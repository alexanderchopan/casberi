// Builds the Privacy Pools engine the app's hidden web view runs (prd §1540):
// src/engine.js plus 0xBow's SDK, snarkjs and viem, into ONE script,
//   Casberi/Casberi/Resources/privacy-engine.js
// Every dependency is pinned exactly (package.json + package-lock.json), and
// esbuild's output is a function of its input, so the same tree builds the
// same bytes.
//   npm ci && node build.mjs           build, print size and SHA-256
//   node build.mjs --check             rebuild in memory; fail if the committed file differs
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { build } from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '../../Casberi/Casberi/Resources/privacy-engine.js');
const shims = join(here, 'src/shims.js');
const check = process.argv.includes('--check');

const result = await build({
  entryPoints: [join(here, 'src/engine.js')],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'safari17',
  minify: true,
  // The licences of everything bundled stay in the file (snarkjs and
  // circomlibjs are GPL-3.0, the SDK MIT); Resources/Licenses.md names them.
  legalComments: 'eof',
  conditions: ['browser'],
  mainFields: ['browser', 'module', 'main'],
  alias: {
    'fs/promises': shims,
    fs: shims,
    path: shims,
    crypto: shims,
    '@lifi/sdk': shims,
    pino: join(here, 'src/pino.js'),
    // The SDK takes ONE thing from circomlibjs, `buildPoseidon`. Its index
    // also pulls EdDSA, MiMC and contract generators (blake-hash, Node
    // streams, ethers); pointing at the Poseidon module alone leaves them out.
    circomlibjs: join(here, 'node_modules/circomlibjs/src/poseidon_wasm.js'),
  },
  define: { 'process.env.NODE_ENV': '"production"', global: 'globalThis' },
  inject: [],
  logLevel: 'warning',
  write: false,
  metafile: true,
});

const bytes = result.outputFiles[0].contents;
const sha = createHash('sha256').update(bytes).digest('hex');
const mb = (n) => (n / 1048576).toFixed(2);
if (check) {
  const committed = readFileSync(out);
  const committedSha = createHash('sha256').update(committed).digest('hex');
  if (committedSha !== sha) {
    console.error(`privacy-engine.js differs from a fresh build:\n  committed ${committedSha}\n  rebuilt   ${sha}`);
    process.exit(1);
  }
  console.log(`privacy-engine.js reproduces: ${sha}`);
} else {
  writeFileSync(out, bytes);
  console.log(`privacy-engine.js  ${mb(bytes.length)} MB  (gzip ${mb(gzipSync(bytes).length)} MB)  sha256 ${sha}`);
  const inputs = Object.entries(result.metafile.outputs)[0][1].inputs;
  const byPackage = {};
  for (const [path, { bytesInOutput }] of Object.entries(inputs)) {
    const m = path.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/);
    const key = m ? m[1] : 'src';
    byPackage[key] = (byPackage[key] ?? 0) + bytesInOutput;
  }
  for (const [name, size] of Object.entries(byPackage).sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  ${mb(size).padStart(6)} MB  ${name}`);
}
