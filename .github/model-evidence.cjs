const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE);
const root = path.resolve('apps/mbui/out/web');
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://fixture').pathname));
  const actual = fs.existsSync(file) && fs.statSync(file).isFile() ? file : path.join(root, 'index.html');
  res.writeHead(200, { 'content-type': actual.endsWith('.js') ? 'text/javascript' : 'text/html' });
  fs.createReadStream(actual).pipe(res);
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({headless: true, args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
  const page = await (await browser.newContext({viewport: {width: 1280, height: 800}, deviceScaleFactor: 2})).newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/?bench=-1&shot_at=3000&MBUI_FIXTURE=settings-profile-spread`);
  const shot = await page.waitForFunction(() => window.__shot || (window.__done !== undefined && {done: window.__done}), null, {timeout: 120000}).then(h => h.jsonValue());
  if (!shot || !shot.frame || shot.fail) throw new Error(`No fixture frame: ${JSON.stringify(shot)}`);
  await page.screenshot({path: process.argv[2]});
  await browser.close();
  server.close();
})().catch(err => { console.error(err); server.close(); process.exitCode = 1; });
