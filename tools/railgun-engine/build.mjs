// Builds the Railgun engine the app's hidden web view runs (prd §1713):
// src/engine.js plus Railgun's wallet SDK, ethers and snarkjs, into ONE module
// script, and the SDK's two wasm files beside it,
//   Casberi/Casberi/Resources/railgun-engine.js
//   Casberi/Casberi/Resources/poseidon_hash_wasm_bg.wasm
//   Casberi/Casberi/Resources/curve25519_scalarmult_wasm_bg.wasm
// Every dependency is pinned exactly (package.json + package-lock.json), and
// esbuild's output is a function of its input, so the same tree builds the
// same bytes.
//   npm ci && node build.mjs            build the app's engine, print size and SHA-256
//   node build.mjs --check              rebuild in memory; fail if the committed files differ
//   node build.mjs src/<spike>.js       the spikes: bundle one page into dist/<name>
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { build } from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const check = process.argv.includes('--check');
const spike = args[0];
const resources = join(here, '../../Casberi/Casberi/Resources');
const WASM = ['poseidon-hash-wasm/pkg-esm/poseidon_hash_wasm_bg.wasm', 'curve25519-scalarmult-wasm/pkg-esm/curve25519_scalarmult_wasm_bg.wasm'];

const r = await build({
  entryPoints: [join(here, spike ?? 'src/engine.js')],
  bundle: true, format: 'esm', platform: 'browser', target: 'safari17', minify: true, splitting: false,
  // The licences of everything bundled stay in the file (snarkjs is GPL-3.0,
  // Railgun's packages and ethers MIT); Resources/Licenses.md names them.
  legalComments: 'eof',
  conditions: ['browser'], mainFields: ['browser', 'module', 'main'],
  alias: {
    crypto: 'crypto-browserify', stream: 'stream-browserify', buffer: 'buffer', events: 'events', util: 'util', assert: 'assert',
    path: 'path-browserify', process: join(here, 'node_modules/process/browser.js'),
    // ONE axios: the SDK `require`s it (the browser CommonJS build) and
    // engine.js imports it to set its adapter; two copies would be two
    // defaults, and the SDK's would keep XMLHttpRequest.
    axios: join(here, 'node_modules/axios/dist/browser/axios.cjs'),
  },
  define: { global: 'globalThis', 'process.env.NODE_ENV': '"production"' },
  // inject.js: Buffer, and `process.nextTick` as a microtask — the browser
  // shim's `setTimeout(0)` is clamped to 4 ms by WebKit and the level store's
  // reads chain through it (7 minutes → 61 s on an iPhone, prd §1713).
  inject: [join(here, 'src/inject.js')],
  external: ['fs', 'fs/promises', 'os', 'worker_threads', 'readline', 'constants', 'http', 'https', 'zlib', 'url', 'net', 'tls', 'child_process', 'node:*', 'react-native-*'],
  logLevel: 'warning', write: false, metafile: true,
});
const bytes = r.outputFiles[0].contents;
const mb = (n) => (n / 1048576).toFixed(2);
const sha = (b) => createHash('sha256').update(b).digest('hex');

if (spike) {
  mkdirSync(join(here, 'dist'), { recursive: true });
  const out = join(here, 'dist', spike.split('/').pop());
  writeFileSync(out, bytes);
  console.log(`${out} ${mb(bytes.length)} MB (gzip ${mb(gzipSync(bytes).length)} MB)`);
} else {
  const outputs = [[join(resources, 'railgun-engine.js'), bytes], ...WASM.map((w) => [join(resources, w.split('/').pop()), readFileSync(join(here, 'node_modules/@railgun-community', w))])];
  if (check) {
    for (const [path, fresh] of outputs) {
      const committed = sha(readFileSync(path));
      if (committed !== sha(fresh)) { console.error(`${path} differs from a fresh build:\n  committed ${committed}\n  rebuilt   ${sha(fresh)}`); process.exit(1); }
    }
    console.log(`railgun-engine.js and its wasm reproduce: ${sha(bytes)}`);
    process.exit(0);
  }
  for (const [path, data] of outputs) writeFileSync(path, data);
  console.log(`railgun-engine.js  ${mb(bytes.length)} MB  (gzip ${mb(gzipSync(bytes).length)} MB)  sha256 ${sha(bytes)}`);
}
const by = {};
for (const [p, { bytesInOutput }] of Object.entries(Object.values(r.metafile.outputs)[0].inputs)) {
  const m = p.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/); const k = m ? m[1] : 'src'; by[k] = (by[k] ?? 0) + bytesInOutput;
}
for (const [k, v] of Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  ${mb(v).padStart(6)} MB  ${k}`);
