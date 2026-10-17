// Aztec on this iPhone — the spike's page (testnet only).
//
// The question: can a phone, alone, run a private Aztec account? Aztec's own
// PXE runs here in the web view; every proof it makes is computed by Aztec's
// native iOS prover in the app (see native-backend.js); the account's only key
// is this phone's Secure Enclave P-256 key, signed in the app (POST /sign).
// Each step is timed, and the app's memory is read once a second.
//
// It follows tools/aztec-signer/signer.mjs, which measured the same account on
// a computer (prd §1276), with the phone now doing every part.
import { NO_FROM } from '@aztec/aztec.js/account';
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee/testing';
import { Fr } from '@aztec/aztec.js/fields';
import { AccountManager } from '@aztec/aztec.js/wallet';
import { EcdsaRSSHAccountContract } from '@aztec/accounts/ecdsa';
import { SponsoredFPCContract } from '@aztec/noir-contracts.js/SponsoredFPC';
import { TokenContract } from '@aztec/noir-contracts.js/Token';
import { AuthWitness } from '@aztec/stdlib/auth-witness';
import { AztecAddress } from '@aztec/stdlib/aztec-address';
import { getContractInstanceFromInstantiationParams } from '@aztec/stdlib/contract';
import { EmbeddedWallet } from '@aztec/wallets/embedded';

import { Barretenberg, BarretenbergSync } from '@aztec/bb.js';

import { proverKind } from './native-backend.js';

const NODE_URL = 'https://v5.testnet.rpc.aztec-labs.com';
const STATE_KEY = 'aztec-spike-state';

// ---- the page ---------------------------------------------------------------

const $ = (id) => document.getElementById(id);
const logBox = $('log');
function log(...parts) {
  const line = parts.map((p) => (typeof p === 'string' ? p : p instanceof Error ? `${p.message}\n${p.stack ?? ''}` : JSON.stringify(p))).join(' ');
  logBox.textContent = `${new Date().toISOString().slice(11, 19)} ${line}\n` + logBox.textContent.slice(0, 20_000);
  fetch('/log', { method: 'POST', body: line }).catch(() => {});
}
for (const level of ['log', 'info', 'warn', 'error']) {
  const original = console[level].bind(console);
  console[level] = (...args) => { original(...args); log(`[${level}]`, ...args.map(String)); };
}
window.addEventListener('error', (e) => log('[uncaught]', e.message));
window.addEventListener('unhandledrejection', (e) => log('[unhandled]', e.reason?.message ?? String(e.reason)));

const inSimulator = new URLSearchParams(location.search).get('device') === 'simulator';
if (inSimulator) document.querySelector('h1').textContent = 'Aztec on iOS';
$('sub').textContent = `Testnet v5 · prover: ${proverKind === 'native' ? 'native iOS' : 'WebAssembly'}${inSimulator ? ' · Simulator' : ''}`;

const mb = (bytes) => `${Math.round(bytes / 1048576)} MB`;
let peak = 0;
setInterval(async () => {
  try {
    const m = await (await fetch('/mem')).json();
    peak = Math.max(peak, m.footprint);
    $('mem').textContent = `app ${mb(m.footprint)} · peak ${mb(peak)}` + (m.available > 0 ? ` · left ${mb(m.available)}` : '');
  } catch {}
}, 1000);

const loadState = () => JSON.parse(localStorage.getItem(STATE_KEY) ?? 'null');
const saveState = (s) => localStorage.setItem(STATE_KEY, JSON.stringify(s));

// ---- the account: Aztec's P-256 account, signed by the Secure Enclave --------

async function enclaveSign(messageHash) {
  const response = await fetch('/sign', { method: 'POST', body: messageHash.toBuffer() });
  if (!response.ok) throw new Error(`the Secure Enclave did not sign: ${await response.text()}`);
  const sig = new Uint8Array(await response.arrayBuffer());
  if (sig.length !== 64) throw new Error('the Secure Enclave returned a malformed signature');
  return sig;
}

class EnclaveAccountContract extends EcdsaRSSHAccountContract {
  constructor(publicKeyHex) { super(Buffer.from(publicKeyHex, 'hex')); }
  getAuthWitnessProvider() {
    return { async createAuthWit(messageHash) { return new AuthWitness(messageHash, [...(await enclaveSign(messageHash))]); } };
  }
}

let session = null;

async function openWallet() {
  const publicKey = await (await fetch('/key')).text();
  let state = loadState();
  if (state?.publicKey !== publicKey) {
    state = { publicKey, secret: Fr.random().toString(), salt: Fr.random().toString() };
    saveState(state);
  }
  const wallet = await EmbeddedWallet.create(NODE_URL, { pxe: { proverEnabled: true } });
  const contract = new EnclaveAccountContract(publicKey);
  const manager = await AccountManager.create(wallet, Fr.fromString(state.secret), contract, { salt: Fr.fromString(state.salt) });
  const address = manager.getInstance().address;
  if (!(await wallet.getContractMetadata(address)).instance) {
    await wallet.registerContract(manager.getInstance(), await contract.getContractArtifact(), manager.getSecretKey());
  }
  await wallet.walletDB.storeAccount(address, {
    type: 'ecdsasecp256r1', secretKey: manager.getSecretKey(), salt: Fr.fromString(state.salt),
    alias: 'phone', signingKey: Buffer.from(publicKey, 'hex'),
  });
  const account = await manager.getAccount();
  const original = wallet.getAccountFromAddress.bind(wallet);
  wallet.getAccountFromAddress = async (a) => (a.equals(address) ? account : original(a));
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
  session = { wallet, manager, address, state, fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) } };
  if (state.token) {
    const instance = await wallet.getContractMetadata(AztecAddress.fromStringUnsafe(state.token));
    if (!instance.instance) {
      const { node } = wallet;
      const remote = await (node ?? wallet.aztecNode)?.getContract?.(AztecAddress.fromStringUnsafe(state.token));
      if (remote) await wallet.registerContract(remote, TokenContract.artifact);
    }
  }
  return `account ${address.toString().slice(0, 10)}…`;
}

async function token() {
  if (!session.state.token) throw new Error('deploy the token first');
  return TokenContract.at(AztecAddress.fromStringUnsafe(session.state.token), session.wallet);
}

// The bridge, before any proof: one Poseidon2 hash through the prover the
// page uses (native unless ?prover=wasm) must equal bb.js's WebAssembly one.
async function checkProver() {
  const inputs = [new Uint8Array(32).fill(0).map((_, i) => (i === 31 ? 1 : 0)), new Uint8Array(32).fill(0).map((_, i) => (i === 31 ? 2 : 0))];
  const hex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  const bb = await Barretenberg.new({ skipSrsInit: true });
  const viaProver = hex((await bb.poseidon2Hash({ inputs })).hash);
  await bb.destroy();
  const viaWasm = hex((await BarretenbergSync.initSingleton()).poseidon2Hash({ inputs }).hash);
  if (viaProver !== viaWasm) throw new Error(`the ${proverKind} prover disagrees: ${viaProver} ≠ ${viaWasm}`);
  return `${proverKind} = wasm · ${viaProver.slice(0, 10)}…`;
}

const steps = [
  { name: 'Check the prover', run: checkProver },
  { name: 'Open the wallet', run: openWallet },
  {
    name: 'Create the account',
    run: async () => {
      const { wallet, manager, address, fee } = session;
      const meta = await wallet.getContractMetadata(address);
      if (String(meta.initializationStatus) === 'INITIALIZED') return 'already created';
      const { receipt } = await (await manager.getDeployMethod()).send({ from: NO_FROM, fee });
      session.state.address = address.toString(); saveState(session.state);
      return `block ${receipt.blockNumber}`;
    },
  },
  {
    name: 'Deploy a token',
    run: async () => {
      const { wallet, address, fee } = session;
      const { contract, receipt } = await TokenContract.deploy(wallet, address, 'Casberi', 'CSB', 18).send({ from: address, fee });
      session.state.token = contract.address.toString(); saveState(session.state);
      return `block ${receipt.blockNumber}`;
    },
  },
  {
    name: 'Mint 100',
    run: async () => {
      const { receipt } = await (await token()).methods.mint_to_public(session.address, 100n).send({ from: session.address, fee: session.fee });
      return `block ${receipt.blockNumber}`;
    },
  },
  {
    name: 'Move 25 into private',
    run: async () => {
      const { receipt } = await (await token()).methods.transfer_to_private(session.address, 25n).send({ from: session.address, fee: session.fee });
      return `block ${receipt.blockNumber}`;
    },
  },
  {
    name: 'Send 5 privately',
    run: async () => {
      const { receipt } = await (await token()).methods.transfer(session.address, 5n).send({ from: session.address, fee: session.fee });
      return `block ${receipt.blockNumber}`;
    },
  },
  {
    name: 'Read the balances',
    run: async () => {
      const t = await token();
      const { result: priv } = await t.methods.balance_of_private(session.address).simulate({ from: session.address });
      const { result: pub } = await t.methods.balance_of_public(session.address).simulate({ from: session.address });
      return `private ${priv} · public ${pub}`;
    },
  },
];

// ---- running them -----------------------------------------------------------

const results = [];
let busy = false;

async function runStep(i, button) {
  const step = steps[i];
  const timing = button.querySelector('.t');
  if (i > 1 && !session) throw new Error('open the wallet first');
  timing.className = 't'; timing.textContent = '…';
  const peakBefore = peak; peak = 0;
  const start = performance.now();
  try {
    const note = await step.run();
    const seconds = (performance.now() - start) / 1000;
    timing.className = 't ok'; timing.textContent = `${seconds.toFixed(1)} s`;
    results.push({ step: step.name, seconds: +seconds.toFixed(2), note, peakMB: Math.round(peak / 1048576) });
    log(`✓ ${step.name} — ${seconds.toFixed(1)} s — ${note}`);
  } catch (e) {
    timing.className = 't bad'; timing.textContent = 'failed';
    log(`✗ ${step.name}`, e);
    throw e;
  } finally {
    peak = Math.max(peak, peakBefore);
    fetch('/result', { method: 'POST', body: JSON.stringify({ prover: proverKind, results }) }).catch(() => {});
  }
}

const list = $('steps');
const buttons = steps.map((step, i) => {
  const button = document.createElement('button');
  button.innerHTML = `<span>${step.name}</span><span class="t"></span>`;
  button.onclick = async () => {
    if (busy) return; busy = true;
    try { await runStep(i, button); } catch {} finally { busy = false; }
  };
  list.appendChild(button);
  return button;
});

const all = document.createElement('button');
all.innerHTML = '<span>Run every step</span><span class="t"></span>';
all.onclick = async () => {
  if (busy) return; busy = true;
  const start = performance.now();
  try {
    for (let i = 0; i < steps.length; i++) await runStep(i, buttons[i]);
    all.querySelector('.t').textContent = `${((performance.now() - start) / 1000).toFixed(1)} s`;
  } catch {} finally { busy = false; }
};
list.appendChild(all);

const autorun = new URLSearchParams(location.search).get('autorun');
if (autorun === 'all') all.click();
else if (autorun === 'open') (async () => { await buttons[0].onclick(); await buttons[1].onclick(); })();
log(`ready · prover ${proverKind} · ${navigator.userAgent}`);
