// Inputs that satisfy a Privacy Pools v2 circuit without a pool: the
// person's own keystore, state and association trees, built here
// (packages/circuits/test/benchmark.test.ts in 0xBow's monorepo; the trial's
// prove-bench.mjs). A proof over them costs what a real one costs and
// verifies against the circuit's key, but names roots no pool holds.
// `H` is Poseidon over bigints.
import { LeanIMT } from '@zk-kit/lean-imt';

const STATE_D = 22, KEYSTORE_D = 18, ASP_D = 18;
const COMMITMENT_LEAF_TAG = 3791694183000795315792098099581407680958131641292811872617553086713867485913n;

export function syntheticInputs(name, H) {
  const rnd = () => globalThis.crypto.getRandomValues(new Uint8Array(31)).reduce((v, x) => (v << 8n) | BigInt(x), 0n);
  const tree = (leaves) => { const t = new LeanIMT((a, b) => H([a, b])); t.insertMany(leaves); return t; };
  const pad = (s, d) => [...s, ...Array(d - s.length).fill(0n)];
  const keystore = () => {
    const ownerAddress = rnd(), privateNullifyingKey = rnd(), privateRevocableKey = rnd();
    const t = tree([H([ownerAddress, H([privateNullifyingKey]), H([0n, privateRevocableKey])])]);
    return { ownerAddress, privateNullifyingKey, privateRevocableKey, t, p: t.generateProof(0) };
  };
  if (name === 'deposit') {
    return { tokenId: 1n, value: 1_000_000n, context: rnd(), noteAddressHash: H([rnd(), rnd()]), depositSecret: rnd() };
  }
  if (name === 'ragequit') {
    const k = keystore();
    return {
      keystoreRoot: k.t.root, ownerAddress: k.ownerAddress, value: 1_000_000n, tokenId: 1n, label: rnd(), noteSecret: rnd(), metadata: 0n,
      privateNullifyingKey: k.privateNullifyingKey, privateRevocableKey: k.privateRevocableKey,
      keystoreLeafIndex: BigInt(k.p.index), keystoreSiblings: pad(k.p.siblings, KEYSTORE_D), keystoreTreeDepth: BigInt(k.t.depth),
    };
  }
  const [, n, m] = name.match(/transact_(\d)x(\d)/).map(Number);
  const k = keystore(); const label = rnd(); const base = 1_000_000n; const ts = BigInt(Math.floor(Date.now() / 1000));
  const secrets = [], commits = [];
  for (let i = 0; i < n; i++) { const s = rnd(); secrets.push(s); commits.push(H([H([H([k.ownerAddress, s]), 1n, base, 0n]), label])); }
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
