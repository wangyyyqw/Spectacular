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
// 默认输出目录；多人/多实例并行时用 CSS_PARITY_OUT 隔离。
const OUT = process.env.CSS_PARITY_OUT || '/tmp/css_parity';
const OUT_ABS = resolve(OUT);
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const FONT_REG = join(ROOT, 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf');
const FONT_BOLD = join(ROOT, 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Bold.otf');
const WIDTH = 350;
const HEIGHT = 800;
// 默认调试端口；并行时用 CSS_PARITY_PORT 换端口，避免抢占。
const PORT = Number(process.env.CSS_PARITY_PORT || 9333);

mkdirSync(OUT, { recursive: true });

const collectScript = `(() => {
  const rectOf = (r) => ({
    x: +r.x.toFixed(2),
    y: +r.y.toFixed(2),
    w: +r.width.toFixed(2),
    h: +r.height.toFixed(2),
  });
  // 文本行几何：取文本节点的 client rects（字体盒，不是行盒），再把
  // 同一视觉行的多段（行内 span / 上下标）按纵向重叠合并成一行，
  // 与引擎「一块 N 行」的口径对齐。行 y/h 取面积最大的 run（锚点），
  // 避免上下标把行顶拉偏。
  // 字体 ascent：Chrome 文本 rect 的 y 是行内盒顶，画笔基线 = rect.y +
  // 字体 ascent（fontBoundingBoxAscent，与 Flutter computeDistanceToActualBaseline
  // 同源）；墨迹 ascent 是字形墨迹顶，不能直接加到 rect.y 上。
  const ascentCache = new Map();
  const inkAscent = (node) => {
    const text = (node.textContent || '').trim();
    const parent = node.parentElement;
    if (!text || !parent) return 0;
    const cs = getComputedStyle(parent);
    const key = [cs.fontStyle, cs.fontWeight, cs.fontSize, cs.fontFamily, text].join('|');
    if (ascentCache.has(key)) return ascentCache.get(key);
    const canvas = document.createElement('canvas').getContext('2d');
    canvas.font = [cs.fontStyle, cs.fontWeight, cs.fontSize, cs.fontFamily].join(' ');
    const ascent = canvas.measureText(text).fontBoundingBoxAscent || 0;
    ascentCache.set(key, ascent);
    return ascent;
  };
  const mergeLines = (rects) => {
    const items = rects.map((r) => ({ ...r }));
    items.sort((a, b) => b.w * b.h - a.w * a.h);
    const lines = [];
    for (const r of items) {
      let target = null;
      for (const line of lines) {
        const overlap = Math.min(r.y + r.h, line.y + line.h) - Math.max(r.y, line.y);
        if (overlap > Math.min(r.h, line.h) * 0.5) {
          target = line;
          break;
        }
      }
      if (!target) {
        lines.push({ ...r });
        continue;
      }
      const right = Math.max(target.x + target.w, r.x + r.w);
      target.x = Math.min(target.x, r.x);
      target.w = right - target.x;
    }
    return lines
      .sort((a, b) => a.y - b.y)
      .map((r) => ({
        x: +r.x.toFixed(2),
        y: +r.y.toFixed(2),
        w: +r.w.toFixed(2),
        h: +r.h.toFixed(2),
        baseline: r.baseline === undefined ? undefined : +r.baseline.toFixed(2),
      }));
  };
  // CSS 生成内容没有对应 DOM Range：用伪元素计算样式与 canvas 量出宽度，
  // 再把 ::before 接到首行左侧、::after 接到末行右侧。
  const pseudoText = (el, which) => {
    const content = getComputedStyle(el, which).content;
    if (!content || content === 'none' || content === 'normal') return '';
    try {
      const parsed = JSON.parse(content);
      return typeof parsed === 'string' ? parsed : '';
    } catch {
      return '';
    }
  };
  const pseudoHasContent = (el, which) => {
    const content = getComputedStyle(el, which).content;
    return Boolean(content && content !== 'none' && content !== 'normal');
  };
  // counter()/attr() 的计算值仍保留函数源码，无法直接得到生成文本。
  // 起始对齐时，正文首字的 x 已经包含 ::before 宽度，用元素内容左缘
  // 反推生成段宽，并把首行扩展到包含它，避免与引擎多算一份前缀。
  const prependPseudoFromLayout = (el, first) => {
    const style = getComputedStyle(el);
    const align = style.textAlign;
    if (!['start', 'left', 'justify'].includes(align) || style.direction !== 'ltr') {
      return false;
    }
    const rect = el.getBoundingClientRect();
    const contentLeft =
      rect.x + (parseFloat(style.borderLeftWidth) || 0) +
      (parseFloat(style.paddingLeft) || 0);
    if (!Number.isFinite(contentLeft) || first.x <= contentLeft + 0.01) return false;
    first.w += first.x - contentLeft;
    first.x = contentLeft;
    return true;
  };
  let pseudoProbeId = 0;
  const pseudoWidth = (el, which, text) => {
    if (!text) return 0;
    // 生成文本没有 DOM Range。临时关掉该元素的伪元素，在真实段落上下文
    // 插入同样式的行内盒，才能保留中文标点间距与相邻文本的 shaping。
    const className = '__css_parity_pseudo_' + (++pseudoProbeId);
    const rule = document.createElement('style');
    rule.textContent =
      '.' + className + '::before,' +
      '.' + className + '::after{content:none!important}';
    document.head.append(rule);
    el.classList.add(className);
    const style = getComputedStyle(el, which);
    const span = document.createElement('span');
    span.textContent = text;
    span.style.cssText = [
      'font-family:' + style.fontFamily,
      'font-size:' + style.fontSize,
      'font-style:' + style.fontStyle,
      'font-weight:' + style.fontWeight,
      'font-stretch:' + style.fontStretch,
      'font-feature-settings:' + style.fontFeatureSettings,
      'font-variant:' + style.fontVariant,
      'letter-spacing:' + style.letterSpacing,
      'word-spacing:' + style.wordSpacing,
      'text-transform:' + style.textTransform,
      'text-spacing-trim:' + style.textSpacingTrim,
    ].join(';');
    if (which === '::before') {
      el.insertBefore(span, el.firstChild);
    } else {
      el.append(span);
    }
    const range = document.createRange();
    range.selectNodeContents(span);
    const rects = Array.from(range.getClientRects())
      .filter((rect) => rect.width > 0);
    const rect = which === '::before' ? rects[0] : rects[rects.length - 1];
    const width = rect ? rect.width : 0;
    span.remove();
    el.classList.remove(className);
    rule.remove();
    return width;
  };
  // 原子行内盒（inline-block/inline-flex/...）有自己的元素条目与行列表，
  // 其内部文本行不能并进父段落，否则父段落会多出「盒内容行」的伪影。
  const atomicInline = new Set(['inline-block', 'inline-flex', 'inline-grid',
    'inline-table', '-webkit-inline-box']);
  const ownText = (node, el) => {
    let parent = node.parentElement;
    while (parent && parent !== el) {
      if (atomicInline.has(getComputedStyle(parent).display)) return false;
      parent = parent.parentElement;
    }
    return true;
  };
  const textRectsRaw = (el) => {
    const raw = [];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (!node.textContent.trim()) continue;
      if (!ownText(node, el)) continue;
      // ruby 注音是独立的上/下注释盒，不属于主文本行；若混入段落
      // 行矩形，会让引擎（只导出基字文本）与浏览器凭空错位。
      let annotation = node.parentElement;
      while (annotation && annotation !== el &&
          !['RT', 'RP'].includes(annotation.tagName)) {
        annotation = annotation.parentElement;
      }
      if (annotation && annotation !== el) continue;
      const range = document.createRange();
      range.selectNodeContents(node);
      const ascent = inkAscent(node);
      // 行尾空白：Chrome 的 Range rect 把行尾空格计入宽度，引擎按 Skia
      // 口径不计；从该节点的最后一个 rect 上扣掉尾部空白宽。
      const trailing = (node.textContent || '').match(/\s+$/);
      let trailingWidth = 0;
      if (trailing) {
        const cs = getComputedStyle(node.parentElement);
        const canvas = document.createElement('canvas').getContext('2d');
        canvas.font = [cs.fontStyle, cs.fontWeight, cs.fontSize, cs.fontFamily].join(' ');
        trailingWidth = canvas.measureText(trailing[0]).width || 0;
      }
      const rects = Array.from(range.getClientRects()).filter(
        (rect) => rect.width > 0 || rect.height > 0);
      rects.forEach((rect, index) => {
        const item = rectOf(rect);
        if (index === rects.length - 1 && trailingWidth > 0) {
          item.w = +Math.max(0, item.w - trailingWidth).toFixed(2);
        }
        item.baseline = +(rect.y + ascent).toFixed(2);
        raw.push(item);
      });
    }
    if (raw.length > 0) {
      const beforeWidth = pseudoWidth(
        el,
        '::before',
        pseudoText(el, '::before').replace(/^\s+/, ''),
      );
      const first = raw.reduce((best, item) =>
        item.y < best.y || (item.y === best.y && item.x < best.x)
          ? item : best);
      if (beforeWidth > 0) {
        first.x -= beforeWidth;
        first.w += beforeWidth;
      } else if (pseudoHasContent(el, '::before')) {
        prependPseudoFromLayout(el, first);
      }
      const afterWidth = pseudoWidth(
        el,
        '::after',
        pseudoText(el, '::after').replace(/\s+$/, ''),
      );
      if (afterWidth > 0) {
        const last = raw.reduce((best, item) =>
          item.y > best.y || (item.y === best.y && item.x > best.x)
            ? item : best);
        last.w += afterWidth;
      }
    }
    return raw.map((r) => ({
      x: +r.x.toFixed(2),
      y: +r.y.toFixed(2),
      w: +r.w.toFixed(2),
      h: +r.h.toFixed(2),
      baseline: +r.baseline.toFixed(2),
    }));
  };
  const textRects = (el) => mergeLines(textRectsRaw(el));
  const inlineish = new Set(['inline', 'inline-block', 'inline-flex', 'inline-grid',
    'inline-table', 'contents', 'none']);
  const blockChild = (el) => Array.from(el.children).some(
    (child) => !inlineish.has(getComputedStyle(child).display));
  const semanticText = (el) => {
    const clone = el.cloneNode(true);
    for (const annotation of clone.querySelectorAll('rt,rp')) {
      annotation.remove();
    }
    return clone.textContent || '';
  };
  const pick = (el) => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const directText = Array.from(el.childNodes)
      .filter((node) => node.nodeType === Node.TEXT_NODE)
      .map((node) => node.textContent || '')
      .join('')
      .trim();
    const out = {
      tag: el.tagName.toLowerCase(),
      directText,
      container: directText.length === 0 && blockChild(el),
      cls: el.className || '',
      text: semanticText(el).slice(0, 400),
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
        // outline-style:none 时浏览器仍报告 medium（3px），但不会绘制。
        outlineWidth: cs.outlineStyle === 'none' ? '0px' : cs.outlineWidth,
        outlineStyle: cs.outlineStyle,
        outlineOffset: cs.outlineOffset,
        whiteSpace: cs.whiteSpace,
        textTransform: cs.textTransform,
        textDecorationUnderline: cs.textDecorationLine.includes('underline'),
        textDecorationLineThrough: cs.textDecorationLine.includes('line-through'),
        textDecorationOverline: cs.textDecorationLine.includes('overline'),
        fontWeight: cs.fontWeight,
        fontStyle: cs.fontStyle,
        fontStretch: cs.fontStretch,
        display: cs.display,
        verticalAlign: cs.verticalAlign,
        listStyleType: cs.listStyleType,
        boxSizing: cs.boxSizing,
        textOverflow: cs.textOverflow,
        overflow: cs.overflow,
        overflowX: cs.overflowX,
        overflowY: cs.overflowY,
        transform: cs.transform,
        transformOrigin: cs.transformOrigin,
        writingMode: cs.writingMode,
        textOrientation: cs.textOrientation,
        direction: cs.direction,
        hyphens: cs.hyphens,
        wordBreak: cs.wordBreak,
        overflowWrap: cs.overflowWrap,
        columnCount: cs.columnCount,
        columnWidth: cs.columnWidth,
        columnGap: cs.columnGap,
        listStylePosition: cs.listStylePosition,
      },
      lines: textRects(el),
      rawLines: textRectsRaw(el),
      pseudo: {
        before: pseudoText(el, '::before'),
        after: pseudoText(el, '::after'),
        beforeWidth: pseudoWidth(
          el,
          '::before',
          pseudoText(el, '::before').replace(/^\s+/, ''),
        ),
        afterWidth: pseudoWidth(
          el,
          '::after',
          pseudoText(el, '::after').replace(/\s+$/, ''),
        ),
      },
      columnRects: Array.from(el.getClientRects())
        .filter((rect) => rect.width > 0)
        .map((rect) => ({ x: +rect.x.toFixed(2), y: +rect.y.toFixed(2), w: +rect.width.toFixed(2), h: +rect.height.toFixed(2) })),
    };
    return out;
  };
  // 表格单元格：行号/格序号取 DOM 的 rowIndex/cellIndex，与引擎导出的
  // (row, col) 对齐；tableIndex 对应引擎导出的第 n 个表格块。
  const tables = Array.from(document.querySelectorAll('table'));
  const pickCell = (el) => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      tag: el.tagName.toLowerCase(),
      table: tables.indexOf(el.closest('table')),
      row: el.parentElement && el.parentElement.rowIndex >= 0 ? el.parentElement.rowIndex : -1,
      col: el.cellIndex,
      text: el.textContent || '',
      rect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2) },
      style: {
        fontSize: cs.fontSize,
        lineHeight: cs.lineHeight,
        textAlign: cs.textAlign,
        verticalAlign: cs.verticalAlign,
        backgroundColor: cs.backgroundColor,
        padding: [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(' '),
        border: [cs.borderTopWidth, cs.borderRightWidth, cs.borderBottomWidth, cs.borderLeftWidth].join(' '),
      },
      lines: textRects(el),
      rawLines: textRectsRaw(el),
      columnRects: Array.from(el.getClientRects())
        .filter((rect) => rect.width > 0)
        .map((rect) => ({ x: +rect.x.toFixed(2), y: +rect.y.toFixed(2), w: +rect.width.toFixed(2), h: +rect.height.toFixed(2) })),
    };
  };
  return {
    viewport: { w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio },
    documentHeight: document.documentElement.scrollHeight,
    elements: Array.from(document.body.querySelectorAll('*'))
      .filter((el) => !['rt', 'rp'].includes(el.tagName.toLowerCase()))
      .map(pick),
    cells: Array.from(document.querySelectorAll('td,th')).map(pickCell),
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
    // profile 跟随输出目录：并行实例不抢同一个 profile
    `--user-data-dir=${join(OUT_ABS, 'chrome-profile')}`,
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
    .map((f) => JSON.parse(readFileSync(join(CASES, f), 'utf8')))
    .filter((caseData) => {
      const selected = (process.env.CSS_PARITY_CASES || '')
        .split(',')
        .map((name) => name.trim())
        .filter(Boolean);
      return selected.length === 0 || selected.includes(caseData.name);
    });

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
