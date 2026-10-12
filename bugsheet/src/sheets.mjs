import { getAccessToken } from "./oauth.mjs";

/** A thin Google Sheets API v4 client over `fetch`. Only the calls bugsheet needs. */

const API = "https://sheets.googleapis.com/v4/spreadsheets";
const MAX_TRIES = 4;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Column index (0-based) → letters: 0 → A, 25 → Z, 26 → AA. */
export function columnLetter(index) {
  let n = index + 1;
  let out = "";
  while (n > 0) {
    const rem = (n - 1) % 26;
    out = String.fromCharCode(65 + rem) + out;
    n = Math.floor((n - 1) / 26);
  }
  return out;
}

/** Letters → column index (0-based): A → 0, AA → 26. */
export function columnIndex(letters) {
  let n = 0;
  for (const ch of String(letters).toUpperCase()) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/** `'Tab name'!A1` — a sheet name is always quoted, with inner quotes doubled. */
export function a1(sheetName, ref) {
  return `'${String(sheetName).replace(/'/g, "''")}'!${ref}`;
}

function explain(status, body, spreadsheetId) {
  const message = body?.error?.message ?? "";
  if (status === 403) {
    return (
      "Google says this account cannot access that sheet (403). Share the sheet with the " +
      `Google account you signed in with, with edit rights. ${message}`
    );
  }
  if (status === 404) return `Sheet not found (404). Check the link / id ${spreadsheetId}.`;
  if (status === 400) return `Google rejected the request (400): ${message}`;
  return `Google Sheets error ${status}: ${message}`;
}

async function call(method, spreadsheetId, path, { query, body } = {}) {
  const url = new URL(`${API}/${encodeURIComponent(spreadsheetId)}${path}`);
  for (const [key, value] of Object.entries(query ?? {})) {
    for (const v of [].concat(value)) url.searchParams.append(key, String(v));
  }

  let refreshed = false;
  for (let attempt = 1; ; attempt++) {
    const token = await getAccessToken({ forceRefresh: refreshed });
    const res = await fetch(url, {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.ok) return res.json();

    const data = await res.json().catch(() => null);
    if (res.status === 401 && !refreshed) {
      refreshed = true; // The stored token was revoked or expired early — refresh once.
      continue;
    }
    if ((res.status === 429 || res.status >= 500) && attempt < MAX_TRIES) {
      await sleep(500 * 2 ** (attempt - 1));
      continue;
    }
    throw new Error(explain(res.status, data, spreadsheetId));
  }
}

/** Every tab: `[{ sheetId, title, index }]`. */
export async function listTabs(spreadsheetId) {
  const data = await call("GET", spreadsheetId, "", {
    query: { fields: "properties.title,sheets.properties(sheetId,title,index)" },
  });
  return {
    title: data.properties?.title ?? "",
    tabs: (data.sheets ?? []).map((s) => s.properties),
  };
}

/** Cell values of a range. `render` is FORMATTED_VALUE (what the user sees) or UNFORMATTED_VALUE. */
export async function getValues(spreadsheetId, range, render = "FORMATTED_VALUE") {
  const data = await call("GET", spreadsheetId, `/values/${encodeURIComponent(range)}`, {
    query: { valueRenderOption: render, dateTimeRenderOption: "SERIAL_NUMBER" },
  });
  return data.values ?? [];
}

/** Several ranges in one call, in the same order. */
export async function batchGet(spreadsheetId, ranges, render = "FORMATTED_VALUE") {
  if (ranges.length === 0) return [];
  const data = await call("GET", spreadsheetId, "/values:batchGet", {
    query: { ranges, valueRenderOption: render, dateTimeRenderOption: "SERIAL_NUMBER" },
  });
  return (data.valueRanges ?? []).map((r) => r.values ?? []);
}

/** The data-validation rule of one cell (`'Tab'!J2`), or `null`. */
export async function getValidation(spreadsheetId, range) {
  const data = await call("GET", spreadsheetId, "", {
    query: {
      ranges: range,
      includeGridData: "true",
      fields: "sheets.data.rowData.values.dataValidation",
    },
  });
  return data.sheets?.[0]?.data?.[0]?.rowData?.[0]?.values?.[0]?.dataValidation ?? null;
}

/**
 * Writes single cells. `RAW` keeps a status exactly as given and stores a date serial as a
 * number, so the cell's existing date format still applies.
 */
export async function writeCells(spreadsheetId, cells) {
  if (cells.length === 0) return null;
  return call("POST", spreadsheetId, "/values:batchUpdate", {
    body: {
      valueInputOption: "RAW",
      data: cells.map((c) => ({ range: c.range, values: [[c.value]] })),
    },
  });
}
