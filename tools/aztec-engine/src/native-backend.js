// Stands in for @aztec-foundation/bb.js's bb_backends/browser/index.js (see
// vite.config.js). In Casberi's app the async prover — the one that makes every
// transaction's proof — runs NATIVELY: each msgpack command goes to POST /bb on
// the engine's own origin, where the app hands it to Aztec's iOS library
// (`bbapi`, libbb-external.a) and returns the reply. The sync backend (hashing)
// stays WebAssembly. Outside the app (no `webkit`) or with `?prover=wasm`,
// bb.js's own WebAssembly prover runs, to compare.
import { BackendType } from '@bbjs/bb_backends/index.js';
import { BarretenbergWasmAsyncBackend, BarretenbergWasmSyncBackend } from '@bbjs/bb_backends/wasm.js';

const wantWasm = new URLSearchParams(globalThis.location?.search ?? '').get('prover') === 'wasm';
export const proverKind = !wantWasm && globalThis.webkit?.messageHandlers ? 'native' : 'wasm';

// bb.js issues commands without waiting for each (ChonkLoad, then
// ChonkAccumulate…) and relies on one worker running them in order; separate
// POSTs can arrive out of order, so every call waits for the one before it.
let tail = Promise.resolve();
class NativeBridgeBackend {
  call(input) {
    const run = tail.then(async () => {
      const response = await fetch('/bb', { method: 'POST', body: input, headers: { 'content-type': 'application/octet-stream' } });
      if (!response.ok) throw new Error(`native prover ${response.status}: ${await response.text()}`);
      return new Uint8Array(await response.arrayBuffer());
    });
    tail = run.catch(() => {});
    return run;
  }
  async destroy() {}
}

export async function createAsyncBackend(type, options, logger) {
  if (proverKind === 'native' && (type === BackendType.Wasm || type === BackendType.WasmWorker)) {
    logger('Using the native iOS prover');
    return new NativeBridgeBackend();
  }
  switch (type) {
    case BackendType.Wasm:
    case BackendType.WasmWorker: {
      const useWorker = type === BackendType.WasmWorker;
      logger(`Using WASM backend (worker: ${useWorker})`);
      return await BarretenbergWasmAsyncBackend.new({
        threads: options.threads, wasmPath: options.wasmPath, logger, memory: options.memory, useWorker,
      });
    }
    default:
      throw new Error(`Unknown backend type: ${type}`);
  }
}

export async function createSyncBackend(type, options, logger) {
  switch (type) {
    case BackendType.Wasm:
      logger('Using WASM backend');
      return await BarretenbergWasmSyncBackend.new(options.wasmPath, logger);
    default:
      throw new Error(`Backend ${type} not supported for BarretenbergSync`);
  }
}
