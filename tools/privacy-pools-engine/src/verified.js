// The private balance, checked against Ethereum itself (prd §1569a), through
// Kohaku's verified provider (`@kohaku-eth/provider`, the Ethereum
// Foundation's) and Colibri, the light client it wraps.
//
// The SDK reads its logs from one node, over Tor. A node can omit a log or
// invent one; Tor does nothing about that. So each tree the balance stands
// on is rebuilt from those logs, its root computed here, and the contract
// asked whether it knows that root, through a provider that checks the
// answer against the beacon chain's signatures and refuses anything it
// cannot prove (`Strategy.VerifiedOnly`: Kohaku's adapter passes no
// strategy, and Colibri's default answers unverified when a proof fails).
// One proven call vouches for every leaf. Then every note the balance
// counts must be a leaf of the proven state tree, checked here: nothing
// asked names a note, so the check tells no one which notes are yours.
//
// What it does not prove: that a note is unspent. Spends are not leaves,
// and asking the chain about one note's nullifier would name it.
import { colibri } from '@kohaku-eth/provider/colibri';
import Colibri, { Strategy, set_wasm_url } from '@corpus-core/colibri-stateless';
import { MerkleService, ViemRPCInteractor, createEvmKeystoreInteractor, createEvmPoolVaultInteractor } from '@0xbow/privacy-pools-v2-sdk';
import { decodeFunctionResult, encodeFunctionData } from 'viem';

// Colibri's hosts, pinned to the ones `NetworkReach` declares for the
// engine: its prover, its consensus API and two checkpoint services each.
const CHAINS = {
  1: {
    prover: ['https://mainnet.colibri-proof.tech', 'https://mainnet1.colibri-proof.tech'],
    beacon_apis: ['https://mainnet.colibri-proof.tech/consensus'],
    checkpointz: ['https://sync-mainnet.beaconcha.in', 'https://mainnet.checkpoint.sigp.io'],
  },
  11155111: {
    prover: ['https://sepolia.colibri-proof.tech', 'https://sepolia1.colibri-proof.tech'],
    beacon_apis: ['https://sepolia.colibri-proof.tech/consensus'],
    checkpointz: ['https://checkpoint-sync.sepolia.ethpandaops.io', 'https://beaconstate-sepolia.chainsafe.io'],
  },
};

const IS_KNOWN_ROOT = [{ type: 'function', name: 'isKnownRoot', stateMutability: 'view',
  inputs: [{ name: '_root', type: 'uint256' }], outputs: [{ name: 'isKnown_', type: 'bool' }] }];

const providers = new Map();
// The two tree readers per chain, kept for the page's life: each `open`
// makes a new account, and a reader made with it would scan from the
// deployment block every pass.
const readers = new Map();
let started = null;

// The WebAssembly comes from the app, like the circuits; its checkpoint
// lives in this page and dies with it. A start that failed is tried again.
function start() {
  started ??= (async () => {
    set_wasm_url('casberi-engine://engine/colibri.wasm');
    const kept = new Map();
    await Colibri.register_storage({ get: (k) => kept.get(k) ?? null, set: (k, v) => kept.set(k, v), del: (k) => kept.delete(k) });
  })().catch((error) => { started = null; throw error; });
  return started;
}

// A proof that never comes must not hold the engine: every flow waits on it.
const PROOF_TIMEOUT_MS = 45_000;
function bounded(promise, what) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(Object.assign(new Error(`${what}: no proof in ${PROOF_TIMEOUT_MS / 1000} s`), { name: 'CheckTimedOut' })), PROOF_TIMEOUT_MS);
  })]).finally(() => clearTimeout(timer));
}

async function provider(network, say) {
  await start();
  const id = Number(network.chainId);
  if (!providers.has(id)) {
    if (!CHAINS[id]) throw Object.assign(new Error(`no verified provider for chain ${id}`), { name: 'NotServed' });
    providers.set(id, await colibri({ chainId: id, rpcs: [network.rpcUrl], ...CHAINS[id],
      proofStrategy: Strategy.VerifiedOnly, warningHandler: async (req, message) => say(`${req.method}: ${message}`) }));
  }
  return providers.get(id);
}

async function knows(p, contract, root) {
  const data = await bounded(p.request({ method: 'eth_call',
    params: [{ to: contract, data: encodeFunctionData({ abi: IS_KNOWN_ROOT, functionName: 'isKnownRoot', args: [BigInt(root)] }) }, 'latest'] }), 'isKnownRoot');
  return decodeFunctionResult({ abi: IS_KNOWN_ROOT, functionName: 'isKnownRoot', data });
}

const leafKey = (h) => BigInt(h).toString(16);

// One pass over both trees; a later pass fetches only the logs since the last.
// It needs no open account, only the network and the commitments `discover`
// returned, so the app runs it outside the engine's one-flow queue: a check
// that takes a minute never holds a Move.
export async function checkTrees(n, { notes, hash, say, now }) {
  const key = `${n.chainId}:${n.pool}:${n.keystore}`;
  if (!readers.has(key)) {
    const rpcInteractor = ViemRPCInteractor.create({ rpcUrl: n.rpcUrl });
    readers.set(key, {
      state: createEvmPoolVaultInteractor({ rpcInteractor, contractAddress: n.pool, deploymentBlock: BigInt(n.fromBlock) }),
      keystore: createEvmKeystoreInteractor({ rpcInteractor, contractAddress: n.keystore, deploymentBlock: BigInt(n.fromBlock) }),
    });
  }
  const tree = readers.get(key);
  const merkle = new MerkleService({ hashService: hash });
  const p = await bounded(provider(n, say), 'light client');
  const trees = {};
  let stateLeaves = [];
  for (const [name, read, contract] of [['state', 'getStateLeaves', n.pool], ['keystore', 'getKeystoreLeaves', n.keystore]]) {
    const t = now();
    const leaves = await tree[name][read]();
    const root = await merkle.computeRoot(leaves);
    const r = now();
    const known = await knows(p, contract, root);
    trees[name] = { leaves: leaves.length, known, readMs: Math.round(r - t), verifyMs: Math.round(now() - r) };
    if (name === 'state') stateLeaves = leaves;
  }
  const inTree = new Set(stateLeaves.map(leafKey));
  const missing = notes.filter((c) => !inTree.has(leafKey(c))).length;
  return { checked: trees.state.known && trees.keystore.known && missing === 0, trees, notes: notes.length, notesMissing: missing };
}
