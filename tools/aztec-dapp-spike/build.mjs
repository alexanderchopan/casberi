// Bundles web/inject.js into one classic script (dist/inject.js) that a
// WKUserScript or a pasted <script> can run. Resolves @aztec-labs/* from
// tools/aztec-account's install (6.0.0) so nothing new is downloaded.
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
// The app-side bundle pulls aztec.js's logger, which reaches for Node builtins
// it never uses in a browser; each resolves to an empty module.
const nodeStubs = {
  name: 'node-stubs',
  setup(b) {
    b.onResolve({ filter: /^(node:)?buffer$/ }, () => ({ path: join(here, '../aztec-account/node_modules/buffer/index.js') }));
    b.onResolve({ filter: /^(node:)?(tty|util|os|fs|path|crypto|stream|events|worker_threads|child_process|net|url|process|module|perf_hooks|async_hooks|zlib|http|https)$/ }, a => ({ path: a.path, namespace: 'stub' }));
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: 'module.exports = {};', loader: 'js' }));
  },
};
for (const name of ['inject', 'relay', 'engine', 'dapp']) {
const result = await build({
  entryPoints: [join(here, `web/${name}.js`)],
  outfile: join(here, `dist/${name}.js`),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari17'],
  nodePaths: [join(here, '../aztec-account/node_modules')],
  metafile: true,
  plugins: [nodeStubs],
  banner: { js: '' },
  inject: name === 'dapp' ? [join(here, 'web/buffer-shim.js')] : [],
  define: { 'process.env.NODE_ENV': '"production"', global: 'globalThis' },
  logLevel: 'warning',
  minify: process.env.MINIFY === '1',
});
const bytes = Object.values(result.metafile.outputs)[0].bytes;
console.log(`dist/${name}.js ${bytes} bytes, ${Object.keys(result.metafile.inputs).length} inputs`);
}
