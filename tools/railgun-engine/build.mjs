// SPIKE: bundle src/page.js (Railgun's SDK + snarkjs + ethers) into one
// browser script, dist/page.js, and print its size by package.
import { build } from 'esbuild';
import { gzipSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const r = await build({
  entryPoints: [join(here, process.argv[2] ?? 'src/page.js')],
  bundle: true, format: 'esm', platform: 'browser', target: 'safari17', minify: true, splitting: false,
  conditions: ['browser'], mainFields: ['browser', 'module', 'main'],
  alias: {
    crypto: 'crypto-browserify', stream: 'stream-browserify', buffer: 'buffer', events: 'events', util: 'util', assert: 'assert',
    path: 'path-browserify', process: join(here, 'node_modules/process/browser.js'),
  },
  define: { global: 'globalThis', 'process.env.NODE_ENV': '"production"' },
  inject: [join(here, 'src/inject.js')],
  external: ['fs', 'fs/promises', 'os', 'worker_threads', 'readline', 'constants', 'http', 'https', 'zlib', 'url', 'net', 'tls', 'child_process', 'node:*', 'react-native-*'],
  logLevel: 'warning', write: false, metafile: true,
});
mkdirSync(join(here, 'dist'), { recursive: true });
const bytes = r.outputFiles[0].contents;
const out = join(here, 'dist', (process.argv[2] ?? 'page.js').split('/').pop()); writeFileSync(out, bytes);
const mb = (n) => (n / 1048576).toFixed(2);
console.log(`${out} ${mb(bytes.length)} MB (gzip ${mb(gzipSync(bytes).length)} MB)`);
const by = {};
for (const [p, { bytesInOutput }] of Object.entries(Object.values(r.metafile.outputs)[0].inputs)) {
  const m = p.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/); const k = m ? m[1] : 'src'; by[k] = (by[k] ?? 0) + bytesInOutput;
}
for (const [k, v] of Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  ${mb(v).padStart(6)} MB  ${k}`);
