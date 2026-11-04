// Builds Casberi's Aztec engine page (../dist/engine/) for a hidden web view.
import { defineConfig } from 'vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

export default defineConfig({
  base: './',
  plugins: [nodePolyfills({ include: ['buffer', 'util', 'path', 'assert', 'events', 'stream', 'process', 'tty', 'os', 'crypto', 'string_decoder'], globals: { Buffer: true, process: true, global: true } })],
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['@aztec-foundation/bb.js', '@aztec-labs/noir-noirc_abi', '@aztec-labs/noir-acvm_js'] },
  build: { outDir: '../dist/engine', emptyOutDir: true, target: 'safari17', chunkSizeWarningLimit: 100_000 },
});
