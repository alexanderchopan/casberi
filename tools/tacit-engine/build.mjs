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

// Tacit's prover imports its wasm-bindgen glue at run time from a URL beside
// itself (`import(GLUE_URL)`). The one script has nothing beside it, so the
// import is made static here and the glue bundled in; the vendored file on
// disk stays Tacit's, byte for byte (its hash is checked above).
const glueStatic = {
  name: 'tacit-glue-static',
  setup(b) {
    b.onLoad({ filter: /btc-pool-halo2-prover\.js$/ }, async (args) => {
      const src = readFileSync(args.path, 'utf8');
      const out = src.replace('await import(GLUE_URL)', "await import('./btc-pool/btc_pool_halo2.js')");
      if (out === src) throw new Error('btc-pool-halo2-prover.js no longer imports its glue as expected');
      return { contents: out, loader: 'js' };
    });
  },
};

const r = await build({
  plugins: [glueStatic],
  entryPoints: [join(here, 'src/engine.js')],
  bundle: true, format: 'iife', platform: 'browser', target: 'safari17', minify: true,
  // Tacit's wallet is MIT; the snarkjs it carries for its prove worker is
  // GPL-3.0. Resources/Licenses.md names both.
  legalComments: 'eof',
  // Tacit's pool library makes its worker URLs from `import.meta.url`,
  // which a single script has none of. Pointing it at the engine's own
  // scheme makes each URL valid; the page serves no worker there and its
  // policy allows none, so the library's workers fail to start and it
  // reads in the page, its own fallback.
  define: { 'import.meta.url': '"casberi-tacit://engine/tacit-engine.js"' },
  logLevel: 'error', write: false,
  loader: { '.json': 'json' },
});
const bytes = r.outputFiles[0].contents;

// Tacit's prover reads three files at run time: its wasm, its parameters and
// its verifying key (whose hash the prover checks against Tacit's pin before
// it proves). The app serves them to the page over its own scheme.
const prover = [
  ['vendor/dapp/btc-pool/btc_pool_halo2_bg.wasm', 'tacit-halo2.wasm'],
  ['vendor/dapp/btc-pool/params-k13.bin', 'tacit-halo2-params.bin'],
  ['vendor/dapp/btc-pool/vk.bin', 'tacit-halo2-vk.bin'],
];
const res = join(here, '../../Casberi/Casberi/Resources');
for (const [from, to] of prover) {
  const want = readFileSync(join(here, from));
  if (check) {
    let have = null;
    try { have = readFileSync(join(res, to)); } catch {}
    if (!have || sha(have) !== sha(want)) { console.error(`${to} is not ${from}`); process.exit(1); }
  } else writeFileSync(join(res, to), want);
}

if (check) {
  const committed = sha(readFileSync(out));
  if (committed !== sha(bytes)) { console.error(`${out} differs from a fresh build:\n  committed ${committed}\n  rebuilt   ${sha(bytes)}`); process.exit(1); }
  console.log(`tacit-engine.js reproduces: ${sha(bytes)}`);
  process.exit(0);
}
writeFileSync(out, bytes);
console.log(`tacit-engine.js  ${(bytes.length / 1048576).toFixed(2)} MB  sha256 ${sha(bytes)}`);
