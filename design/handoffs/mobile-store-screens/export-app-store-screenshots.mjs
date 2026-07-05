import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { access, mkdir, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const sharp = require('sharp');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sourceFile = 'Read the World - Store Screenshots.dc.html';
const outputRoot = path.join(__dirname, 'app-store-connect-screenshots');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const exportsToMake = [
  {
    folder: 'iphone-6.5-1284x2778',
    sourceWidth: 1320,
    sourceHeight: 2868,
    width: 1320,
    height: 2868,
    outputWidth: 1284,
    outputHeight: 2778,
    labels: [
      ['AS 1 Answer', '01-answer.png'],
      ['AS 2 Predict', '02-predict.png'],
      ['AS 3 Reveal', '03-reveal.png'],
      ['AS 4 Score', '04-read-score.png'],
      ['AS 5 Ways', '05-ways-to-play.png'],
      ['AS 6 Party', '06-party-mode.png'],
    ],
  },
  {
    folder: 'ipad-13-2064x2752',
    sourceWidth: 2064,
    sourceHeight: 2752,
    width: 2064,
    height: 2752,
    outputWidth: 2064,
    outputHeight: 2752,
    labels: [
      ['iPad 1 Answer', '01-answer.png'],
      ['iPad 2 Predict', '02-predict.png'],
      ['iPad 3 Reveal', '03-reveal.png'],
      ['iPad 4 Score', '04-read-score.png'],
      ['iPad 5 Ways', '05-ways-to-play.png'],
      ['iPad 6 Party', '06-party-mode.png'],
    ],
  },
];

function cssString(value) {
  return String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

async function createStaticServer(rootDir) {
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1');
      const requestedPath = decodeURIComponent(url.pathname === '/' ? `/${sourceFile}` : url.pathname);
      const filePath = path.normalize(path.join(rootDir, requestedPath));

      if (!filePath.startsWith(rootDir)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      await access(filePath);
      res.writeHead(200, {
        'Content-Type': mimeTypes[path.extname(filePath).toLowerCase()] ?? 'application/octet-stream',
      });
      createReadStream(filePath).pipe(res);
    } catch {
      res.writeHead(404);
      res.end('Not found');
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return {
    close: () => new Promise((resolve) => server.close(resolve)),
    port: address.port,
  };
}

async function main() {
  await rm(outputRoot, { recursive: true, force: true });
  await mkdir(outputRoot, { recursive: true });

  const staticServer = await createStaticServer(__dirname);
  const browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
    args: ['--disable-dev-shm-usage'],
  });

  const manifest = [];

  try {
    const context = await browser.newContext({
      colorScheme: 'light',
      deviceScaleFactor: 1,
      viewport: { width: 2400, height: 3200 },
    });
    const page = await context.newPage();
    page.setDefaultTimeout(45_000);

    const url = `http://127.0.0.1:${staticServer.port}/${encodeURIComponent(sourceFile)}`;
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForFunction(() => window.__dcRegistry && document.querySelectorAll('[data-screen-label] .sc-host').length >= 18);
    await page.evaluate(() => document.fonts?.ready);
    await page.waitForFunction(() => {
      return Array.from(document.querySelectorAll('[data-screen-label] .sc-host')).every((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 1000 && rect.height > 1800 && element.innerText.trim().length > 0;
      });
    });

    for (const group of exportsToMake) {
      const sourceWidth = group.sourceWidth ?? group.width;
      const sourceHeight = group.sourceHeight ?? group.height;
      const outputWidth = group.outputWidth ?? group.width;
      const outputHeight = group.outputHeight ?? group.height;
      const groupDir = path.join(outputRoot, group.folder);
      await mkdir(groupDir, { recursive: true });

      for (const [label, filename] of group.labels) {
        const locator = page.locator(`[data-screen-label="${cssString(label)}"] .sc-host`);
        const count = await locator.count();
        if (count !== 1) {
          throw new Error(`Expected one frame for "${label}", found ${count}.`);
        }

        const box = await locator.boundingBox();
        if (!box) {
          throw new Error(`Frame "${label}" has no bounding box.`);
        }

        const roundedWidth = Math.round(box.width);
        const roundedHeight = Math.round(box.height);
        if (roundedWidth !== sourceWidth || roundedHeight !== sourceHeight) {
          throw new Error(`Frame "${label}" is ${roundedWidth}x${roundedHeight}, expected source ${sourceWidth}x${sourceHeight}.`);
        }

        const tmpPath = path.join(groupDir, `.${filename}.tmp.png`);
        const outPath = path.join(groupDir, filename);

        await locator.screenshot({ path: tmpPath, animations: 'disabled', omitBackground: false });
        const capturedMetadata = await sharp(tmpPath).metadata();
        if ((capturedMetadata.width ?? 0) < sourceWidth || (capturedMetadata.height ?? 0) < sourceHeight) {
          throw new Error(`Captured ${filename} is too small: ${capturedMetadata.width}x${capturedMetadata.height}, expected at least ${sourceWidth}x${sourceHeight}.`);
        }

        await sharp(tmpPath)
          .extract({ left: 0, top: 0, width: sourceWidth, height: sourceHeight })
          .resize({ width: outputWidth, height: outputHeight, fit: 'cover', position: 'center' })
          .removeAlpha()
          .png({ compressionLevel: 9 })
          .toFile(outPath);
        await rm(tmpPath, { force: true });

        const metadata = await sharp(outPath).metadata();
        if (metadata.width !== outputWidth || metadata.height !== outputHeight || metadata.hasAlpha) {
          throw new Error(`Exported ${filename} metadata mismatch: ${metadata.width}x${metadata.height}, hasAlpha=${metadata.hasAlpha}`);
        }

        manifest.push({
          file: path.relative(outputRoot, outPath),
          label,
          width: metadata.width,
          height: metadata.height,
          format: metadata.format,
          hasAlpha: metadata.hasAlpha,
        });
      }
    }

    await writeFile(path.join(outputRoot, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  } finally {
    await browser.close();
    await staticServer.close();
  }

  console.log(`Exported ${manifest.length} screenshots to ${outputRoot}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
