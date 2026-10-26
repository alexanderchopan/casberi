// Proof-generation timing on THIS machine with the real ceremony artifacts (fetch-circuits.mjs),
// no funds needed. Inputs are synthetic but self-consistent (own keystore, state and ASP trees),
// mirroring packages/circuits/test/benchmark.test.ts in the v2 monorepo: the circuit is satisfied
// and the proof verifies against the ceremony vkey; it would not verify ON CHAIN only because
// the roots are ours, not the pool's. Proving cost is identical.
//   node prove-bench.mjs [runs=3] [circuit ...]
import { readFileSync } from 'node:fs';
import { buildPoseidon } from 'circomlibjs';
import { LeanIMT } from '@zk-kit/lean-imt';
import * as snarkjs from 'snarkjs';

const args = process.argv.slice(2);
const RUNS = Number(args[0] ?? 3);
const names = args.slice(1).length ? args.slice(1) : ['deposit', 'ragequit', 'transact_1x1', 'transact_1x2', 'transact_2x2'];
const STATE_D = 22, KEYSTORE_D = 18, ASP_D = 18; // Config E, circuits.json
const COMMITMENT_LEAF_TAG = 3791694183000795315792098099581407680958131641292811872617553086713867485913n;

const P = await buildPoseidon();
const H = (xs) => P.F.toObject(P(xs));
const rnd = () => { const b = crypto.getRandomValues(new Uint8Array(31)); return b.reduce((v, x) => (v << 8n) | BigInt(x), 0n); };
const tree = (leaves) => { const t = new LeanIMT((a, b) => H([a, b])); t.insertMany(leaves); return t; };
const pad = (s, d) => [...s, ...Array(d - s.length).fill(0n)];

function keystore() {
  const ownerAddress = rnd(), privateNullifyingKey = rnd(), privateRevocableKey = rnd();
  const leaf = H([ownerAddress, H([privateNullifyingKey]), H([0n, privateRevocableKey])]);
  const t = tree([leaf]); const p = t.generateProof(0);
  return { ownerAddress, privateNullifyingKey, privateRevocableKey, t, p };
}

function inputs(name) {
  if (name === 'deposit') {
    const ownerAddress = rnd(), noteSecret = rnd();
    return { tokenId: 1n, value: 1_000_000n, context: rnd(), noteAddressHash: H([ownerAddress, noteSecret]), depositSecret: rnd() };
  }
  if (name === 'ragequit') {
    const k = keystore();
    return {
      keystoreRoot: k.t.root, ownerAddress: k.ownerAddress, value: 1_000_000n, tokenId: 1n, label: rnd(),
      noteSecret: rnd(), metadata: 0n, privateNullifyingKey: k.privateNullifyingKey, privateRevocableKey: k.privateRevocableKey,
      keystoreLeafIndex: BigInt(k.p.index), keystoreSiblings: pad(k.p.siblings, KEYSTORE_D), keystoreTreeDepth: BigInt(k.t.depth),
    };
  }
  const [, n, m] = name.match(/transact_(\d)x(\d)/).map(Number);
  const k = keystore(); const label = rnd(); const base = 1_000_000n; const ts = BigInt(Math.floor(Date.now() / 1000));
  const secrets = [], commits = [];
  for (let i = 0; i < n; i++) {
    const s = rnd(); secrets.push(s);
    commits.push(H([H([H([k.ownerAddress, s]), 1n, base, 0n]), label]));
  }
  const st = tree(commits.map((c) => H([COMMITMENT_LEAF_TAG, c, ts])));
  const at = tree([H([label])]); const ap = at.generateProof(0);
  const total = base * BigInt(n); const per = total / BigInt(m);
  const outVals = Array.from({ length: m }, (_, j) => (j === m - 1 ? total - per * BigInt(m - 1) : per));
  const sp = commits.map((_, i) => st.generateProof(i));
  return {
    stateRoot: st.root, keystoreRoot: k.t.root, associationSetRoot: at.root, amountOut: 0n, tokenIdOut: 1n, context: rnd(),
    ownerAddress: k.ownerAddress, privateNullifyingKey: k.privateNullifyingKey, privateRevocableKey: k.privateRevocableKey,
    keystoreLeafIndex: BigInt(k.p.index), keystoreSiblings: pad(k.p.siblings, KEYSTORE_D), keystoreTreeDepth: BigInt(k.t.depth),
    noteSecret: secrets, value: Array(n).fill(base), label: Array(n).fill(label), tokenId: 1n,
    stateLeafIndex: sp.map((p) => BigInt(p.index)), stateSiblings: sp.map((p) => pad(p.siblings, STATE_D)), stateTreeDepth: sp.map((p) => BigInt(p.siblings.length)),
    associationSetLeafIndex: Array(n).fill(BigInt(ap.index)), associationSetSiblings: Array(n).fill(pad(ap.siblings, ASP_D)), associationSetTreeDepth: Array(n).fill(BigInt(ap.siblings.length)),
    timestamp: Array(n).fill(ts),
    outputNoteAddressHash: outVals.map(() => H([rnd(), rnd()])), outputValue: outVals, outputLabel: Array(m).fill(label),
  };
}

const dir = (n) => new URL(`./circuits-cache/${n}/`, import.meta.url).pathname;
const rows = [];
for (const name of names) {
  const wasm = `${dir(name)}${name}_js/${name}.wasm`, zkey = `${dir(name)}groth16_pkey.zkey`;
  const vkey = JSON.parse(readFileSync(`${dir(name)}groth16_vkey.json`, 'utf8'));
  const wt = [], pt = [], ft = []; let ok = true;
  for (let r = 0; r < RUNS; r++) {
    const inp = inputs(name);
    const wtns = { type: 'mem' };
    const t0 = performance.now();
    await snarkjs.wtns.calculate(inp, wasm, wtns);
    const t1 = performance.now();
    // SINGLE_THREAD=1 approximates a JS host with no worker threads.
    const { proof, publicSignals } = await snarkjs.groth16.prove(zkey, wtns, undefined, process.env.SINGLE_THREAD ? { singleThread: true } : undefined);
    const t2 = performance.now();
    ok &&= await snarkjs.groth16.verify(vkey, publicSignals, proof);
    wt.push(t1 - t0); pt.push(t2 - t1); ft.push(t2 - t0);
  }
  const med = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];
  rows.push({ circuit: name, runs: RUNS, witness_ms: Math.round(med(wt)), prove_ms: Math.round(med(pt)), total_ms: Math.round(med(ft)), first_total_ms: Math.round(ft[0]), verifies: ok });
  console.log(JSON.stringify(rows.at(-1)));
}
console.table(rows);
process.exit(0); // snarkjs leaves worker threads alive
