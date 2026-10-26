#!/usr/bin/env node
/**
 * 用 Chrome CDP 渲染 cases/*.json：输出 350x800 的截图 + 每个元素的
 * getBoundingClientRect / 文本行 client rects / 关键计算样式，供与引擎
 * 渲染结果逐项对比。
 *
 * 用法：node tool/css_parity/render_browser.mjs
 * 输出：/tmp/css_parity/browser_<name>.png 与 browser_<name>.json
 */
import { spawn } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = resolve(import.meta.dirname, '../..');
const CASES = join(ROOT, 'tool/css_parity/cases');
const OUT = '/tmp/css_parity';
const OUT_ABS = resolve(OUT);
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const FONT_REG = join(ROOT, 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf');
const FONT_BOLD = join(ROOT, 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Bold.otf');
const WIDTH = 350;
const HEIGHT = 800;
const PORT = 9333;

mkdirSync(OUT, { recursive: true });

const collectScript = `(() => {
  const pick = (el) => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const out = {
      tag: el.tagName.toLowerCase(),
      cls: el.className || '',
      text: (el.textContent || '').slice(0, 40),
      rect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2) },
      style: {
        fontSize: cs.fontSize,
        lineHeight: cs.lineHeight,
        letterSpacing: cs.letterSpacing,
        wordSpacing: cs.wordSpacing,
        textAlign: cs.textAlign,
        textIndent: cs.textIndent,
        color: cs.color,
        backgroundColor: cs.backgroundColor,
        margin: [cs.marginTop, cs.marginRight, cs.marginBottom, cs.marginLeft].join(' '),
        padding: [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(' '),
        border: [cs.borderTopWidth, cs.borderRightWidth, cs.borderBottomWidth, cs.borderLeftWidth].join(' '),
        whiteSpace: cs.whiteSpace,
        textTransform: cs.textTransform,
        fontWeight: cs.fontWeight,
        fontStyle: cs.fontStyle,
        display: cs.display,
        verticalAlign: cs.verticalAlign,
        listStyleType: cs.listStyleType,
      },
      lines: [],
    };
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (!node.textContent.trim()) continue;
      const range = document.createRange();
      range.selectNodeContents(node);
      for (const rect of range.getClientRects()) {
        out.lines.push({ x: +rect.x.toFixed(2), y: +rect.y.toFixed(2), w: +rect.width.toFixed(2), h: +rect.height.toFixed(2) });
      }
    }
    return out;
  };
  return {
    viewport: { w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio },
    elements: Array.from(document.body.querySelectorAll('*')).map(pick),
    body: pick(document.body),
  };
})()`;

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.events = [];
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve: done, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(JSON.stringify(msg.error))) : done(msg.result);
      } else if (msg.method) {
        this.events.push(msg.method);
      }
    });
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    this.ws.send(JSON.stringify(payload));
    return new Promise((done, reject) => this.pending.set(id, { resolve: done, reject }));
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(fn, timeoutMs = 15000, step = 100) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const value = await fn();
    if (value) return value;
    await sleep(step);
  }
  throw new Error('timeout');
}

function buildHtml(caseData) {
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>
@font-face { font-family: "builtin_song"; src: url("file://${FONT_REG}"); font-weight: 400; font-display: block; }
@font-face { font-family: "builtin_song"; src: url("file://${FONT_BOLD}"); font-weight: 700; font-display: block; }
html, body { background: #ffffff; }
${caseData.css}
</style></head>
<body>${caseData.html}</body></html>`;
}

async function main() {
  const chrome = spawn(CHROME, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    // file:// 页面加载 @font-face 需要放开本地文件读取，否则字体回退
    // 到系统字体、字宽与引擎不一致。
    '--allow-file-access-from-files',
    `--remote-debugging-port=${PORT}`,
    '--no-first-run',
    '--user-data-dir=/tmp/css_parity/chrome-profile',
    'about:blank',
  ]);

  let version;
  try {
    version = await waitFor(async () => {
      try {
        const res = await fetch(`http://127.0.0.1:${PORT}/json/version`);
        return await res.json();
      } catch {
        return null;
      }
    });
  } catch (err) {
    chrome.kill();
    throw err;
  }

  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((r, j) => {
    ws.addEventListener('open', r, { once: true });
    ws.addEventListener('error', j, { once: true });
  });
  const cdp = new Cdp(ws);

  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: WIDTH,
    height: HEIGHT,
    deviceScaleFactor: 1,
    mobile: false,
  }, sessionId);
  await cdp.send('Page.enable', {}, sessionId);
  await cdp.send('Runtime.enable', {}, sessionId);

  const cases = readdirSync(CASES)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => JSON.parse(readFileSync(join(CASES, f), 'utf8')));

  for (const caseData of cases) {
    const htmlPath = join(OUT, `${caseData.name}.html`);
    writeFileSync(htmlPath, buildHtml(caseData), 'utf8');
    await cdp.send('Page.navigate', { url: `file://${htmlPath}` }, sessionId);
    await sleep(150);
    await cdp.send('Runtime.evaluate', {
      expression: 'document.fonts.ready.then(() => true)',
      awaitPromise: true,
    }, sessionId);
    await sleep(120);

    const probe = await cdp.send('Runtime.evaluate', {
      expression: collectScript,
      returnByValue: true,
    }, sessionId);
    writeFileSync(
      join(OUT, `browser_${caseData.name}.json`),
      JSON.stringify(probe.result.value, null, 2),
      'utf8',
    );

    const shot = await cdp.send('Page.captureScreenshot', { format: 'png' }, sessionId);
    writeFileSync(
      join(OUT, `browser_${caseData.name}.png`),
      Buffer.from(shot.data, 'base64'),
    );
    console.log(`ok ${caseData.name}`);
  }

  ws.close();
  chrome.kill();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
