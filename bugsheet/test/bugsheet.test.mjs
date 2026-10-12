import assert from "node:assert/strict";
import { test } from "node:test";
import { bugForOutput, columnsForTab, mergeDeep } from "../server/tools.mjs";
import { normalizeConfig } from "../src/config.mjs";
import {
  analyzeTab,
  canonicalStatus,
  defaultFixedStatuses,
  detectDateStyle,
  detectHeaderRow,
  firstEmptyHeaderColumn,
  formatDate,
  mapColumns,
  normalizeHeader,
  parseIsoDate,
  parseTestLogin,
  statusValuesFromValidation,
  toSerial,
} from "../src/schema.mjs";
import { a1, columnIndex, columnLetter } from "../src/sheets.mjs";
import {
  bugRows,
  buildSheet,
  findBug,
  findRows,
  nextComment,
  parseBugRef,
  planUpdates,
  resolveColumns,
} from "../src/update.mjs";
import { parseSheetUrl } from "../src/url.mjs";

// The real QA sheet's header, with a title row and a blank row above it.
const HEADER = [
  "Bug ID",
  "Module",
  "Bug Description",
  "Steps to Reproduce",
  "Expected Result",
  "Actual Result",
  "Test data",
  "Status(QA)",
  "QA Comments",
  "Severity",
  "Priority",
  "Reporter",
  "Environment",
  "Access Link",
  "Bug Link",
  "found date",
];
const GRID = [
  ["Salesforge QA bug sheet"],
  [],
  HEADER,
  [
    "61",
    "Roles & permission",
    "Assign/Unassign missing for Manager",
    "",
    "",
    "",
    "",
    "Open",
    "",
    "",
    "",
    "Shweta",
    "",
    "",
    "",
    "09-10-26",
  ],
  [
    "62",
    "Roles & permission",
    "Assign/Unassign missing for Team leader",
    "",
    "",
    "",
    "",
    "Open",
    "",
    "",
    "",
    "Shweta",
    "",
    "",
    "",
    "09-10-26",
  ],
  [
    "1",
    "My Queue",
    "Leads shown with none assigned",
    "",
    "",
    "",
    "",
    "Fixed",
    "",
    "",
    "",
    "Shweta",
    "",
    "",
    "",
    "09-10-26",
  ],
];

test("parseSheetUrl: link with #gid, ?gid, none, and a bare id", () => {
  const id = "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789";
  assert.deepEqual(parseSheetUrl(`https://docs.google.com/spreadsheets/d/${id}/edit#gid=12345`), {
    spreadsheetId: id,
    gid: 12345,
  });
  assert.deepEqual(
    parseSheetUrl(`https://docs.google.com/spreadsheets/d/${id}/edit?usp=sharing&gid=7`),
    { spreadsheetId: id, gid: 7 },
  );
  assert.deepEqual(parseSheetUrl(`https://docs.google.com/spreadsheets/d/${id}/edit`), {
    spreadsheetId: id,
    gid: null,
  });
  assert.deepEqual(parseSheetUrl(id), { spreadsheetId: id, gid: null });
  assert.throws(() => parseSheetUrl("https://example.com/not-a-sheet"), /does not look like/);
});

test("columns: letters and A1 ranges", () => {
  assert.equal(columnLetter(0), "A");
  assert.equal(columnLetter(25), "Z");
  assert.equal(columnLetter(26), "AA");
  assert.equal(columnIndex("AA"), 26);
  assert.equal(a1("Bug's sheet", "H4"), "'Bug''s sheet'!H4");
});

test("normalizeHeader strips case and punctuation", () => {
  assert.equal(normalizeHeader("Status(QA)"), "statusqa");
  assert.equal(normalizeHeader(" Bug ID "), "bugid");
});

test("detectHeaderRow skips a title row and blank rows", () => {
  assert.equal(detectHeaderRow(GRID), 2);
  assert.equal(detectHeaderRow([["hello"], ["world"]]), -1);
});

test("mapColumns finds Bug ID, Status(QA) and the optional fields", () => {
  const { columns, ambiguous, missing } = mapColumns(HEADER);
  assert.equal(columns.id, 0);
  assert.equal(columns.status, 7);
  assert.equal(columns.title, 2);
  assert.equal(columns.module, 1);
  assert.equal(columns.foundDate, 15);
  assert.equal(columns.fixedDate, null);
  assert.deepEqual(ambiguous, {});
  assert.deepEqual(missing, []);
});

test("mapColumns: two status columns are ambiguous unless a column choice picks one", () => {
  const header = ["Bug ID", "Status(QA)", "Status(Dev)", "Fixed date"];
  const first = mapColumns(header);
  assert.deepEqual(first.ambiguous, { status: [1, 2] });
  const picked = mapColumns(header, { status: "Status(Dev)" });
  assert.equal(picked.columns.status, 2);
  assert.equal(picked.columns.fixedDate, 3);
  assert.equal(mapColumns(header, { status: "B" }).columns.status, 1);
  assert.throws(() => mapColumns(header, { status: "Nope" }), /No column "Nope"/);
});

test("mapColumns reports a missing required column", () => {
  assert.deepEqual(mapColumns(["Title", "Owner"]).missing, ["id", "status"]);
});

test("status values: dropdown, canonical spelling, fixed statuses", () => {
  const rule = {
    condition: {
      type: "ONE_OF_LIST",
      values: [
        { userEnteredValue: "Open" },
        { userEnteredValue: "Fixed" },
        { userEnteredValue: "Reopen" },
        { userEnteredValue: "Closed" },
      ],
    },
  };
  const values = statusValuesFromValidation(rule);
  assert.deepEqual(values, ["Open", "Fixed", "Reopen", "Closed"]);
  assert.equal(canonicalStatus(values, "fixed"), "Fixed");
  assert.equal(canonicalStatus(values, "Fxed"), null);
  assert.deepEqual(defaultFixedStatuses(["Open", "Fixed", "Not fixed", "Resolved", "Reopen"]), [
    "Fixed",
    "Resolved",
  ]);
  assert.equal(statusValuesFromValidation(null), null);
});

test("dates: follow the column's own format", () => {
  const oct9 = new Date(2026, 9, 9);
  assert.equal(formatDate(oct9, detectDateStyle(["09-10-26"])), "09-10-26");
  assert.equal(formatDate(oct9, detectDateStyle(["2026-01-31"])), "2026-10-09");
  assert.equal(formatDate(oct9, detectDateStyle(["12/25/2026"])), "10/09/2026");
  assert.equal(formatDate(oct9, detectDateStyle(["9/1/2026"])), "9/10/2026");
  assert.equal(formatDate(oct9, detectDateStyle([])), "2026-10-09");
  const serial = detectDateStyle([46000, ""]);
  assert.deepEqual(serial, { kind: "serial" });
  assert.equal(formatDate(new Date(1899, 11, 31), serial), 1);
  assert.equal(toSerial(new Date(2026, 9, 9)), 46304);
  assert.throws(() => parseIsoDate("09-10-2026"), /YYYY-MM-DD/);
  assert.throws(() => parseIsoDate("2026-02-31"), /Not a real date/);
});

test("link_sheet column choices: all tabs, one tab (case-insensitive), merged", () => {
  const columns = { "*": { status: "Status(QA)" }, "Agent QA": { status: "Status(Dev)", id: "B" } };
  assert.deepEqual(columnsForTab(columns, "Sales QA"), { status: "Status(QA)" });
  assert.deepEqual(columnsForTab(columns, "agent qa"), { status: "Status(Dev)", id: "B" });
  assert.deepEqual(columnsForTab(undefined, "x"), {});
});

test("verify settings merge without losing logins", () => {
  assert.deepEqual(
    mergeDeep({ appUrl: "x", logins: { qa: "Q" } }, { appUrl: "y", logins: { admin: "A,B" } }),
    { appUrl: "y", logins: { qa: "Q", admin: "A,B" } },
  );
});

const STATUSES = { statusValues: ["Open", "Fixed", "Reopen"], fixedStatuses: ["Fixed"] };

/** A loaded tab, the way `loadSheets` builds it, from a grid. */
function sheetFrom(grid, title = "Bugs", sheetId = 0, statuses = STATUSES) {
  const result = analyzeTab(grid);
  assert.ok(result.ok, result.reason);
  const columns = Object.fromEntries(
    Object.entries(result.columns).map(([f, i]) => [
      f,
      i == null ? null : { letter: columnLetter(i), header: result.headerCells[i] },
    ]),
  );
  const tabConfig = {
    sheetId,
    sheetName: title,
    headerRow: result.headerRow + 1,
    columns,
    ...statuses,
  };
  return buildSheet(tabConfig, { sheetId, title }, grid);
}

test("findRows matches 61, '61' and '#61'", () => {
  const sheet = sheetFrom(GRID);
  assert.deepEqual(findRows(GRID, sheet.headerRow, 0, 61), [4]);
  assert.deepEqual(findRows(GRID, sheet.headerRow, 0, "#61"), [4]);
  assert.deepEqual(findRows(GRID, sheet.headerRow, 0, "999"), []);
});

test("planUpdates: change, no-op, unknown id, bad status, duplicate id, fixed date", () => {
  const grid = [...GRID.map((r) => [...r]), ["62", "dup"]];
  grid[2] = [...HEADER, "Fixed date"];
  const sheet = sheetFrom(grid);
  assert.equal(sheet.columns.fixedDate, 16);
  const options = {
    dateStyles: new Map([[0, detectDateStyle(["09-10-26"])]]),
    today: new Date(2026, 9, 9),
  };
  const plan = planUpdates(
    [sheet],
    [
      { id: "61", status: "fixed" },
      { id: "1", status: "Fixed" },
      { id: "999", status: "Fixed" },
      { id: "61", status: "Fxed" },
      { id: "62", status: "Fixed" },
    ],
    options,
  );
  assert.equal(plan.changes.length, 1);
  const [change] = plan.changes;
  assert.equal(change.rowNumber, 4);
  assert.deepEqual(
    change.cells.map((c) => [c.range, c.from, c.to]),
    [
      ["'Bugs'!H4", "Open", "Fixed"],
      ["'Bugs'!Q4", "", "09-10-26"],
    ],
  );
  assert.deepEqual(
    plan.unchanged.map((u) => u.id),
    ["1"],
  );
  assert.deepEqual(
    plan.errors.map((e) => [e.id, e.code]),
    [
      ["999", "missing"],
      ["61", "status"],
      ["62", "duplicate"],
    ],
  );

  // --force lets a value outside the dropdown through; a status-only sheet gets no date.
  const forced = planUpdates([sheetFrom(GRID)], [{ id: "61", status: "Ready for QA" }], {
    ...options,
    force: true,
  });
  assert.deepEqual(
    forced.changes[0].cells.map((c) => c.to),
    ["Ready for QA"],
  );
});

test("resolveColumns finds a moved column by its header", () => {
  const saved = {
    id: { letter: "A", header: "Bug ID" },
    status: { letter: "H", header: "Status(QA)" },
    fixedDate: null,
  };
  const moved = ["Module", "Bug ID", "Status(QA)"];
  const { columns, problems } = resolveColumns(moved, saved);
  assert.deepEqual(columns, { id: 1, status: 2, fixedDate: null });
  assert.deepEqual(problems, []);
  assert.deepEqual(resolveColumns(["Module"], saved).problems, [
    'id ("Bug ID")',
    'status ("Status(QA)")',
  ]);
});

// ---------------------------------------------------------------------------
// Several tabs
// ---------------------------------------------------------------------------

const AGENT_TAB = [
  ["Bug ID", "Module", "Bug Description", "Status(QA)", "Fixed date"],
  ["1", "My Queue", "Agent sees pool leads", "Open", ""],
  ["61", "Leads", "Agent can edit with Edit off", "Open", ""],
];

test("analyzeTab: a bug tab is linked, a summary tab is skipped", () => {
  assert.equal(analyzeTab(GRID).ok, true);
  const summary = analyzeTab([
    ["Module", "Count"],
    ["Leads", "4"],
  ]);
  assert.equal(summary.ok, false);
  assert.match(summary.reason, /no header row/);
  const noStatus = analyzeTab([
    ["Bug ID", "Bug Description", "Module"],
    ["1", "x", "y"],
  ]);
  assert.equal(noStatus.ok, false);
  assert.match(noStatus.reason, /no status column/);
});

test("parseBugRef: tab prefix, tab names with a colon, plain ids", () => {
  const tabs = ["Sales QA", "Round 2: Agents"];
  assert.deepEqual(parseBugRef("Sales QA:61", tabs), { tab: "Sales QA", id: "61" });
  assert.deepEqual(parseBugRef("sales qa: 61", tabs), { tab: "Sales QA", id: "61" });
  assert.deepEqual(parseBugRef("Round 2: Agents:3", tabs), { tab: "Round 2: Agents", id: "3" });
  assert.deepEqual(parseBugRef("61", tabs), { tab: null, id: "61" });
  assert.deepEqual(parseBugRef("ABC:7", tabs), { tab: null, id: "ABC:7" });
});

test("findBug across tabs: found, ambiguous, scoped by tab, missing", () => {
  const sales = sheetFrom(GRID, "Sales QA", 0);
  const agent = sheetFrom(AGENT_TAB, "Agent QA", 812);
  const sheets = [sales, agent];

  const only = findBug(sheets, "62");
  assert.equal(only.ok, true);
  assert.equal(only.sheet.tab.title, "Sales QA");

  const both = findBug(sheets, "61");
  assert.equal(both.ok, false);
  assert.equal(both.code, "ambiguous");
  assert.match(both.message, /Sales QA \(row 4\), Agent QA \(row 3\)/);

  const scoped = findBug(sheets, "Agent QA:61");
  assert.equal(scoped.ok, true);
  assert.equal(scoped.rowNumber, 3);

  assert.equal(findBug(sheets, "Agent QA:62").code, "missing");
});

test("planUpdates across two tabs uses each tab's own columns and statuses", () => {
  const sales = sheetFrom(GRID, "Sales QA", 0);
  const agent = sheetFrom(AGENT_TAB, "Agent QA", 812, {
    statusValues: ["Open", "Done"],
    fixedStatuses: ["Done"],
  });
  const plan = planUpdates(
    [sales, agent],
    [
      { id: "Sales QA:61", status: "Fixed" },
      { id: "Agent QA:1", status: "done" },
      { id: "Agent QA:61", status: "Fixed" }, // "Fixed" is not a status on that tab
      { id: "61", status: "Fixed" }, // in both tabs
    ],
    { dateStyles: new Map([[812, detectDateStyle([])]]), today: new Date(2026, 9, 9) },
  );
  assert.deepEqual(
    plan.changes.map((c) => [c.label, c.cells.map((x) => [x.range, x.to])]),
    [
      ["Sales QA:61", [["'Sales QA'!H4", "Fixed"]]],
      [
        "Agent QA:1",
        [
          ["'Agent QA'!D2", "Done"],
          ["'Agent QA'!E2", "2026-10-09"],
        ],
      ],
    ],
  );
  assert.deepEqual(
    plan.errors.map((e) => [e.id, e.code]),
    [
      ["Agent QA:61", "status"],
      ["61", "ambiguous"],
    ],
  );
});

test("bugRows carries tab, ref and every column", () => {
  const [bug] = bugRows(sheetFrom(AGENT_TAB, "Agent QA", 812));
  assert.equal(bug.tab, "Agent QA");
  assert.equal(bug.ref, "Agent QA:1");
  assert.equal(bug.rowNumber, 2);
  assert.equal(bug.title, "Agent sees pool leads");
  assert.deepEqual(bug.fields, {
    "Bug ID": "1",
    Module: "My Queue",
    "Bug Description": "Agent sees pool leads",
    "Status(QA)": "Open",
  });
});

test("normalizeConfig reads a one-tab config from the first version", () => {
  const old = {
    url: "u",
    spreadsheetId: "s",
    sheetId: 0,
    sheetName: "Bugs",
    headerRow: 1,
    columns: {},
    statusValues: ["Open"],
    statusSource: "dropdown",
    fixedStatuses: [],
  };
  const config = normalizeConfig(old);
  assert.equal(config.tabs.length, 1);
  assert.equal(config.tabs[0].sheetName, "Bugs");
  assert.equal(config.sheetName, undefined);
  assert.deepEqual(config.verify, {});
  assert.equal(normalizeConfig(config).tabs.length, 1);
});

// ---------------------------------------------------------------------------
// Dev Comment, logins from test data, browser-test fields
// ---------------------------------------------------------------------------

/** The real tab layout: QA Comments in I, Dev Comment added at the end (Q). */
const DEV_HEADER = [...HEADER, "Dev Comment"];
const DEV_TAB = [
  DEV_HEADER,
  [
    "3",
    "Leads",
    "Agent can add and edit leads with Add/Edit off",
    "1. Log in as Admin…",
    "The Agent should not be able to add or edit leads",
    "The Agent can add and edit leads",
    "Agent email - varun@yopmail.com\nPassword - Varun@741852",
    "Open",
    "QA note",
    "",
    "",
    "Shweta",
    "browser= googlechrome",
    "https://qa.example.test/leads",
    "video.mp4",
    "09-10-26",
    "",
  ],
  [
    "4",
    "Dialer",
    "x",
    "",
    "",
    "",
    "",
    "Open",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "[2026-10-01] Looked at it",
  ],
];

test("devComment: 'Dev Comment' maps, 'QA Comments' does not", () => {
  const { columns } = mapColumns(DEV_HEADER);
  assert.equal(columns.devComment, 16);
  assert.equal(mapColumns(HEADER).columns.devComment, null);
  for (const h of ["Dev Comments", "Developer comment", "dev remarks", "Comments (Dev)"]) {
    assert.equal(mapColumns(["Bug ID", "Status", h]).columns.devComment, 2, h);
  }
});

test("firstEmptyHeaderColumn: a gap, or the end", () => {
  assert.equal(firstEmptyHeaderColumn(["Bug ID", "Status", "", "Notes"]), 2);
  assert.equal(firstEmptyHeaderColumn(["Bug ID", "Status"]), 2);
  assert.equal(firstEmptyHeaderColumn([]), 0);
});

test("status values from a dropdown are de-duplicated", () => {
  const rule = {
    condition: {
      type: "ONE_OF_LIST",
      values: ["Done", "Open", "Discuss", "Duplicate", "Task", "discuss", "Working"].map((v) => ({
        userEnteredValue: v,
      })),
    },
  };
  assert.deepEqual(statusValuesFromValidation(rule), [
    "Done",
    "Open",
    "Discuss",
    "Duplicate",
    "Task",
    "Working",
  ]);
});

test("parseTestLogin reads the formats QA uses", () => {
  assert.deepEqual(parseTestLogin("Agent email - varun@yopmail.com\nPassword - Varun@741852"), {
    email: "varun@yopmail.com",
    password: "Varun@741852",
  });
  assert.deepEqual(parseTestLogin("Email- salesagencies123@yopmail.com\nPassword- Sales@741852"), {
    email: "salesagencies123@yopmail.com",
    password: "Sales@741852",
  });
  assert.deepEqual(parseTestLogin("Manager email- sai@bizzfly.com Password: Sai@741852"), {
    email: "sai@bizzfly.com",
    password: "Sai@741852",
  });
  assert.deepEqual(parseTestLogin("user@x.io"), { email: "user@x.io", password: null });
  assert.equal(parseTestLogin("100+ characters"), null);
  assert.equal(parseTestLogin(undefined), null);
});

test("nextComment: dated line, append keeps history, same note not repeated, replace", () => {
  const oct9 = new Date(2026, 9, 9);
  assert.equal(nextComment("", "Retested: works", oct9), "[2026-10-09] Retested: works");
  assert.equal(
    nextComment("[2026-10-01] Looked at it", "Retested: works", oct9),
    "[2026-10-01] Looked at it\n[2026-10-09] Retested: works",
  );
  assert.equal(
    nextComment("[2026-10-01] Retested: works", "Retested: works", oct9),
    "[2026-10-01] Retested: works",
  );
  assert.equal(
    nextComment("old", "Retested: works", oct9, "replace"),
    "[2026-10-09] Retested: works",
  );
});

test("planUpdates: status + comment, comment only, no comment column, nothing given", () => {
  const sheet = sheetFrom(DEV_TAB, "Agent-Bug Report", 5, {
    statusValues: ["Done", "Open"],
    fixedStatuses: ["Done"],
  });
  const plain = sheetFrom(AGENT_TAB, "Agent QA", 812);
  const plan = planUpdates(
    [sheet, plain],
    [
      { id: "Agent-Bug Report:3", status: "Done", comment: "Retested: works" },
      { id: "Agent-Bug Report:4", comment: "Retested: still fails" },
      { id: "Agent QA:1", comment: "x" },
      { id: "Agent-Bug Report:3" },
    ],
    { today: new Date(2026, 9, 9) },
  );
  assert.deepEqual(
    plan.changes.map((c) => [c.label, c.cells.map((x) => [x.field, x.range, x.to])]),
    [
      [
        "Agent-Bug Report:3",
        [
          ["status", "'Agent-Bug Report'!H2", "Done"],
          ["devComment", "'Agent-Bug Report'!Q2", "[2026-10-09] Retested: works"],
        ],
      ],
      [
        "Agent-Bug Report:4",
        [
          [
            "devComment",
            "'Agent-Bug Report'!Q3",
            "[2026-10-01] Looked at it\n[2026-10-09] Retested: still fails",
          ],
        ],
      ],
    ],
  );
  assert.deepEqual(
    plan.errors.map((e) => [e.id, e.code]),
    [
      ["Agent QA:1", "no_comment_column"],
      ["Agent-Bug Report:3", "empty"],
    ],
  );
});

test("bugForOutput adds the row's login and access link", () => {
  const sheet = sheetFrom(DEV_TAB, "Agent-Bug Report", 5);
  const [bug] = bugRows(sheet);
  const out = bugForOutput(bug, sheet);
  assert.deepEqual(out.login, { email: "varun@yopmail.com", password: "Varun@741852" });
  assert.equal(out.appUrl, "https://qa.example.test/leads");
  assert.equal(out.devComment, "");
  assert.equal(out.fixStatus, "Fixed");
  const [, second] = bugRows(sheet);
  assert.equal(bugForOutput(second, sheet).login, null);
});
