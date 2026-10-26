// Step 2: fresh Sepolia test keys into state/keys.json (gitignored, mode 600).
// Prints ADDRESSES and balances only, never a private key.
//   node keys.mjs          create if missing, then show balances
import { existsSync, mkdirSync, readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { createPublicClient, http, formatEther } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import { RPC, assertTestnet } from './config.mjs';

const DIR = new URL('./state/', import.meta.url);
const FILE = new URL('./state/keys.json', import.meta.url);

export function loadKeys() {
  if (!existsSync(FILE)) {
    mkdirSync(DIR, { recursive: true });
    const keys = {
      note: 'SEPOLIA TEST KEYS ONLY. Never fund with mainnet value. Never commit.',
      created: new Date().toISOString(),
      // A: funds the trial, deposits, sends privately. B: receives the private transfer.
      // C: plain address the relayed withdrawal pays out to.
      A: generatePrivateKey(),
      B: generatePrivateKey(),
      C: generatePrivateKey(),
    };
    writeFileSync(FILE, JSON.stringify(keys, null, 2));
    chmodSync(FILE, 0o600);
  }
  const raw = JSON.parse(readFileSync(FILE, 'utf8'));
  return { A: privateKeyToAccount(raw.A), B: privateKeyToAccount(raw.B), C: privateKeyToAccount(raw.C) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const keys = loadKeys();
  const c = createPublicClient({ chain: sepolia, transport: http(RPC) });
  assertTestnet(await c.getChainId());
  for (const [name, acct] of Object.entries(keys)) {
    const bal = await c.getBalance({ address: acct.address });
    console.log(`${name}  ${acct.address}  ${formatEther(bal)} SepoliaETH`);
  }
}
