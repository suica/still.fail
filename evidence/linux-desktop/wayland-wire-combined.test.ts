import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { answerScreen, frame, FrameIn, KIND, SCREEN_TYPE } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import { LinuxGstDesktop } from "../src/screens/linux-portal.ts";
import { memoryMesh } from "./memory-mesh.ts";

test("Wayland screen wire carries a frame and controls the real GTK target", { timeout: 70_000 }, async () => {
  const desktop = new LinuxGstDesktop({ env: process.env, changed: () => {} });
  const hub = new ScreenHub();
  hub.add(desktop);
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const station = await bind();
  const device = await bind();
  let conn, stream, served;
  const target = `${process.env.TEST_ROOT}/target.log`;
  async function waitFor(pattern, count = 1) {
    let value = "";
    for (let i = 0; i < 100; i++) {
      value = await readFile(target, "utf8");
      if ((value.match(pattern) ?? []).length >= count) return;
      await sleep(100);
    }
    assert.fail(`missing ${pattern} in target log: ${value}`);
  }
  try {
    const accepting = station.accept();
    conn = await device.connect({ id: station.id() }, ALPN);
    const theirs = await accepting;
    stream = await conn.openBi();
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "en" }, screen: { maxWidth: 800, maxHeight: 600, codecs: ["jpeg"], control: true } });
    let incoming = await theirs.acceptBi();
    let request = new Reader(incoming);
    let head = await request.line();
    served = answerScreen(hub, incoming, request.carry, head, { sub: "u", email: "test@example.com", name: "test", role: "member", workspace: "w", device: "d" }, () => true);
    let reader = new Reader(stream);
    assert.deepEqual(await reader.line(), { status: 503, headers: { "content-type": "application/json" } });
    await served;
    served = undefined;
    assert.equal(desktop.access().asking, true);
    console.log("Screen wire: pending consent is reported after the normal 4 second wait");
    for (let i = 0; i < 200 && !desktop.access().capture; i++) await sleep(100);
    assert.equal(desktop.access().capture, true, "the same portal session is ready after consent");
    await stream.finish();
    stream = await conn.openBi();
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "en" }, screen: { maxWidth: 800, maxHeight: 600, codecs: ["jpeg"], control: true } });
    incoming = await theirs.acceptBi();
    request = new Reader(incoming);
    head = await request.line();
    served = answerScreen(hub, incoming, request.carry, head, { sub: "u", email: "test@example.com", name: "test", role: "member", workspace: "w", device: "d" }, () => true);
    reader = new Reader(stream);
    assert.deepEqual(await reader.line(), { status: 200, headers: { "content-type": SCREEN_TYPE } });
    const frames = new FrameIn(stream, reader.carry, 16 * 1024 * 1024);
    let config = null, picture = null;
    while (!picture) {
      const got = await frames.next();
      assert.ok(got);
      if (got.kind === KIND.config) config = JSON.parse(got.payload.toString());
      if (got.kind === KIND.video) picture = got.payload;
    }
    assert.deepEqual(config, { codec: "jpeg", width: 800, height: 600 });
    assert.equal(picture[0], 1);
    assert.deepEqual([...picture.subarray(9, 11)], [0xff, 0xd8]);
    const send = (input) => stream.write(frame(KIND.input, Buffer.from(JSON.stringify(input))));
    await send({ t: "pointer", kind: "down", x: 0.5, y: 0.25, buttons: 1 });
    await send({ t: "pointer", kind: "up", x: 0.5, y: 0.25, buttons: 0 });
    await waitFor(/entry-pressed/g);
    await send({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 0 });
    await send({ t: "key", kind: "up", key: "a", code: "KeyA", mods: 0 });
    await waitFor(/text:a/g);
    await send({ t: "text", text: "Hi!你好" });
    await waitFor(/text:aHi!你好/g);
    await send({ t: "pointer", kind: "down", x: 0.5, y: 0.75, buttons: 1 });
    await send({ t: "pointer", kind: "up", x: 0.5, y: 0.75, buttons: 0 });
    await waitFor(/clicked/g);
    await send({ t: "pointer", kind: "down", x: 0.5, y: 0.75, buttons: 1 });
    await send({ t: "key", kind: "down", key: "b", code: "KeyB", mods: 0 });
    await waitFor(/key-down:b/g);
    await stream.finish();
    await served;
    served = undefined;
    await waitFor(/key-up:b/g);
    await waitFor(/button-up/g, 2);
    console.log("Screen wire: JPEG 800x600, pointer, keyboard, mixed-case Unicode and release on disconnect verified");
  } finally {
    if (served) { await stream?.finish(); await served; }
    conn?.close(0, "test done");
    await Promise.all([station.close(), device.close()]);
    await desktop.close();
  }
});
