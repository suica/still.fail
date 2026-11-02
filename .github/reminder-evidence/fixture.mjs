import { readFileSync, writeFileSync } from 'node:fs';

// Add an invented reminder to the existing history fixture, so both builds show the same app and data.
const path = 'apps/mbui/src/sffixture/decide_fixture.mbt';
const text = readFileSync(path, 'utf8');
const after = '      item("h6", "mark", { "text": "标记为做完了：截图已更新，测试全部通过" }),';
if (!text.includes(after)) throw new Error('history fixture changed');
writeFileSync(path, text.replace(after, `${after}
      item("h7", "received", {
        "note": "This is a new conversation: your earlier one in this session is no longer available.\\nThe agent can continue here.",
        "tasks": [],
        "messages": [{ "key": "m2", "from": { "name": "林", "bound": false }, "text": "请继续检查这个问题。" }],
      }),`));
