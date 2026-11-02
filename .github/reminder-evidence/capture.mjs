import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright-core';

const root = path.resolve('apps/mbui/out/web');
const server = http.createServer(async (req, res) => {
  const route = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  let file = path.join(root, route === '/' ? 'index.html' : route);
  try { if (!(await stat(file)).isFile()) file = path.join(root, 'index.html'); }
  catch { file = path.join(root, 'index.html'); }
  try {
    res.writeHead(200, { 'content-type': file.endsWith('.js') ? 'text/javascript' : 'text/html' });
    const body = await readFile(file);
    // Expose the capture clock and any host wait for diagnosing a frame that never reports completion.
    res.end(file.endsWith('/host.js')
      ? body.toString().replace('    frames++;', '    frames++; window.__frameData = { frame: frames, t, awaiting, why };')
      : body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--no-sandbox', '--enable-unsafe-swiftshader'] });
try {
  const page = await browser.newPage({ viewport: { width: 500, height: 700 }, deviceScaleFactor: 2, locale: 'zh-CN' });
  page.on('pageerror', (error) => console.error('pageerror:', error.message));
  const query = new URLSearchParams({ bench: '-1', shot_at: '200', MBUI_PLATFORM: 'mac', MBUI_FIXTURE: 'history', MBUI_LOCALE: 'zh-CN' });
  await page.goto(`http://127.0.0.1:${server.address().port}/?${query}`);
  const result = await (await page.waitForFunction(() => window.__shot || window.__done !== undefined, null, { timeout: 60000 }).catch(async (error) => {
    console.error('app state:', JSON.stringify(await page.evaluate(() => ({ logs: window.__logs?.slice(-30), frame: window.__frameData }))));
    await page.screenshot({ path: 'diagnostic.png' });
    throw error;
  })).jsonValue();
  if (!result?.frame || result.fail) throw new Error(`app did not draw: ${JSON.stringify(result)}`);
  await page.screenshot({ path: process.argv[2] });
  await page.screenshot({ path: process.argv[2].replace('.png', '-detail.png'), clip: { x: 8, y: 540, width: 480, height: 150 } });
} finally {
  await browser.close();
  server.close();
}
