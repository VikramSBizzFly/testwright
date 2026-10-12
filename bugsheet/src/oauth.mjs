import { spawn } from "node:child_process";
import crypto from "node:crypto";
import http from "node:http";
import { readCredentials, writeCredentials } from "./config.mjs";

/**
 * Google OAuth 2.0 for an installed ("Desktop app") client: a loopback redirect to
 * 127.0.0.1 on a free port, with PKCE. Google allows any port on the loopback address for
 * Desktop clients, so nothing has to be registered beyond the client itself.
 */

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const SCOPE = "https://www.googleapis.com/auth/spreadsheets";
const LOGIN_TIMEOUT_MS = 5 * 60 * 1000;

const base64url = (buf) => buf.toString("base64url");

/** Opens a URL in the default browser. Best effort — the URL is always printed too. */
function openBrowser(url) {
  try {
    const child =
      process.platform === "win32"
        ? // `start` would split the URL at every `&`; rundll32 takes it whole.
          spawn("rundll32", ["url.dll,FileProtocolHandler", url], {
            detached: true,
            stdio: "ignore",
          })
        : spawn(process.platform === "darwin" ? "open" : "xdg-open", [url], {
            detached: true,
            stdio: "ignore",
          });
    child.on("error", () => {});
    child.unref();
  } catch {
    // No browser available (SSH, CI): the user opens the printed URL by hand.
  }
}

async function postToken(params) {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(
      `Google refused the token request: ${data.error ?? res.status}${
        data.error_description ? ` — ${data.error_description}` : ""
      }`,
    );
    err.code = data.error;
    throw err;
  }
  return data;
}

/**
 * The OAuth client. It comes from the plugin's settings (Claude Code asks for it when the
 * plugin is enabled and hands it to the server as environment variables), so the secret is
 * never written to the project.
 */
export function oauthClient() {
  const clientId = process.env.BUGSHEET_CLIENT_ID?.trim();
  const clientSecret = process.env.BUGSHEET_CLIENT_SECRET?.trim();
  if (!clientId || !clientSecret) {
    throw new Error(
      "The Google OAuth client is not set. Enter the client ID and secret in the bugsheet " +
        "plugin's settings (/plugin → bugsheet → Configure), then restart Claude Code.",
    );
  }
  return { clientId, clientSecret };
}

/**
 * Starts the browser sign-in and returns at once with the consent URL; `done` settles when
 * Google redirects back (or after 5 minutes). Starting a new sign-in cancels a pending one.
 */
let pending = null;

export async function startLogin({ openInBrowser = true } = {}) {
  const { clientId, clientSecret } = oauthClient();
  pending?.cancel();

  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash("sha256").update(verifier).digest());
  const state = base64url(crypto.randomBytes(16));

  const server = http.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const redirectUri = `http://127.0.0.1:${server.address().port}`;

  const url = new URL(AUTH_URL);
  url.search = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: SCOPE,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state,
    // A refresh token is only issued with offline access, and only reliably on consent.
    access_type: "offline",
    prompt: "consent",
  }).toString();

  let cancel;
  const code = new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Sign-in timed out after 5 minutes. Start it again.")),
      LOGIN_TIMEOUT_MS,
    );
    cancel = () => {
      clearTimeout(timer);
      reject(new Error("Sign-in was replaced by a newer one."));
    };
    server.on("request", (req, res) => {
      const params = new URL(req.url, redirectUri).searchParams;
      if (!params.has("code") && !params.has("error")) {
        res.writeHead(404).end();
        return;
      }
      const reply = (status, message) => {
        res.writeHead(status, { "content-type": "text/html; charset=utf-8" });
        res.end(`<!doctype html><meta charset="utf-8"><title>bugsheet</title>
<body style="font:16px system-ui;padding:40px">${message}</body>`);
      };
      clearTimeout(timer);
      if (params.get("error")) {
        reply(400, "Sign-in was cancelled. You can close this tab.");
        reject(new Error(`Google sign-in failed: ${params.get("error")}`));
      } else if (params.get("state") !== state) {
        reply(400, "Sign-in check failed. You can close this tab and try again.");
        reject(new Error("Sign-in failed: the state did not match. Start it again."));
      } else {
        reply(200, "bugsheet is signed in. You can close this tab and go back to Claude.");
        resolve(params.get("code"));
      }
    });
  });

  const done = code
    .then(async (authCode) => {
      const token = await postToken({
        code: authCode,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: "authorization_code",
        code_verifier: verifier,
      });
      if (!token.refresh_token) {
        throw new Error(
          "Google did not return a refresh token. Remove the app's access at " +
            "https://myaccount.google.com/permissions and sign in again.",
        );
      }
      const credentials = {
        clientId,
        refreshToken: token.refresh_token,
        accessToken: token.access_token,
        expiresAt: Date.now() + (token.expires_in ?? 3600) * 1000,
        scope: token.scope ?? SCOPE,
      };
      writeCredentials(credentials);
      return credentials;
    })
    .finally(() => server.close());

  const login = { url: url.toString(), state: "waiting", error: null, done, cancel };
  done.then(
    () => {
      login.state = "signed_in";
    },
    (e) => {
      login.state = "failed";
      login.error = e.message;
    },
  );
  pending = login;
  if (openInBrowser) openBrowser(login.url);
  return login;
}

/** The sign-in started by `startLogin` in this process, if any. */
export function pendingLogin() {
  return pending;
}

/** A valid access token, refreshing (and saving) it when it is about to expire. */
export async function getAccessToken({ forceRefresh = false } = {}) {
  const creds = readCredentials();
  if (!creds?.refreshToken) {
    throw new Error("Not signed in to Google yet. Use the sign_in tool first.");
  }
  if (!forceRefresh && creds.accessToken && creds.expiresAt - 60_000 > Date.now()) {
    return creds.accessToken;
  }
  const { clientId, clientSecret } = oauthClient();
  if (creds.clientId && creds.clientId !== clientId) {
    throw new Error(
      "The OAuth client in the plugin settings changed since you signed in. Sign in again.",
    );
  }
  let token;
  try {
    token = await postToken({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: creds.refreshToken,
      grant_type: "refresh_token",
    });
  } catch (e) {
    if (e.code === "invalid_grant" || e.code === "invalid_client") {
      throw new Error(`Your Google sign-in is no longer valid (${e.code}). Sign in again.`);
    }
    throw e;
  }
  writeCredentials({
    ...creds,
    accessToken: token.access_token,
    expiresAt: Date.now() + (token.expires_in ?? 3600) * 1000,
  });
  return token.access_token;
}
