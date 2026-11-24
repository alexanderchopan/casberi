// Builds the Tacit engine the app's hidden web view runs: src/engine.js plus
// Tacit's own standalone wallet (vendor/, pinned by hash in upstream.json),
// into ONE script,
//   Casberi/Casberi/Resources/tacit-engine.js
// esbuild is pinned exactly and its output is a function of its input, so the
// same tree builds the same bytes.
//   npm ci && node build.mjs     build, print size and SHA-256
//   node build.mjs --check       rebuild in memory; fail if the committed file differs
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const check = process.argv.includes('--check');
const out = join(here, '../../Casberi/Casberi/Resources/tacit-engine.js');
const sha = (b) => createHash('sha256').update(b).digest('hex');

// The vendor file is Tacit's, byte for byte: a different file is not built.
const upstream = JSON.parse(readFileSync(join(here, 'upstream.json'), 'utf8'));
for (const [path, { sha256 }] of Object.entries(upstream.files)) {
  const got = sha(readFileSync(join(here, path)));
  if (got !== sha256) { console.error(`${path} is not the pinned file:\n  pinned ${sha256}\n  found  ${got}`); process.exit(1); }
}

const r = await build({
  entryPoints: [join(here, 'src/engine.js')],
  bundle: true, format: 'iife', platform: 'browser', target: 'safari17', minify: true,
  // Tacit's wallet is MIT; the snarkjs it carries for its prove worker is
  // GPL-3.0. Resources/Licenses.md names both.
  legalComments: 'eof',
  logLevel: 'warning', write: false,
});
const bytes = r.outputFiles[0].contents;

if (check) {
  const committed = sha(readFileSync(out));
  if (committed !== sha(bytes)) { console.error(`${out} differs from a fresh build:\n  committed ${committed}\n  rebuilt   ${sha(bytes)}`); process.exit(1); }
  console.log(`tacit-engine.js reproduces: ${sha(bytes)}`);
  process.exit(0);
}
writeFileSync(out, bytes);
console.log(`tacit-engine.js  ${(bytes.length / 1048576).toFixed(2)} MB  sha256 ${sha(bytes)}`);
