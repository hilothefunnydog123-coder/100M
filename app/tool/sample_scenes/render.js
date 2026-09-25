const { chromium } = require('playwright-core');
const fs = require('fs');
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
  page.on('console', (m) => console.log('console:', m.text()));
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  const jobs = process.argv.slice(2);
  for (const job of jobs) {
    const [scene, cam] = job.split(':');
    await page.goto(`http://localhost:8799/index.html?scene=${scene}&cam=${cam}`);
    await page.waitForFunction(() => window.result, null, { timeout: 180000 });
    const data = await page.evaluate(() => window.result);
    const file = `out/${scene}_${cam}.jpg`;
    fs.writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
    console.log('wrote', file);
  }
  await browser.close();
})();
