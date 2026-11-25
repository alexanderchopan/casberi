
const U64_MAX = (1n << 64n) - 1n;
const ZERO32 = '0x' + '00'.repeat(32);
const bmod = (a, m) => ((a % m) + m) % m;
const SWAP_TAG = 'tacit-swap-intent-v1';

export function clearingPriceBperA(sol) {
  return { priceNum: BigInt(sol.P_clear_den), priceDen: BigInt(sol.P_clear_num) };
}

const _U64_MAX = (1n << 64n) - 1n;
const _FEE_BPS_MAX = 1000n;
const _asU64 = (x, n) => { const v = BigInt(x); if (v < 0n || v > _U64_MAX) throw new Error(`${n} must fit in u64`); return v; };
function _solveAToB(X, Y, R_A, R_B, gNum, gDen) {
  let lo = 1n, hi = X, best = 1n, iter = 0;
  while (iter < 64 && lo <= hi) {
    const mid = lo + (hi - lo) / 2n;
    const deltaB = (R_B * gNum * mid) / (R_A * gDen + gNum * mid);
    const denom = Y + deltaB;
    const deltaAImplied = denom === 0n ? X : X - (Y * X) / denom;
    if (deltaAImplied === mid) return { P_clear_num: X, P_clear_den: Y + deltaB };
    if (deltaAImplied < mid) hi = mid - 1n; else { best = mid; lo = mid + 1n; }
    iter++;
  }
  const fdb = (R_B * gNum * best) / (R_A * gDen + gNum * best);
  return { P_clear_num: X, P_clear_den: Y + fdb };
}
export function solveClearing(X, Y, R_A, R_B, fee_bps) {
  X = _asU64(X, 'X'); Y = _asU64(Y, 'Y'); R_A = _asU64(R_A, 'R_A'); R_B = _asU64(R_B, 'R_B');
  fee_bps = BigInt(fee_bps);
  if (fee_bps < 0n || fee_bps > _FEE_BPS_MAX) throw new Error('fee_bps out of range');
  if (X === 0n && Y === 0n) return { P_clear_num: R_A, P_clear_den: R_B === 0n ? 1n : R_B };
  if (R_A === 0n || R_B === 0n) throw new Error('pool reserves must be > 0 for a non-empty batch');
  const gDen = 10000n, gNum = gDen - fee_bps;
  const lhs = X * R_B, rhs = Y * R_A;
  if (lhs > rhs) return _solveAToB(X, Y, R_A, R_B, gNum, gDen);
  if (lhs < rhs) { const r = _solveAToB(Y, X, R_B, R_A, gNum, gDen); return { P_clear_num: r.P_clear_den, P_clear_den: r.P_clear_num }; }
  return { P_clear_num: R_A, P_clear_den: R_B };
}

export function makeConfidentialSwap({ keccak256, pool }) {
  const { leaf, nullifier, nkToOwner, nativeNu, commitXY, openingSigma, verifyOpeningSigma, openingPokBlind, verifyOpeningPokBlind, deriveOpeningNonce, intentContext } = pool;

  function spentNullifier(asset, note, fail) {
    const lf = leaf(asset, note.cx, note.cy, note.owner);
    if (BigInt(note.owner ?? 0) === 0n) return nullifier(lf);
    if (note.nk == null) fail('input note requires nk to derive its nullifier');
    if (String(nkToOwner(note.nk)).toLowerCase() !== String(note.owner).toLowerCase()) fail('input nk does not commit to the note owner');
    return nativeNu(note.owner, note.nk, lf);
  }
  const hexToBytes = (h) => { h = (h || '').replace(/^0x/, ''); const o = new Uint8Array(h.length / 2); for (let i = 0; i < o.length; i++) o[i] = parseInt(h.substr(i * 2, 2), 16); return o; };
  const bytesToHex = (b) => '0x' + Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  const concat = (arr) => { const t = arr.reduce((s, x) => s + x.length, 0); const o = new Uint8Array(t); let p = 0; for (const x of arr) { o.set(x, p); p += x.length; } return o; };

  const be32 = (n) => { const o = new Uint8Array(32); let v = BigInt(n); for (let i = 31; i >= 0; i--) { o[i] = Number(v & 0xffn); v >>= 8n; } return o; };
  const bigOf = (h) => BigInt('0x' + h.replace(/^0x/, ''));
  const poolId = (a, b, feeBps) => {
    const [lo, hi] = bigOf(a) <= bigOf(b) ? [a, b] : [b, a];
    return bytesToHex(keccak256(concat([hexToBytes(lo), hexToBytes(hi), be32(feeBps)])));
  };

  function clearOut(direction, amountIn, priceNum, priceDen) {
    amountIn = BigInt(amountIn);
    const [mulN, divN] = direction === 'A->B' ? [BigInt(priceNum), BigInt(priceDen)] : [BigInt(priceDen), BigInt(priceNum)];
    const prod = amountIn * mulN;
    const amountOut = prod / divN;
    return { amountOut, rem: prod - amountOut * divN };
  }

  const intentCtx = (assetA, assetB, chainBinding, it) => intentContext(
    SWAP_TAG, chainBinding, assetA, assetB,
    [[it.in.cx, it.in.cy, it.in.owner], [it.out.cx, it.out.cy, it.out.owner]],
    [BigInt(it.dirByte), it.amountIn, it.amountOut, it.minOut, BigInt(it.deadline ?? 0), BigInt(it.fee ?? 0)],
  );

  function buildIntent({ direction, amountIn, priceNum, priceDen, minOut, rInSecp, rOutSecp, inNote, outOwner, deadline, fee = 0n, assetA, assetB }) {
    const feeBig = BigInt(fee);
    if (!(feeBig < BigInt(amountIn))) throw new Error('swap: fee >= input');
    const swapIn = BigInt(amountIn) - feeBig;
    const { amountOut, rem } = clearOut(direction, swapIn, priceNum, priceDen);
    const inC = commitXY(amountIn, rInSecp);
    const outC = commitXY(amountOut, rOutSecp);
    const nk = inNote.nk ?? inNote.secret;
    const inAsset = (assetA && assetB) ? (direction === 'A->B' ? assetA : assetB) : null;
    const inNullifier = inAsset
      ? spentNullifier(inAsset, { cx: inC.cx, cy: inC.cy, owner: inNote.owner, nk }, (m) => { throw new Error('swap: ' + m); })
      : null;
    const outAsset = (assetA && assetB) ? (direction === 'A->B' ? assetB : assetA) : null;
    const outLeaf = outAsset ? leaf(outAsset, outC.cx, outC.cy, outOwner) : null;
    return {
      direction, dirByte: direction === 'A->B' ? 0 : 1,
      in: { cx: inC.cx, cy: inC.cy, owner: inNote.owner, nk, leafIndex: inNote.leafIndex, path: inNote.path },
      amountIn: BigInt(amountIn), fee: feeBig, swapIn, amountOut, rem,
      minOut: BigInt(minOut ?? 0), deadline: BigInt(deadline ?? 0),
      out: { cx: outC.cx, cy: outC.cy, owner: outOwner },
      inNullifier, outLeaf,
      _r: { rIn: BigInt(rInSecp), rOut: BigInt(rOutSecp) },
    };
  }

  function buildBatch({ assetA, assetB, chainBinding, feeBps, reserveAPre, reserveBPre, priceNum, priceDen, intents, spendRoot }) {
    let gAin = 0n, gAout = 0n, gBin = 0n, gBout = 0n;
    for (const it of intents) {
      const ctx = intentCtx(assetA, assetB, chainBinding, it);
      it.inPok = openingPokBlind(it.amountIn, it._r.rIn, ctx, deriveOpeningNonce(it._r.rIn, ctx, 'swap-in-v'), deriveOpeningNonce(it._r.rIn, ctx, 'swap-in-r'));
      it.outSig = openingSigma(it.amountOut, it._r.rOut, ctx, deriveOpeningNonce(it._r.rOut, ctx, 'swap-out'));
      if (it.direction === 'A->B') { gAin += it.swapIn; gBout += it.amountOut; }
      else { gBin += it.swapIn; gAout += it.amountOut; }
    }
    const aPre = BigInt(reserveAPre), bPre = BigInt(reserveBPre);
    return {
      assetA, assetB, chainBinding, feeBps: Number(feeBps), poolId: poolId(assetA, assetB, feeBps), spendRoot,
      priceNum: BigInt(priceNum), priceDen: BigInt(priceDen),
      reserveAPre: aPre, reserveBPre: bPre,
      reserveAPost: aPre + gAin - gAout, reserveBPost: bPre + gBin - gBout,
      intents,
    };
  }

  function verifyBatch(batch, { merkleRootFrom }) {
    const fail = (m) => { throw new Error('swap: ' + m); };
    if (!(batch.priceNum > 0n && batch.priceDen > 0n)) fail('zero price');
    if (batch.spendRoot === ZERO32 || !batch.spendRoot) fail('membership requires a non-zero spend root');

    let gAin = 0n, gAout = 0n, gBin = 0n, gBout = 0n;
    const nullifiers = [], leaves = [], fees = [];
    for (const it of batch.intents) {
      const inAsset = it.direction === 'A->B' ? batch.assetA : batch.assetB;
      const outAsset = it.direction === 'A->B' ? batch.assetB : batch.assetA;

      const lf = leaf(inAsset, it.in.cx, it.in.cy, it.in.owner);
      if (merkleRootFrom(lf, it.in.leafIndex, it.in.path) !== batch.spendRoot) fail('membership');

      const ctx = intentCtx(batch.assetA, batch.assetB, batch.chainBinding, it);
      if (!verifyOpeningPokBlind(it.in.cx, it.in.cy, it.inPok.R, it.inPok.zV, it.inPok.zR, ctx)) fail('input opening');
      if (!verifyOpeningSigma(it.out.cx, it.out.cy, it.amountOut, it.outSig.R, it.outSig.z, ctx)) fail('output opening');

      const fee = BigInt(it.fee ?? 0n);
      if (!(fee < it.amountIn)) fail('fee >= input');
      const swapIn = it.amountIn - fee;
      const { amountOut, rem } = clearOut(it.direction, swapIn, batch.priceNum, batch.priceDen);
      if (amountOut !== it.amountOut || rem !== it.rem) fail('clearing');
      if (it.amountOut < it.minOut) fail('min_out');

      if (it.direction === 'A->B') { gAin += swapIn; gBout += it.amountOut; }
      else { gBin += swapIn; gAout += it.amountOut; }
      if (fee > 0n) fees.push({ assetId: inAsset, value: fee });

      const inNu = spentNullifier(inAsset, { ...it.in, nk: it.in.nk ?? it.inNk }, fail);
      const outLf = leaf(outAsset, it.out.cx, it.out.cy, it.out.owner);
      nullifiers.push(inNu);
      leaves.push(outLf);
      it.inNullifier = inNu;
      it.outLeaf = outLf;
    }

    const aPre = batch.reserveAPre, bPre = batch.reserveBPre;
    if (aPre + gAin < gAout) fail('reserve A underflow');
    if (bPre + gBin < gBout) fail('reserve B underflow');
    const aPost = aPre + gAin - gAout, bPost = bPre + gBin - gBout;
    if (aPost > U64_MAX || bPost > U64_MAX) fail('reserve overflow');
    if (aPost * bPost < aPre * bPre) fail('constant-product decreased');

    const cp = clearingPriceBperA(solveClearing(gAin, gBin, aPre, bPre, batch.feeBps));
    if (batch.priceNum !== cp.priceNum || batch.priceDen !== cp.priceDen) fail('declared price is not the fee-clearing price');

    return {
      settlement: { poolId: batch.poolId, reserveAPre: aPre, reserveBPre: bPre, reserveAPost: aPost, reserveBPost: bPost },
      nullifiers, leaves, fees,
    };
  }

  return { poolId, clearOut, clearingPriceBperA, buildIntent, buildBatch, verifyBatch };
}
