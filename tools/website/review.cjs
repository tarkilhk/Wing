// Browser acceptance for the static website. Reuses the repo's Playwright Core.
const { resolve } = require('node:path');
const { mkdirSync, writeFileSync, readFileSync } = require('node:fs');
const assert = require('node:assert/strict');

const [modulePath, baseUrl, outputPath] = process.argv.slice(2);
if (!modulePath || !baseUrl || !outputPath) {
  throw new Error('Usage: node tools/website/review.cjs <playwright-core-path> <preview-url> <output-directory>');
}
const playwright = require(resolve(modulePath));
const executableConfig = process.argv[5] ? JSON.parse(readFileSync(process.argv[5], 'utf8')) : {};
const launchOptions = name => ({ headless: true, ...(executableConfig[name] ? { executablePath: executableConfig[name] } : {}) });
const output = resolve(outputPath);
mkdirSync(output, { recursive: true });

async function loadedImages(page) {
  await page.evaluate(() => document.fonts.ready);
  await page.locator('img').evaluateAll(async images => {
    for (const image of images) image.loading = 'eager';
    await Promise.all(images.map(image => image.decode()));
  });
}

async function checkLayout(page, label) {
  const result = await page.evaluate(() => {
    const overflow = document.documentElement.scrollWidth > innerWidth + 1;
    const brokenImages = [...document.images].filter(image => !image.complete || !image.naturalWidth).map(image => image.src);
    const brokenAnchors = [...document.querySelectorAll('a[href^="#"]')].filter(link => link.hash && !document.getElementById(link.hash.slice(1))).map(link => link.hash);
    return { overflow, brokenImages, brokenAnchors };
  });
  assert.equal(result.overflow, false, `${label}: horizontal overflow`);
  assert.deepEqual(result.brokenImages, [], `${label}: broken images`);
  assert.deepEqual(result.brokenAnchors, [], `${label}: broken anchors`);
}

async function checkContrast(page) {
  const failures = await page.evaluate(() => {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    function rgba(color) {
      context.clearRect(0, 0, 1, 1);
      context.fillStyle = color;
      context.fillRect(0, 0, 1, 1);
      return [...context.getImageData(0, 0, 1, 1).data];
    }
    function luminance(color) {
      const linear = color.slice(0, 3).map(v => {
        const channel = v / 255;
        return channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4;
      });
      return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2];
    }
    const results = [];
    const selectors = 'p,dt,dd,h1,h2,h3,.button,.nav-link,.work-tab>span,.text-link,.trust-line>a,summary,.footer-top nav>a';
    for (const element of document.querySelectorAll(selectors)) {
      if (!element.getClientRects().length || element.closest('[hidden]')) continue;
      const style = getComputedStyle(element);
      let ancestor = element;
      let background;
      while (ancestor && !background) {
        const color = rgba(getComputedStyle(ancestor).backgroundColor);
        if (color[3] === 255) background = color;
        ancestor = ancestor.parentElement;
      }
      if (!background) continue;
      const a = luminance(rgba(style.color));
      const b = luminance(background);
      const ratio = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
      const large = parseFloat(style.fontSize) >= 24 || (parseFloat(style.fontSize) >= 18.66 && parseInt(style.fontWeight) >= 700);
      if (ratio < (large ? 3 : 4.5)) results.push({ text: element.textContent.trim().slice(0, 70), ratio });
    }
    return results;
  });
  assert.deepEqual(failures, [], 'Text contrast failures');
}

async function review(engineName) {
  const browser = await playwright[engineName].launch(launchOptions(engineName));
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('response', response => { if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`); });
  const response = await page.goto(baseUrl);
  assert.equal(response.status(), 200);
  await page.addStyleTag({ content: 'html { scroll-behavior: auto !important; }' });
  await loadedImages(page);
  assert.equal(await page.locator('main').count(), 1, 'One main landmark');
  assert.equal(await page.evaluate(() => document.fonts.check('650 32px Manrope') && document.fonts.check('400 18px "Source Sans 3"')), true, 'Self-hosted fonts loaded');

  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: width < 600 ? 844 : 1000 });
    for (const theme of ['dark', 'light']) {
      await page.locator(`[data-theme="${theme}"]`).click();
      await loadedImages(page);
      for (const name of ['follow', 'steer', 'results']) {
        await page.locator(`#tab-${name}`).click();
        assert.equal(await page.locator('[role="tabpanel"]:visible').count(), 1);
        assert.equal(await page.locator(`#tab-${name}`).getAttribute('aria-selected'), 'true');
        assert.equal(await page.locator(`#panel-${name} img`).getAttribute('src').then(src => src.endsWith(`-${theme}.png`)), true);
        const image = await page.locator(`#panel-${name} img`).getAttribute('src');
        assert.equal(await page.locator(`#panel-${name} [data-expand-image]`).getAttribute('href'), image);
        await checkLayout(page, `${engineName} ${width} ${theme} ${name}`);
      }
    }
    await page.locator('#tab-follow').click();
    await page.locator('[data-theme="dark"]').click();
    await loadedImages(page);
    await page.evaluate(() => scrollTo(0, 0));
    if (width === 1440 || width === 390) {
      await page.screenshot({ path: resolve(output, `${engineName}-${width}-full.png`), fullPage: true });
      await page.screenshot({ path: resolve(output, `${engineName}-${width}-hero.png`) });
    }
  }

  await page.locator('#tab-follow').focus();
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.locator('#tab-steer').getAttribute('aria-selected'), 'true');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'tab-steer');
  assert.equal(await page.locator('.work-stage').getAttribute('data-pointer-change'), 'false', 'Keyboard changes do not animate');
  await page.keyboard.press('End');
  assert.equal(await page.locator('#tab-results').getAttribute('aria-selected'), 'true');
  await page.keyboard.press('Home');
  assert.equal(await page.locator('#tab-follow').getAttribute('aria-selected'), 'true');
  for (const question of await page.locator('details').all()) {
    await question.locator('summary').click();
    assert.equal(await question.getAttribute('open'), '');
    await question.locator('summary').click();
    assert.equal(await question.getAttribute('open'), null);
  }
  await checkContrast(page);
  for (const width of [390, 1024]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.evaluate(() => document.documentElement.style.fontSize = '200%');
    await checkLayout(page, `${engineName} ${width} 200% text`);
    await page.evaluate(() => document.documentElement.style.fontSize = '');
  }
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const motion = await page.locator('.hero-phone').evaluate(el => getComputedStyle(el).animationName);
  assert.equal(motion, 'none');
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.locator('#tab-steer').click();
  await page.screenshot({ path: resolve(output, `${engineName}-steer.png`), fullPage: true });
  assert.deepEqual(errors, [], `${engineName}: browser errors`);
  await browser.close();

  const staticBrowser = await playwright[engineName].launch(launchOptions(engineName));
  const staticPage = await staticBrowser.newPage({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
  await staticPage.goto(baseUrl);
  assert.equal(await staticPage.locator('[role="tabpanel"]:visible').count(), 3, 'All workflows remain readable without JavaScript');
  await checkLayout(staticPage, `${engineName} JavaScript disabled`);
  await staticBrowser.close();
  return `${engineName}: 30 viewport/theme/workflow combinations; keyboard tabs; disclosures; text contrast; 200% text; reduced motion; no-JavaScript reading.`;
}

(async () => {
  const reports = [];
  for (const engine of ['chromium', 'firefox', 'webkit']) {
    reports.push(await review(engine));
    console.log(reports.at(-1));
  }
  writeFileSync(resolve(output, 'verification.txt'), reports.join('\n') + '\n');
})().catch(error => { console.error(error); process.exit(1); });
