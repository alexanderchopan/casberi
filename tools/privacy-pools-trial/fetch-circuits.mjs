// Download the ceremony circuit artifacts the SDK pins (DEFAULT_CIRCUIT_MANIFEST, IPFS CIDs +
// sha256), through the SDK's own IpfsCircuitArtifacts so every byte is digest-checked, and lay
// them out for LocalCircuitArtifacts in circuits-cache/ (gitignored).
//   node fetch-circuits.mjs [circuit ...]     default: the five a phone would need first
//   KEYS=sepolia-dev node fetch-circuits.mjs  the SDK 1.0.0 dev keys the Sepolia pool actually verifies
//                                             (into circuits-cache-sepolia-dev/)
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { DEFAULT_CIRCUIT_MANIFEST, HTTPClient, IpfsCircuitArtifacts } from '@0xbow/privacy-pools-v2-sdk';

const names = process.argv.slice(2).length ? process.argv.slice(2) : ['deposit', 'ragequit', 'transact_1x1', 'transact_1x2', 'transact_2x2'];
// ipfs.io (the SDK default) and dweb.link answered 'switching to a service worker gateway' / 429 on
// 2026-10-26 for some CIDs; the SDK's sha256 check rejects that page and moves to the next gateway.
const gateways = ['https://gateway.pinata.cloud/ipfs', 'https://ipfs.io/ipfs', 'https://dweb.link/ipfs'];
const DEV = process.env.KEYS === 'sepolia-dev';
const manifest = DEV ? (({ _note, ...m }) => m)(JSON.parse(readFileSync(new URL('./manifest-sepolia-dev.json', import.meta.url)))) : DEFAULT_CIRCUIT_MANIFEST;
const art = new IpfsCircuitArtifacts({
  ipfsGatewayUrls: gateways,
  circuitManifest: manifest,
  httpClient: new HTTPClient({ timeout: 300_000, retryAttempts: 2, headers: {} }),
});
const root = new URL(DEV ? './circuits-cache-sepolia-dev/' : './circuits-cache/', import.meta.url).pathname;
const mb = (n) => (n / 1048576).toFixed(1);
for (const name of names) {
  const dir = `${root}${name}`;
  const files = { wasm: `${dir}/${name}_js/${name}.wasm`, zkey: `${dir}/groth16_pkey.zkey`, vkey: `${dir}/groth16_vkey.json` };
  if (Object.values(files).every(existsSync)) {
    console.log(`${name}: cached  wasm ${mb(statSync(files.wasm).size)} MB  zkey ${mb(statSync(files.zkey).size)} MB`);
    continue;
  }
  mkdirSync(`${dir}/${name}_js`, { recursive: true });
  const t0 = performance.now();
  const wasm = await art.getWasm(name);
  const t1 = performance.now();
  const zkey = await art.getProvingKey(name);
  const t2 = performance.now();
  const vkey = await art.getVerificationKey(name);
  writeFileSync(files.wasm, wasm); writeFileSync(files.zkey, zkey); writeFileSync(files.vkey, vkey);
  console.log(`${name}: wasm ${mb(wasm.length)} MB in ${((t1 - t0) / 1000).toFixed(1)}s  zkey ${mb(zkey.length)} MB in ${((t2 - t1) / 1000).toFixed(1)}s  vkey ${(vkey.length / 1024).toFixed(1)} KB  (sha256 verified by the SDK)`);
}
