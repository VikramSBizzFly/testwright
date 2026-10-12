/**
 * Understanding a bug sheet without being told its layout: which row is the header, which
 * column holds the bug id, the status, a fixed date, and so on.
 *
 * Pure functions over a grid of strings (`rows[r][c]`), so they are tested without Google.
 */

/** Lowercase, keep letters/digits/#: `Status(QA)` → `statusqa`, `Bug ID` → `bugid`. */
export function normalizeHeader(text) {
  return String(text ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9#]/g, "");
}

/**
 * Known header spellings per field, already normalized. Order of FIELDS is the order fields
 * claim columns in, so `id` wins a column before a vaguer field could.
 */
export const ALIASES = {
  id: [
    "bugid",
    "id",
    "#",
    "srno",
    "sno",
    "slno",
    "bugno",
    "bug#",
    "ticketid",
    "ticket",
    "issueid",
    "defectid",
    "key",
  ],
  status: [
    "status",
    "statusqa",
    "statusdev",
    "bugstatus",
    "qastatus",
    "devstatus",
    "state",
    "currentstatus",
  ],
  fixedDate: [
    "fixeddate",
    "fixdate",
    "datefixed",
    "fixedon",
    "resolveddate",
    "resolvedon",
    "closeddate",
    "closedon",
    "dateresolved",
  ],
  title: [
    "bugdescription",
    "description",
    "summary",
    "title",
    "bugtitle",
    "bugsummary",
    "issue",
    "issuedescription",
    "defectdescription",
  ],
  module: ["module", "feature", "area", "component", "section", "page"],
  severity: ["severity"],
  priority: ["priority"],
  reporter: ["reporter", "reportedby", "raisedby"],
  foundDate: [
    "founddate",
    "reporteddate",
    "dateraised",
    "createddate",
    "date",
    "reportedon",
    "foundon",
  ],
  // The developer's note on a bug. "QA Comments" is QA's own column and deliberately not here.
  devComment: [
    "devcomment",
    "devcomments",
    "developercomment",
    "developercomments",
    "devremark",
    "devremarks",
    "devnote",
    "devnotes",
    "commentsdev",
    "commentdev",
  ],
};

export const FIELDS = Object.keys(ALIASES);
export const REQUIRED_FIELDS = ["id", "status"];

/** Fields a header could be. A status variant such as `Dev status` or `Status - QA` counts too. */
export function fieldsForHeader(header) {
  const norm = normalizeHeader(header);
  if (!norm) return [];
  const out = FIELDS.filter((field) => ALIASES[field].includes(norm));
  if (!out.includes("status") && (norm.startsWith("status") || norm.endsWith("status"))) {
    out.push("status");
  }
  return out;
}

/**
 * The header row: of the first `maxScan` rows, the one matching the most distinct fields,
 * needing at least two. Earliest row wins a tie. Returns a 0-based index, or -1.
 */
export function detectHeaderRow(rows, maxScan = 15) {
  let best = -1;
  let bestScore = 1;
  for (let r = 0; r < Math.min(rows.length, maxScan); r++) {
    const fields = new Set((rows[r] ?? []).flatMap((cell) => fieldsForHeader(cell)));
    const score = fields.size + (fields.has("id") ? 1 : 0) + (fields.has("status") ? 1 : 0);
    if (score > bestScore) {
      best = r;
      bestScore = score;
    }
  }
  return best;
}

/**
 * Field → column index for one header row.
 *
 * `overrides` (`{ status: "Status(Dev)" }` or `{ status: "K" }`) win outright. A required
 * field matching several columns is reported in `ambiguous` instead of guessed — two status
 * columns (QA and Dev) is common, and picking the wrong one writes to the wrong column.
 */
export function mapColumns(headerCells, overrides = {}) {
  const columns = Object.fromEntries(FIELDS.map((f) => [f, null]));
  const ambiguous = {};
  const taken = new Set();

  for (const [field, wanted] of Object.entries(overrides)) {
    if (!FIELDS.includes(field))
      throw new Error(`Unknown field "${field}". Known: ${FIELDS.join(", ")}`);
    const index = resolveColumnRef(headerCells, wanted);
    if (index < 0) {
      throw new Error(`No column "${wanted}" in the header row: ${listHeaders(headerCells)}`);
    }
    columns[field] = index;
    taken.add(index);
  }

  for (const field of FIELDS) {
    if (columns[field] !== null) continue;
    const candidates = [];
    headerCells.forEach((cell, index) => {
      if (!taken.has(index) && fieldsForHeader(cell).includes(field)) candidates.push(index);
    });
    if (candidates.length === 0) continue;
    if (candidates.length > 1 && REQUIRED_FIELDS.includes(field)) {
      // An exact `Bug ID` beats a plain `ID`; otherwise the user has to choose.
      const exact = candidates.filter((i) => normalizeHeader(headerCells[i]) === ALIASES[field][0]);
      if (exact.length !== 1) {
        ambiguous[field] = candidates;
        continue;
      }
      candidates.splice(0, candidates.length, exact[0]);
    }
    columns[field] = candidates[0];
    taken.add(candidates[0]);
  }

  const missing = REQUIRED_FIELDS.filter((f) => columns[f] === null && !ambiguous[f]);
  return { columns, ambiguous, missing };
}

/**
 * Is this tab a bug tab? `{ ok: true, headerRow, headerCells, columns, ambiguous }` when it
 * has an id and a status column (`ambiguous` may still need a choice), or
 * `{ ok: false, reason }` for a summary, list or chart tab.
 */
export function analyzeTab(rows, overrides = {}) {
  const headerRow = detectHeaderRow(rows);
  if (headerRow < 0) {
    return { ok: false, reason: "no header row with bug columns in the first 15 rows" };
  }
  const headerCells = rows[headerRow];
  let mapped;
  try {
    mapped = mapColumns(headerCells, overrides);
  } catch (e) {
    return { ok: false, headerRow, headerCells, reason: e.message };
  }
  if (mapped.missing.length > 0) {
    return {
      ok: false,
      headerRow,
      headerCells,
      reason: `no ${mapped.missing.join(" / ")} column in row ${headerRow + 1} (headers: ${listHeaders(headerCells)})`,
    };
  }
  return { ok: true, headerRow, headerCells, ...mapped };
}

/** A header text (case/punctuation-insensitive) or a column letter → index, or -1. */
export function resolveColumnRef(headerCells, ref) {
  const text = String(ref ?? "").trim();
  if (/^[A-Z]{1,3}$/.test(text)) {
    let n = 0;
    for (const ch of text) n = n * 26 + (ch.charCodeAt(0) - 64);
    return n - 1;
  }
  const norm = normalizeHeader(text);
  return headerCells.findIndex((cell) => normalizeHeader(cell) === norm && norm !== "");
}

export function listHeaders(headerCells) {
  return headerCells
    .map((h) => String(h ?? "").trim())
    .filter(Boolean)
    .map((h) => `"${h}"`)
    .join(", ");
}

/** Allowed values from a data-validation rule (a dropdown), or `null` when it has none. */
export function statusValuesFromValidation(rule) {
  const condition = rule?.condition;
  if (condition?.type !== "ONE_OF_LIST") return null;
  const values = (condition.values ?? []).map((v) => String(v.userEnteredValue ?? "").trim());
  // A dropdown can list the same value twice; keep the first spelling.
  const seen = new Set();
  return values.filter((v) => {
    const key = v.toLowerCase();
    if (!v || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/** 0-based index of the first empty header cell — where a missing column can be added. */
export function firstEmptyHeaderColumn(headerCells) {
  const cells = headerCells ?? [];
  const empty = cells.findIndex((cell) => String(cell ?? "").trim() === "");
  return empty < 0 ? cells.length : empty;
}

/**
 * The login in a row's test data, as QA writes it:
 * `Agent email - varun@yopmail.com\nPassword - Varun@741852`, `Email- x Password- y`,
 * `Manager email- x`… Returns `{ email, password }`, or `null` when there is no email.
 */
export function parseTestLogin(text) {
  const value = String(text ?? "");
  const email = value.match(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/)?.[0];
  if (!email) return null;
  const password = value.match(/pass(?:word)?\s*[-:=]\s*(\S+)/i)?.[1] ?? null;
  return { email, password };
}

/** The range a ONE_OF_RANGE dropdown reads from (`=Lists!A2:A9` → `Lists!A2:A9`), or `null`. */
export function validationSourceRange(rule) {
  const condition = rule?.condition;
  if (condition?.type !== "ONE_OF_RANGE") return null;
  const value = condition.values?.[0]?.userEnteredValue;
  return value ? String(value).replace(/^=/, "") : null;
}

/** Distinct non-empty values in a column below the header, first-seen order. */
export function distinctColumnValues(rows, headerRow, column) {
  const seen = new Map();
  for (let r = headerRow + 1; r < rows.length; r++) {
    const value = String(rows[r]?.[column] ?? "").trim();
    if (value && !seen.has(value.toLowerCase())) seen.set(value.toLowerCase(), value);
  }
  return [...seen.values()];
}

/** Statuses that mean "fixed" — these get the fixed date. */
export function defaultFixedStatuses(statusValues) {
  return statusValues.filter(
    (s) => /fix|resolv|done|complet/i.test(s) && !/not|un|re-?open/i.test(s),
  );
}

/** The sheet's own spelling of a status, matched case- and space-insensitively, or `null`. */
export function canonicalStatus(statusValues, wanted) {
  const norm = (s) => String(s).toLowerCase().replace(/\s+/g, " ").trim();
  return statusValues.find((s) => norm(s) === norm(wanted)) ?? null;
}

// ---------------------------------------------------------------------------
// Dates — written the way the column already holds them
// ---------------------------------------------------------------------------

/**
 * How to write a date into a column, from its existing cells.
 *
 * `rawValues` are UNFORMATTED values. A number there means a real date cell (a serial), so we
 * write a serial too and the cell's own format shows it. Otherwise dates are text, and we copy
 * the shape of the text (`09-10-26`, `2026-10-09`, `9/10/2026`). An empty column gets ISO.
 */
export function detectDateStyle(rawValues) {
  const samples = rawValues
    .map((v) => (typeof v === "string" ? v.trim() : v))
    .filter((v) => v !== "" && v != null);
  if (samples.some((v) => typeof v === "number")) return { kind: "serial" };

  const parsed = samples
    .map((s) => String(s).match(/^(\d{1,4})([-/.])(\d{1,2})\2(\d{2,4})$/))
    .filter(Boolean);
  if (parsed.length === 0)
    return { kind: "text", order: "ymd", sep: "-", pad: true, yearDigits: 4 };

  const [, first, sep, second, last] = parsed[0];
  if (first.length === 4)
    return { kind: "text", order: "ymd", sep, pad: second.length === 2, yearDigits: 4 };
  // Day-first unless some sample cannot be (second part above 12).
  const monthFirst = parsed.some((m) => Number(m[3]) > 12);
  return {
    kind: "text",
    order: monthFirst ? "mdy" : "dmy",
    sep,
    pad: first.length === 2,
    yearDigits: last.length === 2 ? 2 : 4,
  };
}

/** Days since 1899-12-30 — the Sheets date serial for a local calendar date. */
export function toSerial(date) {
  const utc = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
  return Math.round((utc - Date.UTC(1899, 11, 30)) / 86_400_000);
}

/** The value to write for `date` in a column of the given style. */
export function formatDate(date, style) {
  if (style.kind === "serial") return toSerial(date);
  const pad = (n) => (style.pad ? String(n).padStart(2, "0") : String(n));
  const year =
    style.yearDigits === 2 ? String(date.getFullYear()).slice(-2) : String(date.getFullYear());
  const d = pad(date.getDate());
  const m = pad(date.getMonth() + 1);
  const parts =
    style.order === "ymd" ? [year, m, d] : style.order === "mdy" ? [m, d, year] : [d, m, year];
  return parts.join(style.sep);
}

/** `YYYY-MM-DD` → a local Date, or throws. */
export function parseIsoDate(text) {
  const m = String(text).match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) throw new Error(`Use YYYY-MM-DD for --date (got "${text}").`);
  const date = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  if (date.getMonth() !== Number(m[2]) - 1) throw new Error(`Not a real date: ${text}`);
  return date;
}
