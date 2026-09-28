// Run against the debug WebView in large_html_native_preview.dart, via ADB forward.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_CORE_PATH);
const browser = await chromium.connectOverCDP(process.env.WING_CDP_ENDPOINT, { noDefaults: true });
try {
  const page = browser.contexts().flatMap(context => context.pages())
    .find(page => page.url() === 'https://wing-diagrams.invalid/index.html');
  assert.ok(page, 'Native Wing viewer must be open');
  const frame = page.frameLocator('#diagram iframe');
  await frame.locator('#large-title').waitFor({ timeout: 60000 });
  assert.equal(await frame.locator('#large-title').textContent(), 'Complete 32 MiB report');
  assert.equal(await frame.locator('body').getAttribute('data-parent-access'), 'blocked');
  assert.equal(await frame.locator('body').getAttribute('data-storage'), 'blocked');
  assert.equal(await page.locator('body').getAttribute('data-escaped'), null);
  await frame.locator('#increment').click();
  assert.equal(await frame.locator('#count').textContent(), '1');
  assert.equal(await frame.locator('html').evaluate(() => document.compatMode), 'CSS1Compat');
  assert.equal(await page.locator('#diagram iframe').getAttribute('src'), 'report.html');
  assert.equal(await page.locator('#diagram iframe').getAttribute('sandbox'), 'allow-scripts');
  await mkdir(resolve('build/large-html-review'), { recursive: true });
  await page.screenshot({ path: resolve('build/large-html-review/native-32mib.png') });
  console.log('PASS: native Android WebView rendered the complete 32 MiB report; controls work and parent/storage access remain blocked.');
} finally {
  await browser.close();
}
