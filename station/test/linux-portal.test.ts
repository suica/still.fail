import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { WaylandDesktop } from "../src/screens/linux-portal.ts";
import { graphicalSession } from "../src/screens/linux-session.ts";

test("graphical session metadata identifies the station user's desktop", () => {
  const properties = "User=123\nClass=user\nType=wayland\nActive=yes\nRemote=no\nDisplay=\n";
  assert.deepEqual(graphicalSession("2", 123, properties), {
    id: "2", uid: 123, type: "wayland", active: true, remote: false, display: undefined,
  });
  assert.equal(graphicalSession("2", 999, properties), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Class=user", "Class=greeter")), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Type=wayland", "Type=tty")), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Active=yes", "Active=no"))?.active, false);
});

test("a portal view carries its first picture, input and close across the helper pipe", async () => {
  const dir = await mkdtemp(join(tmpdir(), "sf-portal-test-"));
  const runner = join(dir, "runner");
  await writeFile(runner, '#!/bin/sh\nshift\nexec "$STILLFAIL_TEST_NODE" "$@"\n', { mode: 0o700 });
  const helper = fileURLToPath(new URL("./fixtures/portal-helper.mjs", import.meta.url));
  let changes = 0;
  const desktop = new WaylandDesktop({
    changed: () => { changes++; },
    env: { ...process.env, STILLFAIL_TEST_NODE: process.execPath },
    python: runner,
    helper,
  });
  try {
    await assert.rejects(desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["h264"] }), /JPEG/);
    const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["jpeg"] });
    assert.deepEqual(desktop.size(), { width: 1280, height: 800 });
    const first = await view.next();
    assert.ok(first);
    assert.deepEqual(first.config, { codec: "jpeg", width: 640, height: 400 });
    assert.deepEqual([...first.data], [0xff, 0xd8, 0xff, 0xd9]);
    assert.equal(first.key, true);
    assert.ok(changes > 0);

    await view.input({ t: "pointer", kind: "move", x: 0.25, y: 0.5, buttons: 0 });
    const pointer = await view.next();
    assert.ok(pointer);
    assert.deepEqual(JSON.parse(Buffer.from(pointer.data).toString()), { t: "pointer", kind: "move", x: 0.25, y: 0.5, buttons: 0 });
    assert.ok(pointer.ts > first.ts);

    await view.input({ t: "key", kind: "down", code: "KeyA", key: "a", mods: 0 });
    const key = await view.next();
    assert.ok(key);
    assert.deepEqual(JSON.parse(Buffer.from(key.data).toString()), { t: "key", keycode: 30, kind: "down" });

    const pending = view.next();
    view.close();
    assert.equal(await pending, null);
  } finally {
    await desktop.close();
    await rm(dir, { recursive: true, force: true });
  }
});
