import {
  canonicalStatus,
  detectDateStyle,
  formatDate,
  normalizeHeader,
  resolveColumnRef,
} from "./schema.mjs";
import { a1, batchGet, columnIndex, columnLetter, listTabs, writeCells } from "./sheets.mjs";

/**
 * Loading the linked tabs, and the update itself: find each bug's row (in whichever tab it
 * lives), plan the cell changes, then write only those cells and read them back.
 *
 * A "sheet" below is one loaded tab:
 * `{ tabConfig, tab: { sheetId, title }, rows, headerRow, headerCells, columns }`.
 */

/** Each linked tab as it is now, by id first (survives a rename), then by name. */
export async function resolveTabs(config, tabConfigs) {
  const { tabs } = await listTabs(config.spreadsheetId);
  return tabConfigs.map((tc) => {
    const tab =
      (tc.sheetId != null && tabs.find((t) => t.sheetId === tc.sheetId)) ||
      tabs.find((t) => t.title === tc.sheetName);
    if (!tab) {
      throw new Error(
        `The linked tab "${tc.sheetName}" is gone. Tabs now: ${tabs.map((t) => `"${t.title}"`).join(", ")}.\n` +
          "Call link_sheet again.",
      );
    }
    return { tabConfig: tc, tab };
  });
}

/**
 * Field → column index for the tab as it is now. Columns are found by their header text, so
 * a column moved since `init` is still found; the saved letter is only a fallback.
 */
export function resolveColumns(headerCells, savedColumns) {
  const columns = {};
  const problems = [];
  for (const [field, saved] of Object.entries(savedColumns)) {
    if (!saved) {
      columns[field] = null;
      continue;
    }
    let index = saved.header ? resolveColumnRef(headerCells, saved.header) : -1;
    if (index < 0 && saved.letter) {
      const byLetter = columnIndex(saved.letter);
      // The letter only counts when the header there still matches (or was never recorded).
      if (
        !saved.header ||
        normalizeHeader(headerCells[byLetter]) === normalizeHeader(saved.header)
      ) {
        index = byLetter;
      }
    }
    if (index < 0) problems.push(`${field} ("${saved.header ?? saved.letter}")`);
    columns[field] = index < 0 ? null : index;
  }
  return { columns, problems };
}

/** One loaded tab from its grid. Pure, so tests build sheets without Google. */
export function buildSheet(tabConfig, tab, rows) {
  const headerRow = tabConfig.headerRow - 1;
  const headerCells = rows[headerRow] ?? [];
  const { columns, problems } = resolveColumns(headerCells, tabConfig.columns);
  const missingRequired = problems.filter((p) => p.startsWith("id ") || p.startsWith("status "));
  if (missingRequired.length > 0) {
    throw new Error(
      `Tab "${tab.title}": columns not found in row ${tabConfig.headerRow} any more: ` +
        `${missingRequired.join(", ")}.\nThe sheet layout changed. Call link_sheet again.`,
    );
  }
  return { tabConfig, tab, rows, headerRow, headerCells, columns };
}

/** Every given tab, read in one call. */
export async function loadSheets(config, tabConfigs) {
  const resolved = await resolveTabs(config, tabConfigs);
  const grids = await batchGet(
    config.spreadsheetId,
    resolved.map((r) => a1(r.tab.title, "A1:ZZZ")),
  );
  return resolved.map((r, i) => buildSheet(r.tabConfig, r.tab, grids[i] ?? []));
}

/**
 * Bugs as objects, one per data row with an id. `fields` holds every column by its header,
 * so a reader (or Claude) gets the steps, expected and actual results too.
 */
export function bugRows(sheet) {
  const { rows, headerRow, headerCells, columns, tab } = sheet;
  const out = [];
  for (let r = headerRow + 1; r < rows.length; r++) {
    const row = rows[r] ?? [];
    const id = String(row[columns.id] ?? "").trim();
    if (!id) continue;
    const bug = { tab: tab.title, ref: `${tab.title}:${id}`, rowNumber: r + 1 };
    for (const [field, index] of Object.entries(columns)) {
      bug[field] = index == null ? "" : String(row[index] ?? "").trim();
    }
    bug.fields = {};
    headerCells.forEach((header, i) => {
      const name = String(header ?? "").trim() || columnLetter(i);
      const value = String(row[i] ?? "").trim();
      if (value) bug.fields[name] = value;
    });
    out.push(bug);
  }
  return out;
}

const normalizeId = (value) =>
  String(value ?? "")
    .trim()
    .replace(/^#/, "")
    .toLowerCase();

/** 1-based sheet row numbers whose id cell equals `id` (`61`, `"61"` and `#61` all match). */
export function findRows(rows, headerRow, idColumn, id) {
  const wanted = normalizeId(id);
  const found = [];
  for (let r = headerRow + 1; r < rows.length; r++) {
    if (wanted && normalizeId(rows[r]?.[idColumn]) === wanted) found.push(r + 1);
  }
  return found;
}

/**
 * `"Agent QA:3"` → `{ tab: "Agent QA", id: "3" }`; a plain `"3"` → `{ tab: null, id: "3" }`.
 * Matched against the linked tab names (longest first), so a tab name with a `:` still works
 * and an id that merely contains `:` is not cut up.
 */
export function parseBugRef(ref, tabNames) {
  const text = String(ref ?? "").trim();
  const lower = text.toLowerCase();
  const byLength = [...tabNames].sort((x, y) => y.length - x.length);
  for (const name of byLength) {
    if (lower.startsWith(`${name.toLowerCase()}:`)) {
      return { tab: name, id: text.slice(name.length + 1).trim() };
    }
  }
  return { tab: null, id: text };
}

/**
 * Where a bug lives: `{ ok: true, sheet, rowNumber, id }`, or `{ ok: false, code, message }`
 * with code `missing`, `duplicate` (twice in one tab) or `ambiguous` (in several tabs).
 */
export function findBug(sheets, ref) {
  const { tab, id } = parseBugRef(
    ref,
    sheets.map((s) => s.tab.title),
  );
  const pool = tab ? sheets.filter((s) => s.tab.title === tab) : sheets;
  const hits = pool.flatMap((sheet) =>
    findRows(sheet.rows, sheet.headerRow, sheet.columns.id, id).map((rowNumber) => ({
      sheet,
      rowNumber,
    })),
  );
  const where = (h) => `${h.sheet.tab.title} (row ${h.rowNumber})`;
  if (hits.length === 0) {
    return { ok: false, code: "missing", message: `Bug ${ref} not found.` };
  }
  if (hits.length > 1) {
    const tabs = new Set(hits.map((h) => h.sheet.tab.title));
    if (tabs.size > 1) {
      const first = hits[0].sheet.tab.title;
      return {
        ok: false,
        code: "ambiguous",
        message: `Bug ${ref} is in more than one tab: ${hits.map(where).join(", ")}. Use "${first}:${id}", or limit the call to one tab with "tabs".`,
      };
    }
    return {
      ok: false,
      code: "duplicate",
      message: `Bug ${ref} is in more than one row: ${hits.map(where).join(", ")}. Fix the sheet first.`,
    };
  }
  return { ok: true, sheet: hits[0].sheet, rowNumber: hits[0].rowNumber, id };
}

/** How a bug is named in output: `Tab:61` when several tabs are linked, else `#61`. */
export function bugLabel(sheets, sheet, id) {
  return sheets.length > 1 ? `${sheet.tab.title}:${id}` : `#${id}`;
}

/**
 * The cell changes for a list of requests, without writing anything.
 *
 * - `requests`: `[{ id, status, date? }]` — `id` may be `Tab:61`; `date` is a JS Date.
 * - `options`: `{ dateStyles: Map<sheetId, style>, today, force }`. Allowed and fixed
 *   statuses come from each tab's own config, because tabs can differ.
 *
 * Returns `{ changes, unchanged, errors }`. A bad id or status is an error for that request
 * only; the rest still go through.
 */
export function planUpdates(sheets, requests, options) {
  const { dateStyles = new Map(), today, force = false } = options;
  const changes = [];
  const unchanged = [];
  const errors = [];

  for (const request of requests) {
    const found = findBug(sheets, request.id);
    if (!found.ok) {
      errors.push({ id: request.id, code: found.code, message: found.message });
      continue;
    }
    const { sheet, rowNumber, id } = found;
    const { statusValues = [], fixedStatuses = [] } = sheet.tabConfig;
    const label = bugLabel(sheets, sheet, id);

    const wantsStatus = request.status != null && String(request.status).trim() !== "";
    const wantsComment = request.comment != null && String(request.comment).trim() !== "";
    if (!wantsStatus && !wantsComment) {
      errors.push({
        id: request.id,
        code: "empty",
        message: `${label}: give a status, a comment, or both.`,
      });
      continue;
    }

    const { columns } = sheet;
    if (wantsComment && columns.devComment == null) {
      errors.push({
        id: request.id,
        code: "no_comment_column",
        message: `${label}: tab "${sheet.tab.title}" has no Dev Comment column. Call link_sheet with addDevCommentColumn: true to add one.`,
      });
      continue;
    }

    const row = sheet.rows[rowNumber - 1] ?? [];
    const cells = [];
    const currentStatus = String(row[columns.status] ?? "").trim();
    let status = currentStatus;
    if (wantsStatus) {
      status = canonicalStatus(statusValues, request.status);
      if (!status) {
        if (!force) {
          errors.push({
            id: request.id,
            code: "status",
            message: `${label}: "${request.status}" is not a status in tab "${sheet.tab.title}". Allowed: ${statusValues.join(", ")} (or set force).`,
          });
          continue;
        }
        status = String(request.status).trim();
      }
    }
    const statusChanges = currentStatus !== status;
    if (statusChanges) {
      cells.push(cell(sheet, columns.status, rowNumber, "status", currentStatus, status));
    }

    if (wantsComment) {
      const currentComment = String(row[columns.devComment] ?? "").trim();
      const comment = nextComment(currentComment, request.comment, today, request.commentMode);
      if (comment !== currentComment) {
        cells.push(
          cell(sheet, columns.devComment, rowNumber, "devComment", currentComment, comment),
        );
      }
    }

    // The fixed date follows a change *to* a fixed status, or an explicit --date.
    const wantsDate =
      columns.fixedDate != null &&
      (request.date ||
        (statusChanges && fixedStatuses.some((s) => s.toLowerCase() === status.toLowerCase())));
    if (wantsDate) {
      const dateStyle = dateStyles.get(sheet.tab.sheetId) ?? detectDateStyle([]);
      const date = request.date ?? today;
      const value = formatDate(date, dateStyle);
      const currentDate = String(row[columns.fixedDate] ?? "").trim();
      const display = dateStyle.kind === "serial" ? isoDate(date) : value;
      if (currentDate !== display) {
        const c = cell(sheet, columns.fixedDate, rowNumber, "fixedDate", currentDate, value);
        c.display = display;
        cells.push(c);
      }
    }

    const base = { ref: request.id, label, id, tab: sheet.tab.title, sheet, rowNumber };
    if (cells.length === 0) unchanged.push({ ...base, status: currentStatus });
    else changes.push({ ...base, cells });
  }
  return { changes, unchanged, errors };
}

/**
 * The Dev Comment after adding `text`: a dated line `[YYYY-MM-DD] text`.
 *
 * - `append` (default) keeps what is there and adds the line below it — the cell becomes the
 *   bug's history. If the last line already says the same thing, nothing changes.
 * - `replace` writes the dated line alone.
 */
export function nextComment(current, text, date, mode = "append") {
  const note = String(text).trim();
  const entry = `[${isoDate(date)}] ${note}`;
  const existing = String(current ?? "").trim();
  if (mode === "replace" || existing === "") return entry;
  const lastLine = existing
    .split(/\r?\n/)
    .pop()
    .replace(/^\[\d{4}-\d{2}-\d{2}\]\s*/, "")
    .trim();
  if (lastLine === note) return existing;
  return `${existing}\n${entry}`;
}

function cell(sheet, column, rowNumber, field, from, to) {
  return {
    field,
    header: String(sheet.headerCells[column] ?? "").trim() || columnLetter(column),
    column,
    range: a1(sheet.tab.title, `${columnLetter(column)}${rowNumber}`),
    from,
    to,
    display: String(to),
  };
}

export function isoDate(date) {
  const p = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())}`;
}

/** How each tab's fixed-date column holds dates today: `Map<sheetId, style>`, one call. */
export async function readDateStyles(config, sheets) {
  const withDate = sheets.filter((s) => s.columns.fixedDate != null);
  const raw = await batchGet(
    config.spreadsheetId,
    withDate.map((s) => {
      const letter = columnLetter(s.columns.fixedDate);
      return a1(s.tab.title, `${letter}${s.headerRow + 2}:${letter}`);
    }),
    "UNFORMATTED_VALUE",
  );
  return new Map(
    withDate.map((s, i) => [s.tab.sheetId, detectDateStyle((raw[i] ?? []).map((r) => r[0]))]),
  );
}

/**
 * Writes a plan. Right before writing it re-reads each target row's id cell: if a row moved
 * (someone sorted or inserted rows since we read), nothing is written. Then it reads the
 * written cells back and reports each one.
 */
export async function applyPlan(config, plan) {
  const idRanges = plan.changes.map((c) =>
    a1(c.sheet.tab.title, `${columnLetter(c.sheet.columns.id)}${c.rowNumber}`),
  );
  const idsNow = await batchGet(config.spreadsheetId, idRanges);
  const moved = plan.changes.filter(
    (c, i) => normalizeId(idsNow[i]?.[0]?.[0]) !== normalizeId(c.id),
  );
  if (moved.length > 0) {
    throw new Error(
      `The sheet changed while we were working (rows moved for ${moved.map((m) => m.label).join(", ")}). ` +
        "Nothing was written. Run the command again.",
    );
  }

  const cells = plan.changes.flatMap((c) => c.cells);
  await writeCells(
    config.spreadsheetId,
    cells.map((c) => ({ range: c.range, value: c.to })),
  );

  const after = await batchGet(
    config.spreadsheetId,
    cells.map((c) => c.range),
  );
  return cells.map((c, i) => {
    const now = String(after[i]?.[0]?.[0] ?? "").trim();
    // A date serial reads back formatted, so only check that the cell is filled.
    const ok = c.field === "fixedDate" ? now !== "" : now === String(c.to);
    return { ...c, now, ok };
  });
}
