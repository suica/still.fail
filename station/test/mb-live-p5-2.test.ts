// The agents' side as the MoonBit station runs it (station/mb src/station_main live_p5_2_*.mbt): `stillfail-reader run`
// under a launcher of the test's, with no Node on its PATH, its hub's actors in its own `--sessions` program and its
// runtimes under the real `stillfail-runner`. A session's message to another (session_send through `/mcp`) starts the
// other's turn: its `claude` (a fake of /bin/sh and curl, test/fake-sh) asks the tools of the station's door with its
// own token and posts all_done, which the store keeps, and the turn ends so. An Antigravity session is declared the
// tools that fit its budget and `station_tool` for the rest. A handover carries a session to the next process, which
// takes it up and serves on; a drain answers idle once no turn runs; nothing of the runners or programs is left.
import assert from "node:assert/strict";
import { type ChildProcess, spawn, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createSocket } from "node:dgram";
import { type Server, createServer } from "node:net";
import { request } from "node:http";
import { DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { deflateSync } from "node:zlib";
import { createInterface } from "node:readline";
import { after, test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Store } from "../src/store/store.ts";
import { exif, film, jpeg } from "../../client/core-ts/test/media-bytes.ts";

const binary = mbReaderBinary();
const runner = process.env.STILLFAIL_RUNNER ?? "";
const skip = binary === null ? "the MoonBit program (stillfail-reader) is not built here"
  : process.platform === "win32" ? "the launcher's descriptors are Unix's"
  : runner === "" || !existsSync(runner) ? "no stillfail-runner (run under scripts/native.ts run runner)"
  : !existsSync("/usr/bin/curl") ? "no /usr/bin/curl for the fake runtime"
  : false;

const dirs: string[] = [];
// (short: a runner's and the status's Unix sockets are at most 104 bytes on macOS)
const fresh = (what: string) => {
  const dir = mkdtempSync(join(process.platform === "darwin" ? "/tmp" : tmpdir(), `p52-${what}-`));
  dirs.push(dir);
  return dir;
};
const children: ChildProcess[] = [];
after(async () => {
  const left = children.filter((c) => c.exitCode === null && c.signalCode === null);
  for (const c of left) c.kill("SIGKILL");
  await Promise.race([
    Promise.all(left.map((c) => (c.exitCode === null && c.signalCode === null ? new Promise<void>((r) => c.once("exit", () => r())) : undefined))),
    new Promise((r) => setTimeout(r, 5_000).unref()),
  ]);
  // (a runner a failed run left: ended by its pid, as its info file says)
  for (const d of dirs) {
    const runners = join(d, "run", "runners");
    if (!existsSync(runners)) continue;
    for (const info of require_json(runners)) {
      try { process.kill(-(info as any).pgid, "SIGKILL"); } catch {}
      try { process.kill(info.runner, "SIGKILL"); } catch {}
    }
  }
  if (process.env.P52_KEEP !== "1") for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

/// The fake runtimes: `claude` speaking Claude Code's stream-json, `agy` only there to be found. Of /bin/sh and curl
/// alone: the station's PATH names no Node, nor does what it starts.
function fakes(dir: string) {
  // A fake Claude Code TUI, as its bridge runs it under the runner's PTY (claude-tui.mjs, claude_tui.mbt): its startup
  // hook and its tools listed through the bridge's stdio MCP, then each pasted message acknowledged (UserPromptSubmit),
  // answered with chat_post and ended (Stop), its hooks the commands the bridge put in its settings. Of /bin/sh alone.
  const tui = String.raw`#!/bin/sh
sid=""; cfg=""; settings=""
for a in "$@"; do printf '%s\n' "$a"; done > "$FAKE_OUT/tui-argv"
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id|--resume) sid="$2"; shift ;;
    --mcp-config) cfg="$2"; shift ;;
    --settings) settings="$2"; shift ;;
  esac
  shift
done
hook_node=$(printf '%s' "$settings" | /usr/bin/sed -n 's/.*"command":"\([^"]*\)","args":\["\([^"]*\)","hook"\].*/\1/p')
hook_script=$(printf '%s' "$settings" | /usr/bin/sed -n 's/.*"command":"\([^"]*\)","args":\["\([^"]*\)","hook"\].*/\2/p')
mcp_node=$(printf '%s' "$cfg" | /usr/bin/sed -n 's/.*"command":"\([^"]*\)","args":\["\([^"]*\)","mcp","\([^"]*\)"\].*/\1/p')
mcp_url=$(printf '%s' "$cfg" | /usr/bin/sed -n 's/.*"command":"\([^"]*\)","args":\["\([^"]*\)","mcp","\([^"]*\)"\].*/\3/p')
hook() { printf '{"session_id":"%s","hook_event_name":"%s"%s}' "$sid" "$1" "$2" | "$hook_node" "$hook_script" hook; }
hook SessionStart ',"source":"startup"'
fifo="$FAKE_OUT/tui-mcp-$$"
/usr/bin/mkfifo "$fifo"
"$mcp_node" "$hook_script" mcp "$mcp_url" < "$fifo" > "$FAKE_OUT/tui-tools.json" &
exec 3> "$fifo"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' >&3
esc=$(printf '\033')
n=0; text=""
while IFS= read -r line; do
  line=$(printf '%s' "$line" | /usr/bin/tr -d '\r')
  case "$line" in "$esc[200~"*) text="" ; line=$(printf '%s' "$line" | /usr/bin/sed "s/^$esc\[200~//") ;; esac
  case "$line" in
    *"$esc[201~")
      line=$(printf '%s' "$line" | /usr/bin/sed "s/$esc\[201~$//")
      if [ -n "$text" ]; then text="$text
$line"; else text="$line"; fi
      n=$((n+1))
      printf '%s' "$text" > "$FAKE_OUT/tui-prompt-$n"
      json=$(printf '%s' "$text" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g' | /usr/bin/awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}')
      hook UserPromptSubmit ',"prompt":"'"$json"'"'
      to=$(printf '%s' "$text" | /usr/bin/sed -n 's/.*thread="\([^"]*\)".*/\1/p' | /usr/bin/head -n 1)
      if [ -n "$to" ]; then printf '%s' "$to" > "$FAKE_OUT/tui-to"; else to=$(/bin/cat "$FAKE_OUT/tui-to" 2>/dev/null); fi
      /usr/bin/curl -s -X POST "$mcp_url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \
        -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"chat_post","arguments":{"to":"'"$to"'","text":"posted by the TUI","kind":"all_done","done":"the TUI answered"}}}' > "$FAKE_OUT/tui-post-$n.json"
      hook Stop ''
      text="" ;;
    *) if [ -n "$text" ]; then text="$text
$line"; else text="$line"; fi ;;
  esac
done
`;
  writeFileSync(join(dir, "claude-tui"), tui);
  chmodSync(join(dir, "claude-tui"), 0o755);
  const claude = `#!/bin/sh
# A fake Claude Code: stream-json in and out; each prompt asks the station's tools (tools/list) and posts all_done.
# Started with no -p it is the TUI, its bridge's (claude-tui above).
case " $* " in *" -p "*) ;; *) exec "\${0%/*}/claude-tui" "$@" ;; esac
sid=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id|--resume) sid="$2"; shift ;;
    --mcp-config) cfg="$2"; shift ;;
  esac
  shift
done
url=$(printf '%s' "$cfg" | /usr/bin/sed -n 's/.*"url":"\\([^"]*\\)".*/\\1/p')
say() { printf '%s\\n' "$1"; }
n=0
while IFS= read -r line; do
  case "$line" in *'"type":"user"'*) ;; *) continue ;; esac
  n=$((n+1))
  # (each prompt it was given, as it came: what a test reads of what woke it)
  printf '%s\\n' "$line" >> "$FAKE_OUT/prompts"
  # (its init as Claude Code says it: once a turn is given it, never before its first message, which the station reads
  # as a turn begun: said at its start, it was read before the station's first prompt on a busy machine, and that prompt
  # was refused as a turn already running, 1 run in 16 or so)
  say '{"type":"system","subtype":"init","session_id":"'"$sid"'","model":"default","tools":[],"mcp_servers":[]}'
  say '{"type":"system","subtype":"status","status":"requesting","session_id":"'"$sid"'"}'
  to=$(printf '%s' "$line" | /usr/bin/sed -n 's/.*thread=\\\\"\\([^\\\\]*\\)\\\\".*/\\1/p')
  # (a prompt that names no thread, as a resume's: the one it was last asked in, as its conversation would know)
  if [ -n "$to" ]; then printf '%s' "$to" > "$FAKE_OUT/to"; else to=$(/bin/cat "$FAKE_OUT/to" 2>/dev/null); fi
  # (asked to drop MCP mid-session: marks this process PID as broken and returns without calling /mcp on this turn and any subsequent nudge in the same process; once the station kills it and starts a new process with TOOLS_LOST, the new PID runs normally)
  case "$line" in *NUDGE-UNHEARD-DROP*)
    printf '%s' "$$" > "$FAKE_OUT/nudge-unheard-bad-pid"
    say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"lost mcp mid-session"}'
    continue ;;
  esac
  if [ -f "$FAKE_OUT/nudge-unheard-bad-pid" ] && [ "$(/bin/cat "$FAKE_OUT/nudge-unheard-bad-pid")" = "$$" ]; then
    say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"still lost mcp on nudge"}'
    continue
  fi
  # (asked to simulate an agent that only sent initialize/notifications/ping and never called tools/list or tools/call:
  # the first process ends without posting so the MoonBit station's toolsUnheard self-heals and restarts it with TOOLS_LOST)
  case "$line" in *UNHEARD-ONCE*)
    if [ ! -f "$FAKE_OUT/unheard-once-done" ]; then
      : > "$FAKE_OUT/unheard-once-done"
      printf '%s\n' "$$" > "$FAKE_OUT/unheard-pid-1"
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":10,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' > "$FAKE_OUT/unheard-init.json"
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":11,"method":"ping"}' > "$FAKE_OUT/unheard-ping.json"
      say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"no tools"}'
      continue
    fi ;;
  esac
  # (asked to hold unheard across a station handover: signals running, waits for unheard-go, sends only initialize/ping
  # and ends without posting so the adopting station still catches toolsUnheard and restarts with TOOLS_LOST)
  case "$line" in *HOLD-UNHEARD*)
    if [ ! -f "$FAKE_OUT/hold-unheard-done" ]; then
      : > "$FAKE_OUT/hold-unheard-done"
      printf '%s\n' "$$" > "$FAKE_OUT/hold-unheard-pid-1"
      : > "$FAKE_OUT/unheard-running"
      while [ ! -f "$FAKE_OUT/unheard-go" ]; do /bin/sleep 0.05; done
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":12,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' > /dev/null
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":13,"method":"ping"}' > /dev/null
      say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"no tools across handover"}'
      continue
    fi ;;
  esac
  # (asked to hold across a station handover: signals running, waits for the test's go file, then posts all_done and
  # chat_state through the shared MCP door before ending its turn)
  case "$line" in *HOLD-HANDOVER*)
    : > "$FAKE_OUT/mid-running"
    while [ ! -f "$FAKE_OUT/mid-go" ]; do /bin/sleep 0.05; done
    /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
      -d '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"chat_post","arguments":{"to":"'"$to"'","text":"posted across handover","kind":"all_done","done":"finished across handover"}}}' > "$FAKE_OUT/mid-post-$n.json"
    /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
      -d '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"chat_state","arguments":{"kind":"all_done","done":"finished across handover"}}}' > "$FAKE_OUT/mid-state-$n.json"
    say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"posted across handover"}'
    continue ;;
  esac
  # (asked to ask: a card posted with no state, then need_human said with no about, which the card is; told to wait for
  # a write lock first, it says it is about to and waits for the test's word)
  case "$line" in *ASK-CARD*)
    /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
      -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"chat_post","arguments":{"to":"'"$to"'","text":"which one?","card":{"type":"options","options":[{"label":"this"},{"label":"that"}],"assignee":"ada@x.com"}}}}' > "$FAKE_OUT/card-$n.json"
    case "$line" in *ASK-BUSY*)
      : > "$FAKE_OUT/stating"
      while [ ! -f "$FAKE_OUT/state-go" ]; do /bin/sleep 0.05; done ;;
    esac
    /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
      -d '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"chat_state","arguments":{"kind":"need_human","need":"pick one"}}}' > "$FAKE_OUT/ask-$n.json"
    say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"asked"}'
    continue ;;
  esac
  /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' > "$FAKE_OUT/list-$n.json"
  /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"chat_post","arguments":{"to":"'"$to"'","text":"posted by the fake","kind":"all_done","done":"answered what it was sent"}}}' > "$FAKE_OUT/post-$n.json"
  # (and its state recorded again by chat_state: what it reads first is the store's changes (store.subscribe), and an
  # all_done sets the archive's review going (hub.fork))
  /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"chat_state","arguments":{"kind":"all_done","done":"answered what it was sent"}}}' > "$FAKE_OUT/state-$n.json"
  say '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m'$n'","role":"assistant","content":[]}},"parent_tool_use_id":null,"session_id":"'"$sid"'","uuid":"a'$n'"}'
  say '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null,"session_id":"'"$sid"'","uuid":"b'$n'"}'
  say '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"posted"}},"parent_tool_use_id":null,"session_id":"'"$sid"'","uuid":"c'$n'"}'
  say '{"type":"stream_event","event":{"type":"content_block_stop","index":0},"parent_tool_use_id":null,"session_id":"'"$sid"'","uuid":"d'$n'"}'
  say '{"type":"stream_event","event":{"type":"message_stop"},"parent_tool_use_id":null,"session_id":"'"$sid"'","uuid":"e'$n'"}'
  say '{"type":"assistant","message":{"id":"m'$n'","role":"assistant","content":[{"type":"text","text":"posted"}]},"session_id":"'"$sid"'"}'
  say '{"type":"result","subtype":"success","is_error":false,"duration_ms":1,"num_turns":1,"session_id":"'"$sid"'","result":"posted"}'
done
`;
  writeFileSync(join(dir, "claude"), claude);
  chmodSync(join(dir, "claude"), 0o755);
  // A fake DeepSeek Harness as the station's driver plugin speaks for it (dsh-bridge.mjs): a line of JSON a request,
  // its events as the plugin says them; each prompt asks the station's tools and posts all_done.
  const dsh = `#!/bin/sh
url="\${STILLFAIL_PEER_HTTP%/peer}/mcp"
say() { printf '%s\\n' "$1"; }
n=0
while IFS= read -r line; do
  case "$line" in
    *'"op":"open"'*) say '{"id":"open","session":"dsh-s1"}' ;;
    *'"op":"prompt"'*)
      n=$((n+1))
      say '{"ev":"event","type":"turn/start","data":{}}'
      to=$(printf '%s' "$line" | /usr/bin/sed -n 's/.*thread=\\\\"\\([^\\\\]*\\)\\\\".*/\\1/p')
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' > "$FAKE_OUT/dsh-list-$n.json"
      /usr/bin/curl -s -X POST "$url" -H 'content-type: application/json' -H "authorization: Bearer $STILLFAIL_MCP_TOKEN" \\
        -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"chat_post","arguments":{"to":"'"$to"'","text":"posted by dsh","kind":"all_done","done":"dsh answered"}}}' > "$FAKE_OUT/dsh-post-$n.json"
      say '{"ev":"event","type":"turn/end","data":{"reason":{"kind":"completed"}}}' ;;
  esac
done
`;
  writeFileSync(join(dir, "dsh"), dsh);
  chmodSync(join(dir, "dsh"), 0o755);
}

type Launched = { child: ChildProcess; said: any[]; next: (what: string, ok: (m: any) => boolean) => Promise<any>; tell: (m: unknown) => void; ended: Promise<number | null>; err: () => string };

/// The launcher's two listening sockets, the agents' door's and the loopback's; `port` listens again where an ended
/// station's door was, as the launcher keeps it (native/launcher), so a runtime taken up reaches the door it was told.
const listener = (port = 0) => new Promise<Server>((resolve, reject) => {
  const s = createServer();
  s.once("error", reject);
  s.listen(port, "127.0.0.1", () => resolve(s));
});
const ports: Server[] = [];
after(() => {
  for (const s of ports) s.close();
});

async function launch(data: string, app: string, path: string, out: string, sockets?: [Server, Server], more: Record<string, string> = {}): Promise<Launched & { sockets: [Server, Server] }> {
  const [mcp, loop] = sockets ?? [await listener(), await listener()];
  const fd = (s: Server) => (s as any)._handle.fd as number;
  const child = spawn(binary!, ["run", "--app", app, "--data", data, "--launcher-fds", "3,4,5", "--launcher-carries", "--launcher-heartbeat"], {
    stdio: ["ignore", "pipe", "pipe", fd(mcp), fd(loop), "pipe"],
    // (no Node: the PATH the fakes are on, and nothing else)
    // (traced by default: what it says goes into a failure's message only, and Linux CI's rare hang at "the turn's end",
    // `a turn is already running` at a session's first prompt, never came where it could be looked at)
    env: { PATH: path, HOME: data, TMPDIR: tmpdir(), STILLFAIL_RUNNER: runner, STILLFAIL_HELD_EVERY_MS: "300", STILLFAIL_AGENT_NICE: "0", FAKE_OUT: out, STILLFAIL_P52_TRACE: process.env.STILLFAIL_P52_TRACE ?? "1", ...more },
  });
  children.push(child);
  // (the launcher's copies let go: the station alone accepts on them; one kept here would race it for a connection
  // and, with no handler, leave that connection hanging)
  mcp.close();
  loop.close();
  const said: any[] = [];
  const waiters: (() => void)[] = [];
  createInterface({ input: (child.stdio as readonly unknown[])[5] as import("node:net").Socket }).on("line", (line) => {
    said.push(JSON.parse(line));
    for (const w of waiters.splice(0)) w();
  });
  let err = "";
  child.stderr!.on("data", (d) => (err += d));
  const next = (what: string, ok: (m: any) => boolean) =>
    new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`never said: ${what}; said ${JSON.stringify(said)}; stderr ${err}`)), 30_000);
      const look = () => {
        const found = said.find(ok);
        if (found !== undefined) {
          clearTimeout(timer);
          resolve(found);
        } else waiters.push(look);
      };
      look();
    });
  const ended = new Promise<number | null>((resolve) => child.on("exit", (code) => resolve(code)));
  return { child, said, next, tell: (m) => ((child.stdio as readonly unknown[])[5] as import("node:net").Socket).write(`${JSON.stringify(m)}\n`), ended, err: () => err, sockets: [mcp, loop] };
}

/// One JSON-RPC call of the agents' door, with `token` as its bearer (none: no header).
function mcp(port: number, body: unknown, token?: string): Promise<{ status: number; json: any }> {
  return new Promise((resolve, reject) => {
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (token !== undefined) headers.authorization = `Bearer ${token}`;
    const req = request({ host: "127.0.0.1", port, path: "/mcp", method: "POST", headers }, (res) => {
      let text = "";
      res.on("data", (d) => (text += d));
      res.on("end", () => resolve({ status: res.statusCode!, json: text === "" ? null : JSON.parse(text) }));
    });
    req.on("error", reject);
    req.end(JSON.stringify(body));
  });
}

/// Looked at until `ok` (real processes: every 50 ms), or failing with `what` at 60 s.
async function until<T>(what: string, look: () => T | null | undefined | false | Promise<T | null | undefined | false>, detail: () => string = () => ""): Promise<T> {
  const end = Date.now() + 60_000;
  for (;;) {
    const v = await look();
    if (v) return v;
    if (Date.now() > end) throw new Error(`never: ${what}; ${detail()}`);
    await new Promise((r) => setTimeout(r, 50));
  }
}

/// A PNG of `width` by `height` grey pixels, whole: what the station decodes for its ThumbHash.
function png(width: number, height: number): Uint8Array {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (b: Buffer) => {
    let c = 0xffffffff;
    for (const x of b) c = crcTable[(c ^ x) & 0xff]! ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, body: Buffer) => {
    const head = Buffer.alloc(4);
    head.writeUInt32BE(body.length);
    const typed = Buffer.concat([Buffer.from(type, "ascii"), body]);
    const tail = Buffer.alloc(4);
    tail.writeUInt32BE(crc(typed));
    return Buffer.concat([head, typed, tail]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr.set([8, 2, 0, 0, 0], 8);
  const rows = Buffer.alloc((width * 3 + 1) * height, 128);
  for (let y = 0; y < height; y++) rows[y * (width * 3 + 1)] = 0;
  return new Uint8Array(Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))]));
}

/// A session of the station's own chat, its thread, as the store keeps them (lifecycle.ts `newSession`'s rows).
function session(store: Store, data: string, key: string, runtime: string, token: string, ts: string, ws?: string, tui?: boolean) {
  const workspace = join(data, "sessions", "chat", key.slice(5), "workspace");
  mkdirSync(workspace, { recursive: true });
  const now = Date.now();
  store.insertSession({ key, connect: "ember", runtime, profile: runtime === "claude" ? "cc" : runtime === "dsh" ? "ds" : "ag", workspace, token, createdAt: now, lastActiveAt: now, title: `chat ${key}`, ...(ws ? { ws } : {}), ...(tui ? { tui: true } : {}) } as never);
  const thread = store.openThread("ember", "CHAT", ts, `chat ${key}`, "ada@x.com");
  store.joinThread(thread.id, key, "ember");
  return thread;
}

test("the agents' side: a turn under the runner posts through /mcp; agy's tools within its budget; a handover and a drain", { skip }, async () => {
  const data = fresh("d");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  mkdirSync(join(data, "homes", "ag"), { recursive: true });
  mkdirSync(join(data, "homes", "ds"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }, { id: "ag", runtime: "agy", home: "homes/ag" }, { id: "ds", runtime: "dsh", home: "homes/ds" }],
    maxNudges: 1,
  }));
  // In a workspace (what the control plane last said): its agents reach out of the station.
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out);
  await a.next("ready", (m) => m.ready === true);
  const door = await a.next("the agents' door", (m) => m.serving === "mcp");

  // No bearer, or one no session has: refused.
  assert.deepEqual(await mcp(door.port, { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }), { status: 401, json: { error: "unknown session token" } });
  assert.equal((await mcp(door.port, { jsonrpc: "2.0", id: 1, method: "tools/list" }, "nobody's")).status, 401);

  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  const t0 = session(store, data, "chat:c-from", "claude", "t0", "1790000000.000001");
  const t1 = session(store, data, "chat:c-to", "claude", "t1", "1790000000.000002");
  session(store, data, "chat:c-agy", "agy", "t2", "1790000000.000003");
  session(store, data, "chat:c-away", "claude", "t3", "1790000000.000004", "w-left");
  const t4 = session(store, data, "chat:c-dsh", "dsh", "t4", "1790000000.000005");
  const t5 = session(store, data, "chat:c-tui", "claude", "t5", "1790000000.000006", undefined, true);

  // A session's own token: the endpoint's methods, its tools as Claude Code takes them (the turn's two loaded).
  const init = await mcp(door.port, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } }, "t0");
  assert.equal(init.status, 200);
  assert.equal(init.json.result.serverInfo.name, "still.fail");
  assert.equal((await mcp(door.port, { jsonrpc: "2.0", method: "notifications/initialized" }, "t0")).status, 202);
  assert.deepEqual((await mcp(door.port, { jsonrpc: "2.0", id: 2, method: "ping" }, "t0")).json.result, {});
  const listed = (await mcp(door.port, { jsonrpc: "2.0", id: 3, method: "tools/list" }, "t0")).json.result.tools as any[];
  const names = listed.map((t) => t.name);
  for (const core of ["chat_post", "chat_state", "chat_leave", "chat_history", "chat_list", "chat_read", "chat_archive", "chat_create", "session_send", "session_history", "skill_read", "workspace_limit", "peer_forward", "relays"]) {
    assert.ok(names.includes(core), `${core} declared: ${names.join(",")}`);
  }
  assert.deepEqual(listed.find((t) => t.name === "chat_post")._meta, { "anthropic/alwaysLoad": true });
  assert.equal(listed.find((t) => t.name === "chat_list")._meta, undefined);
  // A string where the schema says a number or a boolean is read as one (typed); an unknown tool is refused.
  assert.equal((await mcp(door.port, { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "no_such", arguments: {} } }, "t0")).json.error.code, -32602);
  // A session of a workspace the station is not in: its outward tools refused, saying why.
  const refused = (await mcp(door.port, { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "chat_post", arguments: { text: "x" } } }, "t3")).json.result;
  assert.equal(refused.isError, true);
  assert.match(refused.content[0].text, /not in a still\.fail workspace/);

  // Antigravity: what fits its budget declared, the rest through station_tool, which says each and runs it.
  const agy = (await mcp(door.port, { jsonrpc: "2.0", id: 6, method: "tools/list" }, "t2")).json.result.tools as any[];
  const indirect = agy.find((t) => t.name === "station_tool");
  assert.ok(indirect !== undefined, `station_tool declared to agy: ${agy.map((t) => t.name).join(",")}`);
  assert.ok(agy.some((t) => t.name === "chat_post") && agy.some((t) => t.name === "chat_state"), "every turn's tools declared");
  const folded: string[] = indirect.inputSchema.properties.name.enum;
  assert.ok(folded.length > 0 && folded.every((n) => !agy.some((t) => t.name === n)), "what is folded is not declared");
  assert.ok(JSON.stringify(agy).length < 30_000);
  const described = (await mcp(door.port, { jsonrpc: "2.0", id: 7, method: "tools/call", params: { name: "station_tool", arguments: { name: folded.includes("chat_list") ? "chat_list" : folded[0] } } }, "t2")).json.result;
  assert.equal(JSON.parse(described.content[0].text).name, folded.includes("chat_list") ? "chat_list" : folded[0]);
  if (folded.includes("chat_list")) {
    const ran = (await mcp(door.port, { jsonrpc: "2.0", id: 8, method: "tools/call", params: { name: "station_tool", arguments: { name: "chat_list", arguments: {} } } }, "t2")).json.result;
    assert.notEqual(ran.isError, true, JSON.stringify(ran));
  }

  // One session sends another a message: the other's turn runs its claude under the runner, which posts all_done.
  const sent = (await mcp(door.port, { jsonrpc: "2.0", id: 9, method: "tools/call", params: { name: "session_send", arguments: { to: "chat:c-to", text: "please answer" } } }, "t0")).json.result;
  assert.notEqual(sent.isError, true, `${JSON.stringify(sent)}\n${a.err()}`);
  const ended = await until("the turn's end", () => store.lastTurn("chat:c-to")?.endedAt != null && store.lastTurn("chat:c-to"), () => a.err());
  const turns = store.listTurns("chat:c-to");
  assert.equal(turns.length, 1, `not nudged: ${JSON.stringify(turns.slice(0, 3).map((t) => t.summary))}\n${a.err()}`);
  assert.deepEqual([turns[0]!.summary.outcome, turns[0]!.summary.ending, turns[0]!.summary.need], ["completed", "all_done", "answered what it was sent"]);
  void ended;
  const posted = JSON.parse(readFileSync(join(out, "post-1.json"), "utf8"));
  assert.notEqual(posted.result.isError, true, JSON.stringify(posted));
  const stated = JSON.parse(readFileSync(join(out, "state-1.json"), "utf8"));
  assert.notEqual(stated.result.isError, true, JSON.stringify(stated));
  const agentSaid = store.messagesBefore(t1.id, null, 20).filter((m) => m.authorKind === "agent");
  assert.deepEqual(agentSaid.map((m) => [m.author, m.text]), [["chat:c-to", "posted by the fake"]]);
  // Another chat of this station read (chat_read): its messages with their words (a letter is not one of them).
  const read = (await mcp(door.port, { jsonrpc: "2.0", id: 12, method: "tools/call", params: { name: "chat_read", arguments: { chat: "chat:c-to" } } }, "t0")).json.result;
  assert.notEqual(read.isError, true, JSON.stringify(read));
  const readText = read.content[0].text as string;
  assert.match(readText, /posted by the fake/, readText);
  const itsList = JSON.parse(readFileSync(join(out, "list-1.json"), "utf8")).result.tools.map((t: any) => t.name);
  assert.ok(itsList.includes("chat_post"), "the runtime asked the door's tools with its own token");
  assert.ok(!store.getSession("chat:c-to")!.running);

  // DeepSeek Harness through its bridge's protocol, with no Node: opened (`open` naming its session), prompted, its
  // turn's end read by the program; it posts through the door with its own token.
  const toDsh = (await mcp(door.port, { jsonrpc: "2.0", id: 10, method: "tools/call", params: { name: "session_send", arguments: { to: "chat:c-dsh", text: "dsh, answer" } } }, "t0")).json.result;
  assert.notEqual(toDsh.isError, true, JSON.stringify(toDsh));
  // (its state said by chat_state in the turn, its outcome as the turn ends: the end waited for, as claude's above)
  await until("dsh's turn ended all_done", () => store.listTurns("chat:c-dsh").some((t) => t.summary.ending === "all_done" && t.summary.endedAt != null), () => `${JSON.stringify(store.listTurns("chat:c-dsh").map((t) => t.summary))}\n${a.err()}`);
  const dshTurns = store.listTurns("chat:c-dsh");
  assert.deepEqual([dshTurns.length, dshTurns[0]!.summary.outcome, dshTurns[0]!.summary.need], [1, "completed", "dsh answered"]);
  assert.deepEqual(store.messagesBefore(t4.id, null, 20).filter((m) => m.authorKind === "agent").map((m) => m.text), ["posted by dsh"]);

  // Claude Code as its TUI (the session's run mode): its bridge this program (claude_tui.mbt) under the runner's PTY,
  // no -p; the message pasted into the terminal as the station's, acknowledged by its hook, answered and ended.
  const toTui = (await mcp(door.port, { jsonrpc: "2.0", id: 11, method: "tools/call", params: { name: "session_send", arguments: { to: "chat:c-tui", text: "tui, answer" } } }, "t0")).json.result;
  assert.notEqual(toTui.isError, true, JSON.stringify(toTui));
  await until("the TUI's turn ended all_done", () => store.listTurns("chat:c-tui").some((t) => t.summary.ending === "all_done" && t.summary.endedAt != null), () => `${JSON.stringify(store.listTurns("chat:c-tui").map((t) => t.summary))}\n${a.err()}`);
  const tuiTurns = store.listTurns("chat:c-tui");
  assert.deepEqual([tuiTurns.length, tuiTurns[0]!.summary.outcome, tuiTurns[0]!.summary.need], [1, "completed", "the TUI answered"]);
  assert.deepEqual(store.messagesBefore(t5.id, null, 20).filter((m) => m.authorKind === "agent").map((m) => m.text), ["posted by the TUI"]);
  const tuiArgv = readFileSync(join(out, "tui-argv"), "utf8").split("\n");
  assert.ok(!tuiArgv.includes("-p") && !tuiArgv.includes("--output-format"), tuiArgv.join(" "));
  const tuiSettings = JSON.parse(tuiArgv[tuiArgv.indexOf("--settings") + 1]!);
  assert.equal(tuiSettings.skipDangerousModePermissionPrompt, true);
  for (const e of ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "PreCompact", "PostCompact"]) {
    assert.deepEqual(tuiSettings.hooks[e].at(-1).hooks[0].args.slice(1), ["hook"], e);
  }
  assert.equal(JSON.parse(tuiArgv[tuiArgv.indexOf("--mcp-config") + 1]!).mcpServers.stillfail.type, "stdio");
  assert.match(readFileSync(join(out, "tui-prompt-1"), "utf8"), /^<station_message>\n[\s\S]*tui, answer[\s\S]*\n<\/station_message>$/);
  assert.ok(Array.isArray(JSON.parse(readFileSync(join(out, "tui-tools.json"), "utf8").split("\n")[0]!).result.tools), "its tools listed through the bridge");

  // Files a session posts (chat_post files): a film keeps its size as shown (its turn applied), its length and frames,
  // read of its head (image-size.ts `shownFactsSoon`); a picture its size and the ThumbHash `keep` made of it.
  const t0Workspace = join(data, "sessions", "chat", "c-from", "workspace");
  writeFileSync(join(t0Workspace, "recording.mp4"), film(1140, 2616, { at: "end", turn: 90, ms: 61_000, frames: 1830 }));
  writeFileSync(join(t0Workspace, "photo.jpg"), jpeg(4032, 3024, exif(6, true)));
  writeFileSync(join(t0Workspace, "dot.png"), png(40, 20));
  const withFiles = (await mcp(door.port, { jsonrpc: "2.0", id: 12, method: "tools/call", params: { name: "chat_post", arguments: { to: "CHAT/1790000000.000001", text: "with files", files: ["recording.mp4", "photo.jpg", "dot.png"].map((f) => join(t0Workspace, f)) } } }, "t0")).json.result;
  assert.notEqual(withFiles.isError, true, `${JSON.stringify(withFiles)}\n${a.err()}`);
  const withFilesRow = store.messagesBefore(t0.id, null, 20).find((m) => m.text === "with files")!;
  const facts = (name: string) => {
    const f = withFilesRow.attachments.find((x) => x.name === name) as any;
    return { width: f.width, height: f.height, duration: f.duration, frames: f.frames };
  };
  assert.deepEqual(facts("recording.mp4"), { width: 2616, height: 1140, duration: 61_000, frames: 1830 });
  assert.deepEqual(facts("photo.jpg"), { width: 3024, height: 4032, duration: undefined, frames: undefined });
  const dot = withFilesRow.attachments.find((x) => x.name === "dot.png") as any;
  assert.deepEqual([dot.width, dot.height, typeof dot.thumbhash, (dot.thumbhash ?? "").length > 0], [40, 20, "string", true]);

  // A chat this session leads (chat_create for: me): its agent's turn ends all_done, and the one that opened it is told
  // so, a turn of its own (opened.ts `settled`, through the hub's `settled`).
  assert.equal(store.listTurns("chat:c-from").length, 0, "the opener has had no turn of its own yet");
  const opened = (await mcp(door.port, { jsonrpc: "2.0", id: 13, method: "tools/call", params: { name: "chat_create", arguments: { for: "me", key: "lead-1", text: "do the led work", runtime: "claude" } } }, "t0")).json.result;
  assert.notEqual(opened.isError, true, `${JSON.stringify(opened)}\n${a.err()}`);
  await until("the opener woken as the chat it leads ended its turn", () => store.listTurns("chat:c-from").some((t) => t.summary.endedAt != null), () => `${JSON.stringify(store.listTurns("chat:c-from").map((t) => t.summary))}\n${a.err()}`);
  // The status socket says the agents.
  // A handover: the next process takes the sessions up and serves the door; the one before ends.
  const b = await launch(data, app, bin, out);
  await b.next("ready", (m) => m.ready === true);
  await b.next("taking", (m) => m.taking === true);
  a.tell({ op: "handover" });
  const carry = await a.next("carry", (m) => m.carry !== undefined);
  assert.equal(await a.ended, 0);
  b.tell({ op: "carried", carried: carry.carry });
  const bDoor = await b.next("its door", (m) => m.serving === "mcp");
  assert.equal(existsSync(join(data, "run", "handover.json")), false, "the handover taken up");
  assert.deepEqual((await mcp(bDoor.port, { jsonrpc: "2.0", id: 1, method: "ping" }, "t1")).json.result, {});
  // The taken-up session's next turn runs under the new process.
  const sent2 = (await mcp(bDoor.port, { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "session_send", arguments: { to: "chat:c-to", text: "once more" } } }, "t0")).json.result;
  assert.notEqual(sent2.isError, true, JSON.stringify(sent2));
  // (this test's launcher gives the next process another port: the runtime taken up was told the old one, so its turn
  // finds no tools, and it is started again told the new one, as hub.ts takes it up; a launcher keeps the port)
  await until("a second turn ended all_done", () => store.listTurns("chat:c-to").filter((t) => t.summary.ending === "all_done" && t.summary.endedAt != null).length >= 2, () => `${JSON.stringify(store.listTurns("chat:c-to").map((t) => t.summary))}\n${b.err()}`);
  const second = store.messagesBefore(t1.id, null, 50).filter((m) => m.authorKind === "agent");
  assert.equal(second.length, 2, "the second turn posted once, through the new process's door");
  // The TUI's session taken up (its bridge's runner, kept across the handover): its next turn ends there too.
  const tuiAgain = (await mcp(bDoor.port, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "session_send", arguments: { to: "chat:c-tui", text: "tui, once more" } } }, "t0")).json.result;
  assert.notEqual(tuiAgain.isError, true, JSON.stringify(tuiAgain));
  await until("the TUI's second turn ended all_done", () => store.listTurns("chat:c-tui").filter((t) => t.summary.ending === "all_done" && t.summary.endedAt != null).length >= 2, () => `${JSON.stringify(store.listTurns("chat:c-tui").map((t) => t.summary))}\n${b.err()}`);
  assert.equal(store.messagesBefore(t5.id, null, 50).filter((m) => m.authorKind === "agent").length, 2, "the TUI's second turn posted once");
  // A drain answers once no turn runs.
  b.tell({ op: "drain" });
  assert.deepEqual(await b.next("drained", (m) => m.drained !== undefined), { drained: "idle" });
  b.tell({ op: "stop" });
  assert.equal(await b.ended, 0);
  store.close();
  // Nothing of it left: no process of the station's, no runner, no sessions' program.
  for (const p of [a.child.pid!, b.child.pid!]) assert.throws(() => process.kill(p, 0), "the station's processes ended");
  const runners = join(data, "run", "runners");
  await until("its runners gone", () => {
    if (!existsSync(runners)) return true;
    for (const f of require_json(runners)) {
      try {
        process.kill(f.runner, 0);
        return false;
      } catch {}
    }
    return true;
  });
});

/// An HTTP request of the agents' door (the admin API under `/admin-api/` with STILLFAIL_LOCAL_ADMIN).
function ask(port: number, path: string, method = "GET", body?: unknown): Promise<{ status: number; json: any }> {
  return new Promise((resolve, reject) => {
    const req = request({ host: "127.0.0.1", port, path, method, headers: { "content-type": "application/json" } }, (res) => {
      let text = "";
      res.on("data", (d) => (text += d));
      res.on("end", () => {
        let json: any = text;
        try { json = JSON.parse(text); } catch {}
        resolve({ status: res.statusCode!, json });
      });
    });
    req.on("error", reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

/// A tool's call through the door as session `token`'s agent: its text and whether it is an error.
async function tool(port: number, token: string, name: string, args: unknown): Promise<{ text: string; error: boolean }> {
  const said = await mcp(port, { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }, token);
  assert.equal(said.status, 200, JSON.stringify(said.json));
  assert.equal(said.json.error, undefined, JSON.stringify(said.json));
  return { text: said.json.result.content[0].text, error: said.json.result.isError === true };
}

test("the conversations' own parts: a title asked of a runtime session of their own, the archive review of an all_done, the mesh's relays listed", { skip }, async () => {
  const data = fresh("e");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }],
    maxNudges: 1,
    // (the archive review of a chat that ended all_done, on a model no profile has: it records that it could not ask)
    automaticDecisions: { completion: { enabled: true, model: "no-profile-has-it" } },
  }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out, undefined, { STILLFAIL_LOCAL_ADMIN: "1" });
  await a.next("ready", (m) => m.ready === true);
  const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    const t0 = session(store, data, "chat:c-from", "claude", "t0", "1790000000.000001");
    const t1 = session(store, data, "chat:c-to", "claude", "t1", "1790000000.000002");

    // A turn that ends all_done sets the archive's review going (review.ts `suggestArchive`, hub.fork): its decision
    // recorded, here that the model it names is no profile's.
    const sent = await tool(door, "t0", "session_send", { to: "chat:c-to", text: "please answer" });
    assert.equal(sent.error, false, `${sent.text}\n${a.err()}`);
    await until("the turn ended all_done", () => store.listTurns("chat:c-to").some((t) => t.summary.ending === "all_done" && t.summary.endedAt != null), () => a.err());
    const checks = () => (store.db.prepare("SELECT session, result FROM decision_checks WHERE session = ?").all("chat:c-to") as { result: string }[]).map((r) => JSON.parse(r.result));
    const reviewed = await until("the archive review recorded its decision", () => checks().length > 0 && checks(), () => a.err());
    assert.deepEqual([reviewed[0].purpose, reviewed[0].accepted, reviewed[0].error], ["archive", false, "配置的模型在现有 Profile 中暂不可用"]);

    // A new title for the chat, asked of its agent's runtime in a session of its own (regenerate-title.ts
    // `driver.open`): the fake Claude Code's answer, "posted", is the title.
    const titled = await ask(door, `/admin-api/threads/${t1.id}/regenerate-title`, "POST", {});
    assert.equal(titled.status, 200, `${JSON.stringify(titled.json)}\n${a.err()}`);
    assert.equal((store.db.prepare("SELECT auto_title FROM threads WHERE id = ?").get(t1.id) as { auto_title: string }).auto_title, "posted");
    // One of a chat with nothing said yet is refused in the words for why (its TitleError's problem).
    const empty = await ask(door, `/admin-api/threads/${t0.id}/regenerate-title`, "POST", {});
    assert.equal(empty.status, 400, JSON.stringify(empty.json));
    assert.doesNotMatch(JSON.stringify(empty.json), /station\.title|undefined/);

    // The relays: the mesh's listed as agents.ts lists them where the native mesh has no directory (none); enrolling
    // one refused, saying it is not this station's.
    const listed = await tool(door, "t0", "relays", { action: "list" });
    assert.equal(listed.error, false, listed.text);
    assert.deepEqual(JSON.parse(listed.text).mesh, []);
    const enrolled = await tool(door, "t0", "relays", { action: "enroll", name: "r1" });
    assert.equal(enrolled.error, true);
    assert.match(enrolled.text, /not available on this station/);

    // need_human said with no about after a card: what it is about is the card, as the conversations reread it in
    // their own transaction (conversations.mbt `state_write`, the actor's `stateWrite` handing it its `record`).
    const asking = () => (store.db.prepare("SELECT COUNT(*) AS n FROM turns WHERE session_key = 'chat:c-to' AND need = 'pick one' AND ended_at IS NOT NULL").get() as { n: number }).n;
    const aboutOf = (key: string) => store.db.prepare("SELECT about_n FROM turns WHERE session_key = ? ORDER BY started_at DESC, rowid DESC LIMIT 1").get(key) as { about_n: number | null };
    const cardN = () => store.messagesBefore(t1.id, null, 50).filter((m) => m.text === "which one?").at(-1)?.n;
    const asked = await tool(door, "t0", "session_send", { to: "chat:c-to", text: "ASK-CARD please" });
    assert.equal(asked.error, false, asked.text);
    await until("its need_human recorded", () => existsSync(join(out, "ask-2.json")) && asking() === 1, () => a.err());
    assert.notEqual(JSON.parse(readFileSync(join(out, "ask-2.json"), "utf8")).result.isError, true, readFileSync(join(out, "ask-2.json"), "utf8"));
    assert.equal(aboutOf("chat:c-to").about_n, cardN(), "about the card");

    // The same while another connection holds the write lock: the record is busy (StateWriteBusy, thrown back as it
    // was through the sessions' program) and tried again until the lock is let go.
    // (BEGIN IMMEDIATE waits out a write of the station's own in progress, as its connections do: with no busy timeout
    // it failed "database is locked" whenever one was, main d4d8cdd53, 44500681208)
    const other = new DatabaseSync(join(data, "stillfail.db"), { timeout: 5000 });
    try {
      const busy = await tool(door, "t0", "session_send", { to: "chat:c-to", text: "ASK-CARD ASK-BUSY please" });
      assert.equal(busy.error, false, busy.text);
      await until("the fake about to say its state", () => existsSync(join(out, "stating")), () => a.err());
      other.exec("BEGIN IMMEDIATE");
      writeFileSync(join(out, "state-go"), "");
      // (held a while as it is asked: what it says once let go is what is asserted, whenever it asked)
      await new Promise((r) => setTimeout(r, 300));
    } finally {
      try {
        other.exec("ROLLBACK");
      } catch {}
      other.close();
    }
    await until("its need_human recorded after the lock", () => existsSync(join(out, "ask-3.json")) && asking() === 2, () => a.err());
    assert.notEqual(JSON.parse(readFileSync(join(out, "ask-3.json"), "utf8")).result.isError, true, readFileSync(join(out, "ask-3.json"), "utf8"));
    assert.equal(aboutOf("chat:c-to").about_n, cardN(), "about the newer card");
  } finally {
    store.close();
  }
  a.tell({ op: "stop" });
  assert.equal(await a.ended, 0, a.err());
});

test("an archived session put in cold storage off the station's thread, and its workspace back whole once unarchived", { skip }, async () => {
  const data = fresh("c");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], maxNudges: 1 }));
  const a = await launch(data, app, bin, out, undefined, { STILLFAIL_LOCAL_ADMIN: "1" });
  await a.next("ready", (m) => m.ready === true);
  const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    session(store, data, "chat:c-cold", "claude", "t0", "1790000000.000001");
    const room = join(data, "sessions", "chat", "c-cold");
    const workspace = join(room, "workspace");
    writeFileSync(join(workspace, "keep.txt"), "kept\n");
    mkdirSync(join(workspace, "node_modules", "x"), { recursive: true });
    writeFileSync(join(workspace, "node_modules", "x", "index.js"), "module.exports = 1;\n");
    // Its transcript, packed in place, and the Rust station's copy of it in the store's archive (`store.archiveDir`),
    // let go once the transcript is packed (cold.mbt `pack_history`).
    const runtimeId = "0b1c2d3e-4f50-4a61-8b72-93a4b5c6d7e8";
    store.setRuntimeSessionId("chat:c-cold", runtimeId);
    // (where Claude keeps it: its project named after the workspace as the system resolves it)
    const project = join(data, "homes", "cc", "projects", realpathSync(workspace).replace(/[^a-zA-Z0-9]/g, "-"));
    const transcript = join(project, `${runtimeId}.jsonl`);
    mkdirSync(project, { recursive: true });
    writeFileSync(transcript, `${JSON.stringify({ type: "user", sessionId: runtimeId, message: { role: "user", content: "hi" } })}\n`);
    const legacy = join(data, "archive", "transcripts", "chat:c-cold.jsonl.zst");
    mkdirSync(join(data, "archive", "transcripts"), { recursive: true });
    writeFileSync(legacy, "the Rust station's copy");

    // Archived: its room marked cold, what can be made again removed, the workspace packed (cold.ts `pack`, by the
    // packing and measuring programs of their own: `--builder packed`, `--builder footprint`).
    const archived = await ask(door, `/admin-api/sessions/${encodeURIComponent("chat:c-cold")}/archive`, "POST", {});
    assert.equal(archived.status, 200, `${JSON.stringify(archived.json)}\n${a.err()}`);
    await until(
      "the room put in cold storage",
      () => {
        if (!existsSync(join(room, "cold")) || !existsSync(join(room, "workspace.tar.zst")) || existsSync(join(room, "workspace.retiring"))) return false;
        try {
          return readdirSync(workspace).length === 0;
        } catch {
          return false;
        }
      },
      () => a.err(),
    );
    assert.equal(existsSync(join(workspace, "keep.txt")), false, "the workspace is in its archive");
    assert.equal(existsSync(join(workspace, "node_modules")), false);
    await until("its transcript packed and the old copy let go", () => existsSync(`${transcript}.zst`) && !existsSync(transcript) && !existsSync(legacy), () => a.err());
    assert.doesNotMatch(a.err(), /no such store method/);

    // Unarchived: the workspace written back from its archive (cold.ts `restore`), what was rebuildable not in it.
    const back = await ask(door, `/admin-api/sessions/${encodeURIComponent("chat:c-cold")}/archive`, "DELETE");
    assert.equal(back.status, 200, `${JSON.stringify(back.json)}\n${a.err()}`);
    await until(
      "the workspace restored",
      () => existsSync(join(workspace, "keep.txt")) && !existsSync(join(room, "workspace.tar.zst")) && !existsSync(join(room, "cold")),
      () => a.err(),
    );
    assert.equal(readFileSync(join(workspace, "keep.txt"), "utf8"), "kept\n");
    assert.equal(existsSync(join(workspace, "node_modules")), false);
    assert.doesNotMatch(a.err(), /an archived session's files not put away/);
  } finally {
    store.close();
  }
  a.tell({ op: "stop" });
  assert.equal(await a.ended, 0, a.err());
});

test("an archived session's transcripts packed in cold storage and the Rust station's copy of them let go (store.archiveDir answered)", { skip }, async () => {
  const data = fresh("c");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], maxNudges: 1 }));
  const a = await launch(data, app, bin, out, undefined, { STILLFAIL_LOCAL_ADMIN: "1" });
  await a.next("ready", (m) => m.ready === true);
  const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    session(store, data, "chat:c-old", "claude", "t0", "1790000000.000002");
    const workspace = join(data, "sessions", "chat", "c-old", "workspace");
    // its runtime session's transcript where the station keeps Claude's (transcript.ts `placedIn`), and the copy the
    // Rust station's archiving left (`archive/transcripts/<key>.jsonl.zst`)
    store.ranIn("chat:c-old", "rt-1", "cc");
    const transcript = join(data, "transcripts", "claude", workspace.replace(/[^A-Za-z0-9]/g, "-"), "rt-1.jsonl");
    mkdirSync(dirname(transcript), { recursive: true });
    writeFileSync(transcript, '{"type":"user"}\n'.repeat(50));
    const legacy = join(data, "archive", "transcripts", "chat:c-old.jsonl.zst");
    mkdirSync(dirname(legacy), { recursive: true });
    writeFileSync(legacy, "legacy copy");

    const archived = await ask(door, `/admin-api/sessions/${encodeURIComponent("chat:c-old")}/archive`, "POST", {});
    assert.equal(archived.status, 200, `${JSON.stringify(archived.json)}\n${a.err()}`);
    await until("the transcript packed and the old copy let go", () => !existsSync(legacy) && !existsSync(transcript) && existsSync(`${transcript}.zst`), () => a.err());
    assert.doesNotMatch(a.err(), /no such store method/);
  } finally {
    store.close();
  }
  a.tell({ op: "stop" });
  assert.equal(await a.ended, 0, a.err());
});

test("hub.wsOf as the parts ask it (hub.ts `wsOf(row | key | null)`): a session's row by its own workspace, a key by its row's, else the home one", { skip }, async () => {
  const data = fresh("w");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [], maxNudges: 1 }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out, undefined, { STILLFAIL_PARTS_DOOR: "1" });
  await a.next("ready", (m) => m.ready === true);
  const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  let row: any;
  try {
    session(store, data, "chat:c-w2", "claude", "t0", "1790000000.000003", "w2");
    row = store.getSession("chat:c-w2");
  } finally {
    store.close();
  }
  const wsOf = async (arg: unknown) => {
    const r = await ask(door, "/parts/hub/hub.wsOf", "POST", [arg]);
    assert.equal(r.status, 200, `${JSON.stringify(r.json)}\n${a.err()}`);
    return r.json;
  };
  // (handover.ts `check` gives the row it read from its page: another workspace's, not the home one)
  assert.equal(await wsOf(row), "w2");
  assert.equal(await wsOf("chat:c-w2"), "w2");
  assert.equal(await wsOf({ ...row, ws: null }), "w1");
  assert.equal(await wsOf(null), "w1");
  a.tell({ op: "stop" });
  assert.equal(await a.ended, 0, a.err());
});

test("the relays tool with no mesh up: the mesh's relays listed as none, enrolling and revoking one refused", { skip }, async () => {
  const data = fresh("r");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], maxNudges: 1 }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  // The mesh's address held by the test: its endpoint never binds, so the relays tool's asks reach the control plane's
  // own answers (live_p5_1_plane.mbt), never the mesh directory's (live_p5_1_scopes.mbt), whenever they are asked.
  const held = createSocket("udp4");
  await new Promise<void>((resolve) => held.bind(0, "127.0.0.1", () => resolve()));
  try {
    const a = await launch(data, app, bin, out, undefined, { STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_BIND_ADDR: `127.0.0.1:${held.address().port}` });
    await a.next("ready", (m) => m.ready === true);
    const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
    await until("the mesh failed to bind", () => /mesh stopped; trying again/.test(a.err()), () => a.err());
    const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
    try {
      session(store, data, "chat:c-relays", "claude", "t0", "1790000000.000001");
      const listed = await tool(door, "t0", "relays", { action: "list" });
      assert.equal(listed.error, false, `${listed.text}\n${a.err()}`);
      assert.deepEqual(JSON.parse(listed.text).mesh, []);
      const enrolled = await tool(door, "t0", "relays", { action: "enroll", name: "r1" });
      assert.equal(enrolled.error, true);
      assert.match(enrolled.text, /native mesh relay enrollment is not available on this station/);
      const revoked = await tool(door, "t0", "relays", { action: "revoke", node: "a".repeat(64) });
      assert.equal(revoked.error, true);
      assert.match(revoked.text, /native mesh relay control is not available on this station/);
      assert.doesNotMatch(a.err(), /no such control plane call/);
    } finally {
      store.close();
    }
    a.tell({ op: "stop" });
    assert.equal(await a.ended, 0, a.err());
  } finally {
    held.close();
  }
});

/// The program's id of a data directory (`stillfail-reader id`): its key made there.
function stationId(data: string): string {
  const r = spawnSync(binary!, ["id", "--data", data], { env: { PATH: "/usr/bin:/bin", HOME: data, TMPDIR: tmpdir() }, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
}

/// A UDP port free on 127.0.0.1 (a station's mesh bound there).
const freeUdpPort = () => new Promise<number>((resolve) => {
  const s = createSocket("udp4");
  s.bind(0, "127.0.0.1", () => {
    const port = s.address().port;
    s.close(() => resolve(port));
  });
});

test("sessions across stations over the mesh: a message to another station's chat, one to a chat moved on to a third, and a chat led there telling its opener here", { skip }, async () => {
  const app = fresh("a");
  const bin = fresh("p");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  const names = ["alpha", "beta", "gamma"] as const;
  const datas = names.map((n) => fresh(n.slice(0, 1)));
  const outs = names.map((n) => fresh(`o${n.slice(0, 1)}`));
  const ids = datas.map(stationId);
  const ports = await Promise.all(names.map(() => freeUdpPort()));
  const origin = "http://127.0.0.1:9";
  const peers = names.map((name, i) => ({ id: ids[i], name, ips: [`127.0.0.1:${ports[i]}`] }));
  for (const data of datas) {
    mkdirSync(join(data, "homes", "cc"), { recursive: true });
    writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], maxNudges: 1 }));
  }
  datas.forEach((data, i) => {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin, station: ids[i], workspace: "w1", workspace_name: "W", name: names[i], relay_url: "", relay_urls: [], grant_keys: null, peers, revocations: [] }));
  });
  const launched = await Promise.all(datas.map((data, i) => launch(data, app, bin, outs[i], undefined, { STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_BIND_ADDR: `127.0.0.1:${ports[i]}` })));
  for (const l of launched) await l.next("ready", (m) => m.ready === true);
  const door = (await launched[0]!.next("alpha's door", (m) => m.serving === "mcp")).port as number;
  const stores = datas.map((data) => Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never));
  const [alpha, beta, gamma] = [stores[0]!, stores[1]!, stores[2]!];
  const errs = () => launched.map((l, i) => `── ${names[i]}\n${l.err()}`).join("\n");
  const ended = (store: Store, key: string) => store.listTurns(key).some((t) => t.summary.ending === "all_done" && t.summary.endedAt != null);
  try {
    session(alpha, datas[0]!, "chat:c-lead", "claude", "ta", "1790000000.000001");
    session(beta, datas[1]!, "chat:c-there", "claude", "tb", "1790000000.000002");
    session(beta, datas[1]!, "chat:c-moved", "claude", "tm", "1790000000.000003");
    // (gamma handed chat:c-moved on to beta: replica/handover.ts's record of where it went)
    gamma.db.prepare("INSERT INTO handed_over(session, station, ws, thread, there, at) VALUES (?, ?, NULL, NULL, NULL, ?)").run("chat:c-moved", ids[1]!, Date.now());

    // A message to a chat on beta, by its link: beta's session is told it and its turn runs there (agents.ts `local`,
    // messages.ts `fromPeer`). (Asked again only while beta is not reached yet over the mesh.)
    const toBeta = `${origin}/o/w1/${ids[1]}/chat:c-there`;
    let last = "";
    const sent = await until("alpha's message taken by beta", async () => {
      const r = await tool(door, "ta", "session_send", { to: toBeta, text: "from alpha" });
      last = r.text;
      return r.error && /not reached|no route|mesh is not up/i.test(r.text) ? null : r;
    }, () => `${last}\n${errs()}`);
    assert.equal(sent.error, false, `${sent.text}\n${errs()}`);
    await until("beta's chat answered the message", () => ended(beta, "chat:c-there"), errs);

    // A message to a chat gamma handed on to beta: gamma carries it there (messages.ts `fromPeer`, hub.ts `peers()`).
    const moved = await tool(door, "ta", "session_send", { to: `${origin}/o/w1/${ids[2]}/chat:c-moved`, text: "to the moved chat" });
    assert.equal(moved.error, false, `${moved.text}\n${errs()}`);
    await until("the moved chat answered on beta", () => ended(beta, "chat:c-moved"), errs);

    // A chat alpha's session opens on beta and leads: its agent ends its turn all_done there, and the opener here is
    // told so (opened.ts `noticeForPeer`), a turn of its own.
    assert.equal(alpha.listTurns("chat:c-lead").length, 0, "the opener has had no turn yet");
    const opened = await tool(door, "ta", "chat_create", { for: "me", station: ids[1], key: "led-1", text: "do the led work", runtime: "claude" });
    assert.equal(opened.error, false, `${opened.text}\n${errs()}`);
    await until("the opener on alpha woken by the chat it leads on beta", () => alpha.listTurns("chat:c-lead").some((t) => t.summary.endedAt != null), errs);
  } finally {
    for (const s of stores) s.close();
  }
  for (const l of launched) l.tell({ op: "stop" });
  for (const l of launched) assert.equal(await l.ended, 0, l.err());
});

test("handover of an in-flight turn: the new station takes up sessions before opening /mcp so chat_state is recorded and the runner survives", { skip }, async () => {
  const data = fresh("h");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }],
    maxNudges: 1,
  }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out);
  await a.next("ready", (m) => m.ready === true);
  const door = await a.next("the agents' door", (m) => m.serving === "mcp");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    session(store, data, "chat:c-from", "claude", "t0", "1790000000.000001");
    const tMid = session(store, data, "chat:c-mid", "claude", "t1", "1790000000.000002");

    // Start a turn that stays in-flight across the station handover.
    const sent = await tool(door.port, "t0", "session_send", { to: "chat:c-mid", text: "HOLD-HANDOVER please" });
    assert.equal(sent.error, false, `${sent.text}\n${a.err()}`);
    await until("in-flight turn running", () => existsSync(join(out, "mid-running")) && store.getSession("chat:c-mid")?.running === true, () => a.err());
    const runnerInfos = require_json(join(data, "run", "runners"));
    assert.ok(runnerInfos.length >= 1, "runner info present for in-flight turn");
    const runnerPid = runnerInfos[0]!.runner;

    // Hand over from `a` first: its end frees the door's port (the runner holds none of its fds, all close-on-exec).
    a.tell({ op: "handover" });
    const carry = await a.next("carry", (m) => m.carry !== undefined);
    assert.equal(await a.ended, 0, a.err());
    // The in-flight runner must survive `a`'s handover and exit (never killed by hub_shutdown).
    assert.doesNotThrow(() => process.kill(runnerPid, 0), "in-flight runner survived handover");

    // Launch the next station on the same door's port, then release the in-flight agent: its POST to /mcp sits in
    // `b`'s kernel accept queue and is served only after `Hub::take_up()` opens the door.
    const b = await launch(data, app, bin, out, [await listener(door.port), await listener()]);
    writeFileSync(join(out, "mid-go"), "");
    await b.next("ready", (m) => m.ready === true);
    b.tell({ op: "carried", carried: carry.carry });
    await b.next("b's door", (m) => m.serving === "mcp");

    await until("in-flight turn finished across handover", () => store.lastTurn("chat:c-mid")?.endedAt != null, () => b.err());
    const turns = store.listTurns("chat:c-mid");
    assert.equal(turns.length, 1, `not nudged: ${JSON.stringify(turns.map((t) => t.summary))}\n${b.err()}`);
    assert.deepEqual(
      [turns[0]!.summary.outcome, turns[0]!.summary.ending, turns[0]!.summary.need],
      ["completed", "all_done", "finished across handover"],
      b.err(),
    );
    const posted = JSON.parse(readFileSync(join(out, "mid-post-1.json"), "utf8"));
    assert.notEqual(posted.result.isError, true, JSON.stringify(posted));
    const stated = JSON.parse(readFileSync(join(out, "mid-state-1.json"), "utf8"));
    assert.notEqual(stated.result.isError, true, JSON.stringify(stated));
    assert.deepEqual(
      store.messagesBefore(tMid.id, null, 20).filter((m) => m.authorKind === "agent").map((m) => m.text),
      ["posted across handover"],
    );
    // Verify in `b`'s trace that drivers.adopt (inside Hub::take_up) ran before agents.openDoor.
    const bTrace = b.err();
    const adoptAt = bTrace.indexOf("p52 hub ask drivers.adopt");
    const openDoorAt = bTrace.indexOf("p52 hub ask agents.openDoor");
    assert.ok(adoptAt >= 0 && openDoorAt > adoptAt, `expected drivers.adopt before agents.openDoor:\n${bTrace}`);

    b.tell({ op: "stop" });
    assert.equal(await b.ended, 0, b.err());
  } finally {
    store.close();
  }
});

test("a cold session woken by its job's stillfail-job notify: the hub makes its actor before telling it (hub.ts `notify`)", { skip }, async () => {
  const data = fresh("n");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], maxNudges: 1 }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out);
  await a.next("ready", (m) => m.ready === true);
  const door = (await a.next("the agents' door", (m) => m.serving === "mcp")).port as number;
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    // A session no message ever reached since this process started: no actor of it in the sessions' program.
    session(store, data, "chat:c-cold", "claude", "t-cold", "1790000000.000007");
    assert.equal(store.listTurns("chat:c-cold").length, 0);
    // Its job says a word on the way (`stillfail-job notify`, the agents' door's /jobs/notify, the hub's `notify`):
    // the session is woken by it, a turn whose prompt carries the word. (`stillfail-job` posts with curl, which
    // the station's PATH here does not name: it names only the fakes' directory.)
    const started = await tool(door, "t-cold", "job_start", { name: "waker", command: "PATH=/usr/bin:/bin:$PATH stillfail-job notify COLD-WAKE-WORD" });
    assert.equal(started.error, false, `${started.text}\n${a.err()}`);
    const job = JSON.parse(started.text);
    await until("the job's word kept", () => store.jobNotices(job.id, 5).some((n) => n.text === "COLD-WAKE-WORD"), () => a.err());
    await until("the cold session's turn ended", () => store.listTurns("chat:c-cold").some((t) => t.summary.endedAt != null), () => `${JSON.stringify(store.listTurns("chat:c-cold").map((t) => t.summary))}\n${a.err()}`);
    const prompts = readFileSync(join(out, "prompts"), "utf8");
    assert.match(prompts, /COLD-WAKE-WORD/, prompts);
  } finally {
    store.close();
  }
  a.tell({ op: "stop" });
  assert.equal(await a.ended, 0, a.err());
});

test("MoonBit station toolsUnheard: initialize/ping do not count as heard, and toolsUnheard restarts the process directly and across handover", { skip }, async () => {
  const data = fresh("u");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }],
    maxNudges: 2,
  }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out);
  await a.next("ready", (m) => m.ready === true);
  const door = await a.next("the agents' door", (m) => m.serving === "mcp");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    session(store, data, "chat:c-from", "claude", "t0", "1790000000.000001");
    session(store, data, "chat:c-unheard", "claude", "t1", "1790000000.000002");
    session(store, data, "chat:c-unheard-ho", "claude", "t2", "1790000000.000003");

    // 1) Direct toolsUnheard: first process only calls initialize/notifications/ping and ends without posting ->
    //    MoonBit station kills it and restarts a new process with TOOLS_LOST, which then calls tools/list and posts all_done.
    const sent1 = await tool(door.port, "t0", "session_send", { to: "chat:c-unheard", text: "UNHEARD-ONCE please" });
    assert.equal(sent1.error, false, `${sent1.text}\n${a.err()}`);
    await until("unheard session healed after restart", () => store.listTurns("chat:c-unheard").some((t) => t.summary.ending === "all_done"), () => a.err());
    const prompts1 = readFileSync(join(out, "prompts"), "utf8");
    assert.match(prompts1, /Your last turn could not reach the station's tools/, prompts1);

    // 2) Across handover: process never reached tools before handover -> snapshot carries toolsUnheard: true ->
    //    adopting MoonBit station still catches toolsUnheard and restarts with TOOLS_LOST.
    const sent2 = await tool(door.port, "t0", "session_send", { to: "chat:c-unheard-ho", text: "HOLD-UNHEARD please" });
    assert.equal(sent2.error, false, `${sent2.text}\n${a.err()}`);
    await until("hold-unheard running", () => existsSync(join(out, "unheard-running")) && store.getSession("chat:c-unheard-ho")?.running === true, () => a.err());

    a.tell({ op: "handover" });
    const carry = await a.next("carry", (m) => m.carry !== undefined);
    assert.equal(await a.ended, 0, a.err());
    const handoverFile = JSON.parse(readFileSync(join(data, "run", "handover.json"), "utf8"));
    const hoSnap = (handoverFile.sessions ?? []).find((s: any) => s.key === "chat:c-unheard-ho");
    assert.equal(hoSnap?.toolsUnheard, true, JSON.stringify(handoverFile));

    const b = await launch(data, app, bin, out, [await listener(door.port), await listener()]);
    await b.next("ready", (m) => m.ready === true);
    b.tell({ op: "carried", carried: carry.carry });
    await b.next("b's door", (m) => m.serving === "mcp");
    writeFileSync(join(out, "unheard-go"), "");

    await until("handed-over unheard session healed after restart", () => store.listTurns("chat:c-unheard-ho").some((t) => t.summary.ending === "all_done"), () => b.err());
    const turnsHo = store.listTurns("chat:c-unheard-ho");
    assert.equal(turnsHo.length, 2, `${JSON.stringify(turnsHo.map((t) => t.summary))}\n${b.err()}`);
    assert.equal(turnsHo[1]!.summary.ending, "all_done", b.err());

    b.tell({ op: "stop" });
    assert.equal(await b.ended, 0, b.err());
  } finally {
    store.close();
  }
});

test("MoonBit station nudge-level toolsUnheard: mid-session MCP loss heals after nudge by restarting with TOOLS_LOST", { skip }, async () => {
  const data = fresh("nu");
  const app = fresh("a");
  const bin = fresh("p");
  const out = fresh("o");
  writeFileSync(join(app, "BUILD"), "9400\n");
  fakes(bin);
  mkdirSync(join(data, "homes", "cc"), { recursive: true });
  writeFileSync(join(data, "homes", "cc", ".credentials.json"), "{}");
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }],
    maxNudges: 2,
  }));
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.example", workspace: "w1", workspace_name: "W", station: "st1" }));
  const a = await launch(data, app, bin, out);
  await a.next("ready", (m) => m.ready === true);
  const door = await a.next("the agents' door", (m) => m.serving === "mcp");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"), { currentTimeMillisUnsafe: () => Date.now() } as never);
  try {
    session(store, data, "chat:c-from", "claude", "t0", "1790000000.000001");
    session(store, data, "chat:c-nudge-unheard", "claude", "t1", "1790000000.000002");

    // Turn 1: process calls tools/list and posts all_done (heard > 0, process stays warm).
    const sent1 = await tool(door.port, "t0", "session_send", { to: "chat:c-nudge-unheard", text: "first normal turn" });
    assert.equal(sent1.error, false, `${sent1.text}\n${a.err()}`);
    await until("turn 1 all_done", () => store.listTurns("chat:c-nudge-unheard").filter((t) => t.summary.ending === "all_done").length >= 1, () => a.err());

    // Turn 2: same process drops MCP (zero /mcp calls on turn 2 and on the following NUDGE) ->
    // MoonBit station catches nudgeUnheard, kills the bad process, and restarts a new process with TOOLS_LOST which finishes all_done.
    const sent2 = await tool(door.port, "t0", "session_send", { to: "chat:c-nudge-unheard", text: "NUDGE-UNHEARD-DROP please" });
    assert.equal(sent2.error, false, `${sent2.text}\n${a.err()}`);
    await until("mid-session MCP loss healed after nudge restart", () => store.listTurns("chat:c-nudge-unheard").filter((t) => t.summary.ending === "all_done").length >= 2, () => `${JSON.stringify(store.listTurns("chat:c-nudge-unheard").map((t) => t.summary))}\n${a.err()}`);
    const prompts = readFileSync(join(out, "prompts"), "utf8");
    assert.match(prompts, /Your last turn could not reach the station's tools/, prompts);

    a.tell({ op: "stop" });
    assert.equal(await a.ended, 0, a.err());
  } finally {
    store.close();
  }
});

/// The runners' info files there.
function require_json(dir: string): { runner: number }[] {
  return readdirSync(dir).filter((f) => f.endsWith(".json")).flatMap((f) => {
    try {
      return [JSON.parse(readFileSync(join(dir, f), "utf8"))];
    } catch {
      return [];
    }
  });
}
