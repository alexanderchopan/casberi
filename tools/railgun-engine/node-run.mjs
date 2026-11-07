// SPIKE: the Node run of src/core.js. A fresh Sepolia-only phrase lives in
// state/ (gitignored, mode 600); its EOA and private address are printed,
// never the phrase.
//   node node-run.mjs
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import memdown from 'memdown';
import { Wallet } from 'ethers';
import { spike, ArtifactStore } from './src/core.js';

const here = dirname(fileURLToPath(import.meta.url));
const state = join(here, 'state');
mkdirSync(state, { recursive: true });
const keysPath = join(state, 'keys.json');
if (!existsSync(keysPath)) {
  writeFileSync(keysPath, JSON.stringify({ note: 'SEPOLIA TEST ONLY. Never fund with mainnet value. Never commit.',
    mnemonic: Wallet.createRandom().mnemonic.phrase, encryptionKey: randomBytes(32).toString('hex') }, null, 1), { mode: 0o600 });
}
const { mnemonic, encryptionKey } = JSON.parse(readFileSync(keysPath, 'utf8'));

const dir = join(here, '.artifacts');
const store = new ArtifactStore(
  async (p) => (existsSync(join(dir, p)) ? readFileSync(join(dir, p)) : null),
  async (d, p, item) => { mkdirSync(join(dir, d), { recursive: true }); writeFileSync(join(dir, p), item); },
  async (p) => existsSync(join(dir, p)),
);

const log = (step, f) => console.log(JSON.stringify({ step, ...f }, (k, v) => (k === 'transaction' ? undefined : typeof v === 'bigint' ? String(v) : v)));
await spike({ db: memdown(), artifactStore: store, mnemonic, encryptionKey, log, network: process.argv[2] ?? 'Ethereum_Sepolia', syncCapMs: Number(process.argv[3] ?? 240000), startBlock: process.argv[4] ? Number(process.argv[4]) : undefined, txidStartTree: process.argv[5] ? Number(process.argv[5]) : undefined });
process.exit(0);
