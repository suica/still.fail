import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const load = (name) => import(pathToFileURL(resolve('client/core-ts/src', name)).href);
const before = await load('present-before.ts');
const after = await load('present.ts');
const summary = { key: 's-c1', runtime: 'claude', process: 'cold', pending: 1, startFailed: true, lastTurn: null };
const states = { before: before.sessionStatus(summary), after: after.sessionStatus(summary) };
assert.equal(states.before, 'queued');
assert.equal(states.after, 'failed');
const at = { createdAt: { ago: '刚刚', full: '2026/11/22 09:00' } };
const msg = (seq, authorKind, author, by, text, extra = {}) => ({
  seq, thread: 7, ts: `test-${seq}`, authorKind, author, by, text,
  attachments: [], quotes: [], createdAt: seq, mine: false, system: authorKind === 'ember', waiting: false, time: at, ...extra,
});
for (const [name, status] of Object.entries(states)) {
  const chat = {
    archived: false, me: { email: 'test@example.com' }, thread: { id: 7, unread: 0 },
    title: '启动失败的示例', people: [],
    agents: [{ session: { key: 's-c1', runtime: 'claude', maker: { id: 'anthropic', name: 'Anthropic' }, agentText: 'Claude', statusText: status === 'failed' ? '无法启动 agent' : '等待中', tone: status === 'failed' ? 'danger' : 'neutral', pending: 1 }, status }],
    messages: [
      msg(1, 'person', 'test@example.com', { name: '测试用户' }, '请继续处理这个任务', { mine: true, waiting: true }),
      msg(2, 'ember', 'ember', { name: 'still.fail' }, '⚠️ 无法启动 agent', { notice: { failed: true, words: '无法启动 agent', detail: '该 workspace 没有可运行的 Profile。' } }),
    ],
    more: false, newer: false, outbox: [], offline: false, archivable: true, asks: [], askClear: false,
  };
  const fixture = { workspace: 'ws1', fallback: true, open: [{ page: 'chat', station: 'ws1/st1', session: 's-c1' }], topics: [{ topic: { topic: 'chat', station: 'ws1/st1', session: 's-c1' }, value: chat }] };
  writeFileSync(`out/${name}.json`, JSON.stringify(fixture));
}
console.log(states);
