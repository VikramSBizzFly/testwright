import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";

/**
 * Talks to the real MCP server over stdio, the way Claude Code does. No Google calls: the
 * settings folder is empty, so every tool stops at "not signed in" / "not linked".
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const home = path.join(here, ".tmp-home");
let server;
let buffer = "";
const waiting = new Map();
let nextId = 1;

function request(method, params = {}) {
  const id = nextId++;
  server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`no reply to ${method}`)), 5000);
    waiting.set(id, (message) => {
      clearTimeout(timer);
      resolve(message);
    });
  });
}

const call = async (name, args = {}) =>
  (await request("tools/call", { name, arguments: args })).result;

before(() => {
  fs.rmSync(home, { recursive: true, force: true });
  server = spawn(process.execPath, [path.join(here, "..", "server", "index.mjs")], {
    env: {
      ...process.env,
      BUGSHEET_HOME: home,
      BUGSHEET_CLIENT_ID: "",
      BUGSHEET_CLIENT_SECRET: "",
    },
    stdio: ["pipe", "pipe", "pipe"],
  });
  server.stdout.on("data", (chunk) => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      const message = JSON.parse(line); // stdout must carry only protocol messages
      waiting.get(message.id)?.(message);
      waiting.delete(message.id);
    }
  });
});

after(() => {
  server.stdin.end();
  fs.rmSync(home, { recursive: true, force: true });
});

test("initialize answers with the server and a supported protocol version", async () => {
  const { result } = await request("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "test", version: "0" },
  });
  assert.equal(result.protocolVersion, "2025-06-18");
  assert.equal(result.serverInfo.name, "bugsheet");
  assert.ok(result.capabilities.tools);
  server.stdin.write(
    `${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`,
  );

  const unknownVersion = await request("initialize", { protocolVersion: "1999-01-01" });
  assert.equal(unknownVersion.result.protocolVersion, "2025-06-18");
});

test("tools/list: every tool, read-only hints, and a forced prompt on the write", async () => {
  const { result } = await request("tools/list");
  const byName = Object.fromEntries(result.tools.map((t) => [t.name, t]));
  assert.deepEqual(Object.keys(byName).sort(), [
    "apply_status_update",
    "get_bug",
    "link_sheet",
    "list_bugs",
    "preview_status_update",
    "set_verify_settings",
    "sheet_info",
    "sign_in",
    "status",
  ]);
  for (const name of ["list_bugs", "get_bug", "sheet_info", "preview_status_update"]) {
    assert.equal(byName[name].annotations.readOnlyHint, true, name);
  }
  assert.equal(byName.apply_status_update.annotations.destructiveHint, true);
  assert.equal(byName.apply_status_update._meta["anthropic/requiresUserInteraction"], true);
  assert.deepEqual(byName.preview_status_update.inputSchema.required, ["updates"]);
  const update = byName.apply_status_update.inputSchema.properties.updates.items;
  assert.deepEqual(update.required, ["ref"]); // status or comment, or both
  assert.ok(update.properties.comment);
  assert.deepEqual(update.properties.commentMode.enum, ["append", "replace"]);
  assert.ok(byName.link_sheet.inputSchema.properties.addDevCommentColumn);
});

test("status before setup says what to do next", async () => {
  const result = await call("status");
  const body = JSON.parse(result.content[0].text);
  assert.equal(body.signedIn, false);
  assert.match(body.oauthClient, /plugin settings/);
  assert.equal(body.sheet, null);
  assert.match(body.next, /\/plugin → bugsheet → Configure/);
});

test("tools fail with a clear message instead of crashing", async () => {
  const signIn = await call("sign_in", { openBrowser: false });
  assert.equal(signIn.isError, true);
  assert.match(signIn.content[0].text, /client ID and secret/);

  const list = await call("list_bugs", { open: true });
  assert.equal(list.isError, true);
  assert.match(list.content[0].text, /No sheet linked yet/);

  const preview = await call("preview_status_update", { updates: [] });
  assert.equal(preview.isError, true);
  assert.match(preview.content[0].text, /at least one update/);
});

test("unknown tool and unknown method are JSON-RPC errors; ping works", async () => {
  assert.equal((await request("tools/call", { name: "nope" })).error.code, -32602);
  assert.equal((await request("resources/list")).error.code, -32601);
  assert.deepEqual((await request("ping")).result, {});
});
