import fs from "node:fs";
import path from "node:path";

/**
 * Where this project's sign-in and sheet link live: `<cwd>/.bugsheet/`, or `BUGSHEET_HOME`.
 *
 * Per project on purpose — each project has its own bug sheet, and the folder is git-ignored,
 * so the client secret and refresh token never reach a commit.
 */
export function homeDir() {
  return path.resolve(process.env.BUGSHEET_HOME || path.join(process.cwd(), ".bugsheet"));
}

const CREDENTIALS = "credentials.json";
const CONFIG = "config.json";

function readJson(file) {
  const full = path.join(homeDir(), file);
  if (!fs.existsSync(full)) return null;
  try {
    return JSON.parse(fs.readFileSync(full, "utf8"));
  } catch (e) {
    throw new Error(`Could not read ${full}: ${e.message}`);
  }
}

function writeJson(file, data, { secret = false } = {}) {
  const dir = homeDir();
  fs.mkdirSync(dir, { recursive: true });
  const full = path.join(dir, file);
  fs.writeFileSync(full, JSON.stringify(data, null, 2) + "\n", { mode: secret ? 0o600 : 0o644 });
  if (secret) {
    try {
      fs.chmodSync(full, 0o600);
    } catch {
      // Windows has no POSIX modes; the folder is git-ignored either way.
    }
  }
  return full;
}

export function readCredentials() {
  return readJson(CREDENTIALS);
}

export function writeCredentials(data) {
  return writeJson(CREDENTIALS, data, { secret: true });
}

export function readConfig() {
  const raw = readJson(CONFIG);
  return raw ? normalizeConfig(raw) : null;
}

const TAB_KEYS = [
  "sheetId",
  "sheetName",
  "headerRow",
  "columns",
  "statusValues",
  "statusSource",
  "fixedStatuses",
];

/**
 * A config always has `tabs: [...]`. The first version linked one tab and kept its keys at
 * the top level; such a file is read as a one-tab config, so it keeps working untouched.
 */
export function normalizeConfig(raw) {
  if (Array.isArray(raw.tabs)) return { verify: {}, ...raw };
  const tab = Object.fromEntries(TAB_KEYS.map((k) => [k, raw[k]]));
  const rest = Object.fromEntries(Object.entries(raw).filter(([k]) => !TAB_KEYS.includes(k)));
  return { verify: {}, ...rest, tabs: [tab] };
}

/**
 * The linked tabs a tool works on: all of them, or the ones named in `tabs`
 * (case-insensitive). An unknown name is an error that lists the linked tabs.
 */
export function tabsFor(config, names = []) {
  const wanted = [].concat(names ?? []).filter(Boolean);
  if (wanted.length === 0) return config.tabs;
  return wanted.map((name) => {
    const tab = config.tabs.find((t) => t.sheetName.toLowerCase() === String(name).toLowerCase());
    if (!tab) {
      throw new Error(
        `Tab "${name}" is not linked. Linked tabs: ${config.tabs.map((t) => `"${t.sheetName}"`).join(", ")}.\n` +
          "Link more by calling link_sheet again.",
      );
    }
    return tab;
  });
}

export function writeConfig(data) {
  return writeJson(CONFIG, data);
}

/** The saved sheet config, or a clear error telling the user to run `init`. */
export function requireConfig() {
  const config = readConfig();
  if (!config) {
    throw new Error(
      `No sheet linked yet (looked in ${homeDir()}). Call link_sheet with the sheet's link.`,
    );
  }
  return config;
}
