// Stands in for @aztec/bb.js's bb_backends/browser/index.js (see vite.config.js).
//
// The async prover — the one that makes every transaction's proof — runs in
// the app, not the web view: each msgpack command goes to POST /bb, where the
// app calls Aztec's native iOS library (`bbapi`) and returns its msgpack reply.
// The sync backend (hashing only) stays WebAssembly. `?prover=wasm` in the
// page URL restores bb.js's own WebAssembly worker, to compare.
import { BarretenbergWasmSyncBackend, BarretenbergWasmAsyncBackend } from 'bbjs-internal/bb_backends/wasm.js';
import { Barretenberg, BarretenbergSync } from 'bbjs-internal/barretenberg/index.js';
import { BackendType } from 'bbjs-internal/bb_backends/index.js';

export const proverKind = new URLSearchParams(globalThis.location?.search ?? '').get('prover') === 'wasm' ? 'wasm' : 'native';

// bb.js issues commands without waiting (ChonkLoad, then ChonkAccumulate) and
// relies on its worker running them in order. Separate POSTs can arrive out of
// order (measured: "No circuit loaded. Call ChonkLoad first"), so each call
// waits for the one before it — across every instance, since the native
// prover's state is one global.
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
    return new Barretenberg(new NativeBridgeBackend(), options);
  }
  switch (type) {
    case BackendType.Wasm:
    case BackendType.WasmWorker: {
      const useWorker = type === BackendType.WasmWorker;
      const wasm = await BarretenbergWasmAsyncBackend.new({
        threads: options.threads, wasmPath: options.wasmPath, logger, memory: options.memory, useWorker,
      });
      return new Barretenberg(wasm, options);
    }
    default:
      throw new Error(`Unknown backend type: ${type}`);
  }
}

export async function createSyncBackend(type, options, logger) {
  switch (type) {
    case BackendType.Wasm: {
      const wasm = await BarretenbergWasmSyncBackend.new(options.wasmPath, logger);
      return new BarretenbergSync(wasm);
    }
    default:
      throw new Error(`Backend ${type} not supported for BarretenbergSync`);
  }
}
