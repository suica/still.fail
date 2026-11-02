// CI-only diagnostic: compare a virtual X server's normal reset behavior with an idle desktop client.
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { setTimeout as sleep } from "node:timers/promises";
import { X11Desktop } from "../src/screens/x11-desktop.ts";

const run = promisify(execFile);
const env = { ...process.env };
const hold = env.KEEP_X_CLIENT === "1";
const desktop = new X11Desktop({ env, changed: () => {} });
const observer = hold ? spawn("xev", ["-event", "keyboard"], { env, stdio: "ignore" }) : null;
let failures = 0, recoveredImmediately = 0, recoveredLater = 0;
try {
  if (observer) {
    let connected = false;
    for (let i = 0; i < 100 && !connected; i++) {
      try { await run("xdotool", ["search", "--name", "Event Tester"], { env }); connected = true; }
      catch { await sleep(50); }
    }
    if (!connected || observer.exitCode !== null) throw new Error("the observer did not connect");
  }
  for (const codec of ["jpeg", "h264"] as const) {
    const count = codec === "jpeg" ? 80 : 30;
    for (let i = 0; i < count; i++) {
      let view: Awaited<ReturnType<typeof desktop.open>> | undefined;
      try {
        view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: [codec], fps: 15 });
        const first = await view.next();
        if (!first || first.config?.codec !== codec) throw new Error("wrong first frame");
        const pending = view.next();
        view.close();
        await pending;
        view = undefined;
      } catch (error) {
        failures++;
        const geometry = async () => {
          try { await run("xdotool", ["getdisplaygeometry"], { env, timeout: 3000 }); return true; }
          catch { return false; }
        };
        const now = await geometry();
        await sleep(100);
        const later = await geometry();
        if (now) recoveredImmediately++;
        if (later) recoveredLater++;
        console.log("FAILURE", JSON.stringify({ codec, iteration: i, now, later, said: String(error).slice(0, 600) }));
      } finally { view?.close(); }
    }
  }
  console.log("RESULT", JSON.stringify({ hold, failures, recoveredImmediately, recoveredLater }));
  if (hold && failures) process.exitCode = 1;
} finally {
  await desktop.close();
  observer?.kill();
}
