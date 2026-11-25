
import {
  bppH, bppRangeProve, bppRangeVerify,
  G, ZERO, SECP_N, modN, randomScalar,
} from './bulletproofs-plus.js';

const KERNEL_DOMAIN = new TextEncoder().encode('tacit-evm-cxfer-kernel-v1');
const TRANSFER_KERNEL_DOMAIN = new TextEncoder().encode('tacit-evm-transfer-kernel-v1');
const kernelDomainBytes = (domain) => {
  if (domain === 'transfer') return TRANSFER_KERNEL_DOMAIN;
  if (domain == null) return KERNEL_DOMAIN;
  throw new Error(`unknown kernel domain: ${domain}`);
};

export function makeConfidentialTransfer({ keccak256 }) {
  const H = bppH();

  const bytesToHex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  const hexToBytes = (h) => Uint8Array.from((String(h).replace(/^0x/, '').match(/../g) || []).map((x) => parseInt(x, 16)));
  const concat = (arr) => { const t = arr.reduce((s, x) => s + x.length, 0); const o = new Uint8Array(t); let p = 0; for (const x of arr) { o.set(x, p); p += x.length; } return o; };
  const ptBytes = (P) => P.toRawBytes(true);
  const beHex = (n) => '0x' + n.toString(16).padStart(64, '0');
  const b32 = (h) => { const b = hexToBytes(h); if (b.length > 32) throw new Error('over 32 bytes'); const o = new Uint8Array(32); o.set(b, 32 - b.length); return o; };
  const u16be = (n) => Uint8Array.of((Number(n) >> 8) & 0xff, Number(n) & 0xff);
  const mul = (P, s) => (s === 0n || P.equals(ZERO)) ? ZERO : P.multiply(modN(s));
  const sum = (pts) => pts.reduce((a, p) => a.add(p), ZERO);
  const commit = (v, r) => H.multiply(v).add(mul(G, r));
  const xy = (P) => { const a = P.toAffine(); return { cx: beHex(a.x), cy: beHex(a.y) }; };
  const pointOf = (cx, cy) => G.constructor.fromAffine({ x: BigInt(cx), y: BigInt(cy) });
  const pointFromHex = (h) => G.constructor.fromHex(String(h).replace(/^0x/, ''));
  const destLeaf = (assetId, cx, cy, owner) => '0x' + bytesToHex(keccak256(concat([b32(assetId), b32(cx), b32(cy), b32(owner)])));
  const BTC_NOTE_DOM = new TextEncoder().encode('tacit-btc-note-v1');
  const btcDestLeaf = (assetId, cx, cy, authKey) =>
    '0x' + bytesToHex(keccak256(concat([b32(assetId), b32(cx), b32(cy), b32(authKey), BTC_NOTE_DOM])));
  const claimId = (destChain, destCommitment, nullifier, assetId) =>
    '0x' + bytesToHex(keccak256(concat([u16be(destChain), b32(destCommitment), b32(nullifier), b32(assetId)])));

  function kernelChallenge(inC, outC, R, outLeaves = [], domain) {
    const parts = [kernelDomainBytes(domain)];
    for (const P of inC) parts.push(ptBytes(P));
    for (const P of outC) parts.push(ptBytes(P));
    for (const lf of outLeaves) parts.push(b32(lf));
    parts.push(ptBytes(R));
    return modN(BigInt('0x' + bytesToHex(keccak256(concat(parts)))));
  }

  function kernelSign({ inputs, outputs, fee = 0n, outLeaves = [], domain }) {
    const f = BigInt(fee);
    if (inputs.reduce((s, i) => s + i.value, 0n) !== outputs.reduce((s, o) => s + o.value, 0n) + f) {
      throw new Error('kernelSign: Σin ≠ Σout + fee');
    }
    const inC = inputs.map((i) => commit(i.value, i.blinding));
    const outC = outputs.map((o) => commit(o.value, o.blinding));
    const excess = modN(inputs.reduce((s, i) => s + i.blinding, 0n) - outputs.reduce((s, o) => s + o.blinding, 0n));
    const k = randomScalar();
    const R = mul(G, k);
    const e = kernelChallenge(inC, outC, R, outLeaves, domain);
    return { R, z: modN(k + e * excess), inC, outC };
  }

  function buildTransfer({ inputs, outputs, fee = 0n, assetId, domain }) {
    const f = BigInt(fee);
    const sumIn = inputs.reduce((s, i) => s + i.value, 0n);
    const sumOut = outputs.reduce((s, o) => s + o.value, 0n);
    if (sumIn !== sumOut + f) throw new Error('transfer not conserved: Σin ≠ Σout + fee');

    const { proof: rangeProof, commitments: outC } =
      bppRangeProve(outputs.map((o) => o.value), outputs.map((o) => o.blinding));
    const inC = inputs.map((i) => commit(i.value, i.blinding));
    const outLeaves = outC.map((P, j) => {
      const { cx, cy } = xy(P);
      return destLeaf(assetId, cx, cy, outputs[j].owner);
    });

    const excess = modN(
      inputs.reduce((s, i) => s + i.blinding, 0n) - outputs.reduce((s, o) => s + o.blinding, 0n)
    );
    const k = randomScalar();
    const R = mul(G, k);
    const e = kernelChallenge(inC, outC, R, outLeaves, domain);
    const z = modN(k + e * excess);

    return { inC, outC, rangeProof, kernel: { R, z }, fee: f, outLeaves, domain };
  }

  function verifyKernel({ inC, outC, fee = 0n, kernel, outLeaves = [], domain }) {
    let X = sum(inC).add(sum(outC).negate());
    if (BigInt(fee) !== 0n) X = X.add(mul(H, BigInt(fee)).negate());
    const e = kernelChallenge(inC, outC, kernel.R, outLeaves, domain);
    return mul(G, kernel.z).equals(kernel.R.add(mul(X, e)));
  }

  function verifyTransfer({ inC, outC, rangeProof, kernel, fee = 0n, outLeaves = [], domain }) {
    if (!bppRangeVerify(outC, rangeProof)) return false;
    const f = BigInt(fee);
    const X = sum(inC).add(sum(outC).negate()).add(mul(H, f).negate());
    const e = kernelChallenge(inC, outC, kernel.R, outLeaves, domain);
    const lhs = mul(G, kernel.z);
    const rhs = kernel.R.add(mul(X, e));
    return lhs.equals(rhs);
  }

  function buildBridgeBurn({ inputs, outputs, assetId, destChain, bindNullifier, fee = 0n }) {
    if (outputs.length !== 1) throw new Error('bridge-burn: exactly one destination per burn');
    const f = BigInt(fee);
    const sumIn = inputs.reduce((s, i) => s + i.value, 0n);
    const sumOut = outputs.reduce((s, o) => s + o.value, 0n);
    if (sumIn !== sumOut + f) throw new Error('bridge-burn not conserved: Σin ≠ Σout + fee');

    const { proof: rangeProof, commitments: outC } =
      bppRangeProve(outputs.map((o) => o.value), outputs.map((o) => o.blinding));
    const inC = inputs.map((i) => commit(i.value, i.blinding));

    const destCommitments = outC.map((C, j) => {
      const { cx, cy } = xy(C);
      return destChain === 1
        ? btcDestLeaf(assetId, cx, cy, outputs[j].owner)
        : destLeaf(assetId, cx, cy, outputs[j].owner);
    });

    const excess = modN(
      inputs.reduce((s, i) => s + i.blinding, 0n) - outputs.reduce((s, o) => s + o.blinding, 0n)
    );
    const k = randomScalar();
    const R = mul(G, k);
    const e = kernelChallenge(inC, outC, R, destCommitments);
    const z = modN(k + e * excess);

    const crossOuts = outC.map((C, j) => {
      const { cx, cy } = xy(C);
      const destCommitment = destCommitments[j];
      return {
        destChain,
        destCommitment,
        nullifier: bindNullifier,
        assetId,
        claimId: claimId(destChain, destCommitment, bindNullifier, assetId),
        cx, cy, owner: outputs[j].owner,
      };
    });

    return { inC, outC, rangeProof, kernel: { R, z }, crossOuts, fee: f };
  }

  function verifyBridgeBurn({ inC, outC, rangeProof, kernel, crossOuts, fee = 0n }) {
    const expectLeaves = crossOuts.map((c) => (Number(c.destChain) === 1
      ? btcDestLeaf(c.assetId, c.cx, c.cy, c.owner)
      : destLeaf(c.assetId, c.cx, c.cy, c.owner)));
    if (!verifyTransfer({ inC, outC, rangeProof, kernel, fee, outLeaves: expectLeaves })) return false;
    for (let j = 0; j < crossOuts.length; j++) {
      const c = crossOuts[j];
      if (expectLeaves[j].toLowerCase() !== String(c.destCommitment).toLowerCase()) return false;
      const expectClaim = claimId(c.destChain, c.destCommitment, c.nullifier, c.assetId);
      if (expectClaim.toLowerCase() !== String(c.claimId).toLowerCase()) return false;
    }
    return true;
  }

  function rangeProve(values, blindings) { return bppRangeProve(values, blindings); }

  return { H, commit, kernelSign, verifyKernel, rangeProve, buildTransfer, verifyTransfer, buildBridgeBurn, verifyBridgeBurn, claimId, destLeaf, btcDestLeaf, pointOf, pointFromHex, _ptBytes: ptBytes };
}
