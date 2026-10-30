#!/usr/bin/env bash
# Render ./index.html (file://, no network) at 360x800 and 1280x900.
# Writes mobile.png, desktop.png and computed.json to /tmp/reviews.
# Usage: render.sh [dir-with-index.html]   (default: $PWD)
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "usage: render.sh [dir]  - screenshots + computed.json of dir/index.html into /tmp/reviews"
  exit 0
fi

export RENDER_DIR="${1:-$PWD}"
export REVIEWS_DIR="${REVIEWS_DIR:-/tmp/reviews}"
[ -f "$RENDER_DIR/index.html" ] || { echo "render.sh: $RENDER_DIR/index.html not found" >&2; exit 2; }
mkdir -p "$REVIEWS_DIR"

read -r -d '' SCRIPT <<'JS' || true
const { execSync } = require('child_process');
const fs = require('fs');
const { chromium } = require(execSync('npm root -g').toString().trim() + '/playwright');

const url = 'file://' + process.env.RENDER_DIR + '/index.html';
const out = process.env.REVIEWS_DIR;

function parse(c) {
  let m = c.match(/^rgba?\(([^)]+)\)$/);
  if (m) { const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p[3] === undefined ? 1 : p[3]]; }
  m = c.match(/^color\(srgb ([^)]+)\)$/);
  if (m) { const p = m[1].split(/[ /]+/).filter(Boolean).map(Number); return [p[0] * 255, p[1] * 255, p[2] * 255, p[3] === undefined ? 1 : p[3]]; }
  return null;
}
const lin = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
const lum = (c) => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
function ratio(fg, bg) {
  const a = parse(fg), b = parse(bg);
  if (!a || !b) return null;
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return Math.round(((hi + 0.05) / (lo + 0.05)) * 100) / 100;
}

// Runs in the page: computed props for the first element matching sel (or the focused element).
const probe = (sel) => {
  const el = sel ? document.querySelector(sel) : document.activeElement;
  if (!el || el === document.body && sel === null) return null;
  const bgOf = (e) => {
    for (; e; e = e.parentElement) {
      const c = getComputedStyle(e).backgroundColor;
      const m = c.match(/[\d.]+/g);
      if (m && (m.length < 4 || Number(m[3]) > 0)) return c;
    }
    return 'rgb(255, 255, 255)';
  };
  const s = getComputedStyle(el);
  return {
    tag: el.tagName.toLowerCase(), text: (el.textContent || '').trim().slice(0, 40),
    fontFamily: s.fontFamily, fontSize: s.fontSize, color: s.color,
    backgroundColor: bgOf(el), outlineStyle: s.outlineStyle, outlineWidth: s.outlineWidth,
    outlineColor: s.outlineColor, outlineOffset: s.outlineOffset,
  };
};

(async () => {
  const browser = await chromium.launch();
  const result = { url, layout: {}, styles: {}, focus: {}, contrast: {} };
  for (const [name, w, h] of [['mobile', 360, 800], ['desktop', 1280, 900]]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, colorScheme: 'light', reducedMotion: 'reduce' });
    // file:// only: no network from the renderer either.
    await ctx.route('**/*', (r) => r.request().url().startsWith('file:') ? r.continue() : r.abort());
    const page = await ctx.newPage();
    await page.goto(url);
    await page.screenshot({ path: `${out}/${name}.png`, fullPage: true });
    result.layout[name] = await page.evaluate(() => {
      const de = document.documentElement;
      const m = document.querySelector('main') || document.body;
      const r = m.getBoundingClientRect(), s = getComputedStyle(m);
      const px = (v) => parseFloat(v) || 0;
      return {
        scrollWidth: de.scrollWidth, clientWidth: de.clientWidth,
        mainWidth: Math.round(r.width),
        mainContentWidth: Math.round(r.width - px(s.paddingLeft) - px(s.paddingRight) - px(s.borderLeftWidth) - px(s.borderRightWidth)),
        mainMaxWidth: s.maxWidth, mainLeft: Math.round(r.left), mainRight: Math.round(de.clientWidth - r.right),
        measure: getComputedStyle(de).getPropertyValue('--measure').trim(),
      };
    });
    if (name === 'desktop') {
      for (const sel of ['body', 'h1', 'summary']) result.styles[sel] = await page.evaluate(probe, sel);
      // Real keyboard focus so :focus-visible applies.
      for (let i = 0; i < 60 && !(result.focus.a && result.focus.summary); i++) {
        await page.keyboard.press('Tab');
        const f = await page.evaluate(probe, null);
        if (f && f.tag === 'a' && !result.focus.a) result.focus.a = f;
        if (f && f.tag === 'summary' && !result.focus.summary) result.focus.summary = f;
      }
      for (const k of ['body', 'h1', 'summary']) {
        const s = result.styles[k];
        result.contrast[k] = s ? ratio(s.color, s.backgroundColor) : null;
      }
    }
    await ctx.close();
  }
  await browser.close();
  fs.writeFileSync(`${out}/computed.json`, JSON.stringify(result, null, 2));
})().catch((e) => { console.error(e); process.exit(1); });
JS

node -e "$SCRIPT"
echo "render.sh: wrote $REVIEWS_DIR/{mobile.png,desktop.png,computed.json}"
