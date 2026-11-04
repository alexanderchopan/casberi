// Builds Casberi's Aztec engine page into Casberi/AztecEngine (not committed;
// scripts/aztec-engine.sh builds it before every build that needs it).
//
// The one swap: bb.js picks its prover in bb_backends/browser/index.js, which in
// a browser is always WebAssembly. That module is replaced by
// src/native-backend.js, which in the app hands every prover command to Aztec's
// native iOS prover over a local POST (the phone spike's trick, on bb.js 6).
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { defineConfig } from 'vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

const here = dirname(fileURLToPath(import.meta.url));
const bbDir = join(here, 'node_modules/@aztec-foundation/bb.js/dest/browser');
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
  resolve: { alias: { '@bbjs': bbDir } },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['@aztec-foundation/bb.js', '@aztec-labs/noir-noirc_abi', '@aztec-labs/noir-acvm_js'] },
  build: { outDir: "../../Casberi/AztecEngine", emptyOutDir: true, target: 'safari17', chunkSizeWarningLimit: 100_000 },
});
