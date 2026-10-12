/**
 * Google Sheets link → `{ spreadsheetId, gid }`.
 *
 * Accepts a full link (`…/spreadsheets/d/<id>/edit#gid=123`, `?gid=123`, `/htmlview`, …)
 * or a bare spreadsheet id. `gid` is the tab id, or `null` when the link names none.
 */
export function parseSheetUrl(input) {
  const text = String(input ?? "").trim();
  if (!text) throw new Error("No sheet link given.");

  const fromPath = text.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
  const bareId = /^[a-zA-Z0-9_-]{20,}$/.test(text) ? text : null;
  const spreadsheetId = fromPath?.[1] ?? bareId;
  if (!spreadsheetId) {
    throw new Error(
      `That does not look like a Google Sheets link: ${text}\n` +
        "Expected something like https://docs.google.com/spreadsheets/d/<id>/edit#gid=0",
    );
  }

  const gidMatch = text.match(/[#?&]gid=(\d+)/);
  return { spreadsheetId, gid: gidMatch ? Number(gidMatch[1]) : null };
}
