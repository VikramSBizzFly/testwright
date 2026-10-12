import readline from "node:readline";

/**
 * A minimal MCP server over stdio: newline-delimited JSON-RPC 2.0, with only what a tools
 * server needs — initialize, ping, tools/list and tools/call. No dependencies.
 *
 * stdout carries the protocol, so nothing else may print there: logs go to stderr.
 */

const SUPPORTED_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];

export const log = (...args) => process.stderr.write(`[bugsheet] ${args.join(" ")}\n`);

/**
 * `tools`: `[{ name, title, description, inputSchema, annotations, handler }]`. A handler gets
 * the arguments and returns a value (sent as JSON text) or throws (sent as a tool error).
 */
export function createServer({ name, version, instructions, tools }) {
  const byName = new Map(tools.map((t) => [t.name, t]));

  async function handle(message) {
    const { id, method, params } = message;
    switch (method) {
      case "initialize": {
        const asked = params?.protocolVersion;
        return {
          protocolVersion: SUPPORTED_VERSIONS.includes(asked) ? asked : SUPPORTED_VERSIONS[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name, version },
          ...(instructions ? { instructions } : {}),
        };
      }
      case "ping":
        return {};
      case "tools/list":
        return {
          tools: tools.map(({ name: n, title, description, inputSchema, annotations, _meta }) => ({
            name: n,
            title,
            description,
            inputSchema,
            annotations,
            ...(_meta ? { _meta } : {}),
          })),
        };
      case "tools/call": {
        const tool = byName.get(params?.name);
        if (!tool) throw rpcError(-32602, `Unknown tool: ${params?.name}`);
        try {
          const result = await tool.handler(params.arguments ?? {});
          const text = typeof result === "string" ? result : JSON.stringify(result, null, 2);
          return { content: [{ type: "text", text }] };
        } catch (e) {
          log(`${tool.name} failed: ${e.message}`);
          return { content: [{ type: "text", text: e.message }], isError: true };
        }
      }
      default:
        if (id === undefined) return undefined; // a notification we do not need
        throw rpcError(-32601, `Method not found: ${method}`);
    }
  }

  function send(payload) {
    process.stdout.write(`${JSON.stringify(payload)}\n`);
  }

  function start() {
    const rl = readline.createInterface({ input: process.stdin, terminal: false });
    rl.on("line", async (line) => {
      if (!line.trim()) return;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
        return;
      }
      const isRequest = message.id !== undefined && message.id !== null;
      try {
        const result = await handle(message);
        if (isRequest) send({ jsonrpc: "2.0", id: message.id, result: result ?? {} });
      } catch (e) {
        if (isRequest) {
          send({
            jsonrpc: "2.0",
            id: message.id,
            error: { code: e.rpcCode ?? -32603, message: e.message },
          });
        }
      }
    });
    rl.on("close", () => process.exit(0));
  }

  return { handle, start };
}

function rpcError(code, message) {
  const e = new Error(message);
  e.rpcCode = code;
  return e;
}
