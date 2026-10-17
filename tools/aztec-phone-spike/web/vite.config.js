// Builds the page the iPhone app serves to its web view (../App/Web).
//
// The one trick: bb.js picks its prover in bb_backends/browser/index.js, which
// in a browser is always WebAssembly. That module is swapped for
// src/native-backend.js, which hands every prover command to the app's native
// iOS prover over a local POST instead.
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { defineConfig } from 'vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

const here = dirname(fileURLToPath(import.meta.url));
const bbDir = join(here, 'node_modules/@aztec/bb.js/dest/browser');
const swapped = join(bbDir, 'bb_backends/browser/index.js');
const shim = join(here, 'src/native-backend.js');

const nativeProver = {
  name: 'casberi-native-prover',
  enforce: 'pre',
  async resolveId(source, importer, options) {
    if (!importer || importer === shim) return null;
    const resolved = await this.resolve(source, importer, { ...options, skipSelf: true });
    return resolved && resolved.id === swapped ? shim : null;
  },
};

export default defineConfig({
  base: './',
  plugins: [nativeProver, nodePolyfills({ include: ['buffer', 'util', 'path', 'assert', 'events', 'stream', 'process', 'tty', 'os', 'crypto', 'string_decoder'], globals: { Buffer: true, process: true, global: true } })],
  resolve: { alias: { 'bbjs-internal': bbDir } },
  worker: { format: 'es' },
  build: {
    outDir: '../App/Web',
    emptyOutDir: true,
    target: 'safari17',
    chunkSizeWarningLimit: 100_000,
  },
});
