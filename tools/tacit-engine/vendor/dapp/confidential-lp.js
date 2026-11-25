
const ZERO32 = '0x' + '00'.repeat(32);

export function makeConfidentialLp({ keccak256, pool, kernelSign, rangeProve }) {
  const { leaf, nullifier, nkToOwner, nativeNu, commitXY, openingSigma, verifyOpeningSigma, openingPokBlind, verifyOpeningPokBlind, deriveOpeningNonce, intentContext } = pool;

  function spentNullifier(asset, note, fail) {
    const lf = leaf(asset, note.cx, note.cy, note.owner);
    if (BigInt(note.owner ?? 0) === 0n) return nullifier(lf);
    if (note.nk == null) return null;
    if (String(nkToOwner(note.nk)).toLowerCase() !== String(note.owner).toLowerCase()) fail('input nk does not commit to the note owner');
    return nativeNu(note.owner, note.nk, lf);
  }
  const enc = new TextEncoder();
  const hexToBytes = (h) => { h = (h || '').replace(/^0x/, ''); const o = new Uint8Array(h.length / 2); for (let i = 0; i < o.length; i++) o[i] = parseInt(h.substr(i * 2, 2), 16); return o; };
  const bytesToHex = (b) => '0x' + Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  const concat = (arr) => { const t = arr.reduce((s, x) => s + x.length, 0); const o = new Uint8Array(t); let p = 0; for (const x of arr) { o.set(x, p); p += x.length; } return o; };

  const be32 = (n) => { const o = new Uint8Array(32); let v = BigInt(n); for (let i = 31; i >= 0; i--) { o[i] = Number(v & 0xffn); v >>= 8n; } return o; };
  const bigOf = (h) => BigInt('0x' + h.replace(/^0x/, ''));
  const poolId = (a, b, feeBps) => {
    const [lo, hi] = bigOf(a) <= bigOf(b) ? [a, b] : [b, a];
    return bytesToHex(keccak256(concat([hexToBytes(lo), hexToBytes(hi), be32(feeBps)])));
  };
  const ZERO_RCPT = '0x' + '00'.repeat(33);
  const poolIdWithProtocolFee = (a, b, feeBps, recipient33 = ZERO_RCPT, pfBps = 0) => {
    if (BigInt(pfBps) === 0n) return poolId(a, b, feeBps);
    const [lo, hi] = bigOf(a) <= bigOf(b) ? [a, b] : [b, a];
    return bytesToHex(keccak256(concat([hexToBytes(lo), hexToBytes(hi), be32(feeBps), hexToBytes(recipient33), be32(pfBps)])));
  };
  const lpShareId = (pid) => bytesToHex(keccak256(concat([hexToBytes(pid), enc.encode('lp')])));
  const floorDiv = (num, den) => { num = BigInt(num); den = BigInt(den); const q = num / den; return { q, rem: num - q * den }; };
  const MINIMUM_LIQUIDITY = 1000n;
  const isqrt = (n) => { n = BigInt(n); if (n < 2n) return n; let x = n, y = (x + 1n) >> 1n; while (y < x) { x = y; y = (x + n / x) >> 1n; } return x; };
  const lpAddShares = (S, dA, dB, rA, rB) => {
    const a = (BigInt(S) * BigInt(dA)) / BigInt(rA);
    const b = (BigInt(S) * BigInt(dB)) / BigInt(rB);
    return a < b ? a : b;
  };

  const addCtx = (op) => {
    const pid = poolIdWithProtocolFee(op.assetA, op.assetB, op.feeBps, op.protocolFeeRecipient ?? ZERO_RCPT, op.protocolFeeBps ?? 0);
    const lpAsset = lpShareId(pid);
    const aIn = op.a.inputs ?? [{ cx: op.a.cx, cy: op.a.cy, owner: op.a.owner }];
    const bIn = op.b.inputs ?? [{ cx: op.b.cx, cy: op.b.cy, owner: op.b.owner }];
    return intentContext('tacit-lp-add-v1', op.chainBinding, op.assetA, op.assetB,
      [...aIn.map((n) => [n.cx, n.cy, n.owner]), ...bIn.map((n) => [n.cx, n.cy, n.owner]),
       [op.share.cx, op.share.cy, op.share.owner], [lpAsset, pid, op.share.owner]],
      [op.dA, op.dB, op.dShares, op.deadline ?? 0n, op.fee ?? 0n, BigInt(aIn.length), BigInt(bIn.length)]);
  };
  const removeCtx = (op) => intentContext('tacit-lp-remove-v1', op.chainBinding, op.assetA, op.assetB,
    [[op.share.cx, op.share.cy, op.share.owner], [op.a.cx, op.a.cy, op.a.owner], [op.b.cx, op.b.cy, op.b.owner]],
    [op.dShares, op.dA, op.dB, op.deadline ?? 0n, op.fee ?? 0n]);

  function buildAdd({ assetA, assetB, chainBinding, feeBps, protocolFeeBps = 0, protocolFeeRecipient = ZERO_RCPT, reserveAPre, reserveBPre, sharesPre, aNote, bNote, aNotes, bNotes, dA, dB, rA, rB, shareOwner, rShares, deadline, fee = 0n, aChange = [], bChange = [] }) {
    const legNotes = (arr, one, r) => (arr && arr.length
      ? arr.map((n) => ({ ...n, blinding: BigInt(n.blinding), value: BigInt(n.value) }))
      : [{ ...one, blinding: BigInt(r), value: null }]);
    const aIns = legNotes(aNotes, aNote, rA);
    const bIns = legNotes(bNotes, bNote, rB);
    const feeBig = BigInt(fee);
    if (!(feeBig < BigInt(dA))) throw new Error('lp_add: fee >= A contribution');
    const addA = BigInt(dA) - feeBig;
    let dShares;
    if (BigInt(sharesPre) === 0n) {
      const total = isqrt(addA * BigInt(dB));
      if (total <= MINIMUM_LIQUIDITY) throw new Error('lp_add: initial liquidity below MINIMUM_LIQUIDITY');
      dShares = total - MINIMUM_LIQUIDITY;
    } else {
      dShares = lpAddShares(sharesPre, addA, dB, reserveAPre, reserveBPre);
      if (dShares <= 0n) throw new Error('lp_add: contribution below one share');
    }
    const aTotal = aChange.reduce((t, c) => t + BigInt(c.value), BigInt(dA));
    const bTotal = bChange.reduce((t, c) => t + BigInt(c.value), BigInt(dB));
    const legCommit = (ins, total, r) => {
      if (ins.length === 1 && ins[0].value == null) {
        const c = commitXY(total, r);
        ins[0] = { ...ins[0], cx: c.cx, cy: c.cy, value: total };
        return ins;
      }
      const sum = ins.reduce((t, n) => t + n.value, 0n);
      if (sum !== total) throw new Error('lp_add: leg inputs must sum to the contribution + change');
      return ins.map((n) => ({ ...n, ...(n.cx ? {} : commitXY(n.value, n.blinding)) }));
    };
    const aFin = legCommit(aIns, aTotal, rA);
    const bFin = legCommit(bIns, bTotal, rB);
    const aC = { cx: aFin[0].cx, cy: aFin[0].cy }, bC = { cx: bFin[0].cx, cy: bFin[0].cy };
    const sC = commitXY(dShares, rShares);
    const op = {
      assetA, assetB, chainBinding, feeBps: Number(feeBps),
      protocolFeeBps: Number(protocolFeeBps), protocolFeeRecipient,
      deadline: BigInt(deadline ?? 0), fee: feeBig,
      reserveAPre: BigInt(reserveAPre), reserveBPre: BigInt(reserveBPre), sharesPre: BigInt(sharesPre),
      a: { cx: aC.cx, cy: aC.cy, owner: aFin[0].owner, leafIndex: aFin[0].leafIndex, path: aFin[0].path,
           inputs: aFin.map((n) => ({ cx: n.cx, cy: n.cy, owner: n.owner, leafIndex: n.leafIndex, path: n.path, nk: n.nk })) }, dA: BigInt(dA),
      b: { cx: bC.cx, cy: bC.cy, owner: bFin[0].owner, leafIndex: bFin[0].leafIndex, path: bFin[0].path,
           inputs: bFin.map((n) => ({ cx: n.cx, cy: n.cy, owner: n.owner, leafIndex: n.leafIndex, path: n.path, nk: n.nk })) }, dB: BigInt(dB),
      dShares, share: { cx: sC.cx, cy: sC.cy, owner: shareOwner },
    };
    const ctx = addCtx(op);
    const legPoks = (ins, tag) => ins.map((n, i) => openingPokBlind(
      n.value, n.blinding, ctx,
      deriveOpeningNonce(n.blinding, ctx, `${tag}-${i}-v`),
      deriveOpeningNonce(n.blinding, ctx, `${tag}-${i}-r`),
    ));
    const aPoks = legPoks(aFin, 'lp-add-a');
    const bPoks = legPoks(bFin, 'lp-add-b');
    op.a.inputs = op.a.inputs.map((n, i) => ({ ...n, pokR: aPoks[i].R, pokZv: aPoks[i].zV, pokZr: aPoks[i].zR }));
    op.b.inputs = op.b.inputs.map((n, i) => ({ ...n, pokR: bPoks[i].R, pokZv: bPoks[i].zV, pokZr: bPoks[i].zR }));
    op.aPok = aPoks[0]; op.bPok = bPoks[0];
    for (const leg of [op.a, op.b]) {
      const first = leg.inputs[0];
      for (const k of ['leafIndex', 'path']) {
        delete leg[k];
        Object.defineProperty(leg, k, {
          enumerable: true, configurable: true,
          get: () => first[k],
          set: (v) => { first[k] = v; },
        });
      }
    }
    op.sSig = openingSigma(op.dShares, rShares, ctx, deriveOpeningNonce(rShares, ctx, 'lp-add-share'));

    const mk = (asset, arr) => arr.map((c) => {
      const cc = commitXY(BigInt(c.value), BigInt(c.blinding));
      return { cx: cc.cx, cy: cc.cy, owner: c.owner, value: BigInt(c.value), blinding: BigInt(c.blinding), asset };
    });
    op.aChange = mk(assetA, aChange);
    op.bChange = mk(assetB, bChange);
    const aLeaves = op.aChange.map((c) => leaf(assetA, c.cx, c.cy, c.owner));
    const bLeaves = op.bChange.map((c) => leaf(assetB, c.cx, c.cy, c.owner));
    const aK = kernelSign({ inputs: aFin.map((n) => ({ value: n.value, blinding: n.blinding })), outputs: op.aChange, fee: BigInt(dA), outLeaves: aLeaves });
    const bK = kernelSign({ inputs: bFin.map((n) => ({ value: n.value, blinding: n.blinding })), outputs: op.bChange, fee: BigInt(dB), outLeaves: bLeaves });
    op.aKernelR = bytesToHex(aK.R.toRawBytes(true));
    op.aKernelZ = bytesToHex(be32(aK.z));
    op.bKernelR = bytesToHex(bK.R.toRawBytes(true));
    op.bKernelZ = bytesToHex(be32(bK.z));
    if (op.aChange.length || op.bChange.length) {
      const allCh = [...op.aChange, ...op.bChange];
      op.changeRangeProof = bytesToHex(rangeProve(allCh.map((c) => c.value), allCh.map((c) => c.blinding)).proof);
    }
    return op;
  }

  function verifyAdd(op, { merkleRootFrom, spendRoot }) {
    const fail = (m) => { throw new Error('lp_add: ' + m); };
    if (spendRoot === ZERO32 || !spendRoot) fail('membership requires a non-zero spend root');
    const pid = poolIdWithProtocolFee(op.assetA, op.assetB, op.feeBps, op.protocolFeeRecipient ?? ZERO_RCPT, op.protocolFeeBps ?? 0), lpAsset = lpShareId(pid);
    const legIns = (leg) => leg.inputs ?? [{ cx: leg.cx, cy: leg.cy, owner: leg.owner, leafIndex: leg.leafIndex, path: leg.path }];
    for (const [tag, leg, asset] of [['A', op.a, op.assetA], ['B', op.b, op.assetB]]) {
      for (const n of legIns(leg)) {
        if (merkleRootFrom(leaf(asset, n.cx, n.cy, n.owner), n.leafIndex, n.path) !== spendRoot) fail(tag + ' membership');
      }
    }
    const ctx = addCtx(op);
    if (!verifyOpeningPokBlind(op.a.cx, op.a.cy, op.aPok.R, op.aPok.zV, op.aPok.zR, ctx)) fail('A opening PoK');
    if (!verifyOpeningPokBlind(op.b.cx, op.b.cy, op.bPok.R, op.bPok.zV, op.bPok.zR, ctx)) fail('B opening PoK');
    for (const c of (op.aChange || [])) if (c.asset !== op.assetA) fail('A change asset != assetA');
    for (const c of (op.bChange || [])) if (c.asset !== op.assetB) fail('B change asset != assetB');
    const fee = BigInt(op.fee ?? 0n);
    if (!(fee < op.dA)) fail('fee >= A contribution');
    const addA = op.dA - fee;
    let reserveAPost, reserveBPost, sharesPost;
    if (op.sharesPre === 0n) {
      if (!(addA > 0n && op.dB > 0n)) fail('first mint needs both sides');
      const total = isqrt(addA * op.dB);
      if (total <= MINIMUM_LIQUIDITY) fail('initial liquidity below MINIMUM_LIQUIDITY');
      if (op.dShares !== total - MINIMUM_LIQUIDITY) fail('first-mint shares = isqrt(addA·dB) - MIN_LIQUIDITY');
      reserveAPost = addA; reserveBPost = op.dB; sharesPost = total;
    } else {
      if (!(op.reserveAPre > 0n && op.reserveBPre > 0n)) fail('pool must be initialized');
      const dShares = lpAddShares(op.sharesPre, addA, op.dB, op.reserveAPre, op.reserveBPre);
      if (!(dShares > 0n)) fail('zero shares minted (dust add would donate)');
      if (op.dShares !== dShares) fail('proportional shares');
      reserveAPost = op.reserveAPre + addA; reserveBPost = op.reserveBPre + op.dB; sharesPost = op.sharesPre + op.dShares;
    }
    if (!verifyOpeningSigma(op.share.cx, op.share.cy, op.dShares, op.sSig.R, op.sSig.z, ctx)) fail('share opening');
    return {
      settlement: {
        poolId: pid, reserveAPre: op.reserveAPre, reserveBPre: op.reserveBPre, sharesPre: op.sharesPre,
        reserveAPost, reserveBPost, sharesPost,
      },
      fees: fee > 0n ? [{ assetId: op.assetA, value: fee }] : [],
      nullifiers: [...legIns(op.a).map((n) => spentNullifier(op.assetA, n, fail)), ...legIns(op.b).map((n) => spentNullifier(op.assetB, n, fail))],
      leaves: [
        leaf(lpAsset, op.share.cx, op.share.cy, op.share.owner),
        ...(op.aChange || []).map((c) => leaf(op.assetA, c.cx, c.cy, c.owner)),
        ...(op.bChange || []).map((c) => leaf(op.assetB, c.cx, c.cy, c.owner)),
      ],
    };
  }

  function buildRemove({ assetA, assetB, chainBinding, feeBps, protocolFeeBps = 0, protocolFeeRecipient = ZERO_RCPT, reserveAPre, reserveBPre, sharesPre, shareNote, dShares, rShares, aOwner, rA, bOwner, rB, deadline, fee = 0n, shareChange = [] }) {
    const a = floorDiv(BigInt(reserveAPre) * BigInt(dShares), sharesPre);
    const b = floorDiv(BigInt(reserveBPre) * BigInt(dShares), sharesPre);
    const feeBig = BigInt(fee);
    if (!(feeBig < a.q)) throw new Error('lp_remove: fee >= A withdrawal');
    const netA = a.q - feeBig;
    const sTotal = shareChange.reduce((t, c) => t + BigInt(c.value), BigInt(dShares));
    const sC = commitXY(sTotal, rShares), aC = commitXY(netA, rA), bC = commitXY(b.q, rB);
    const op = {
      assetA, assetB, chainBinding, feeBps: Number(feeBps),
      protocolFeeBps: Number(protocolFeeBps), protocolFeeRecipient,
      deadline: BigInt(deadline ?? 0), fee: feeBig,
      reserveAPre: BigInt(reserveAPre), reserveBPre: BigInt(reserveBPre), sharesPre: BigInt(sharesPre),
      share: { cx: sC.cx, cy: sC.cy, owner: shareNote.owner, leafIndex: shareNote.leafIndex, path: shareNote.path, nk: shareNote.nk }, dShares: BigInt(dShares),
      dA: a.q, remA: a.rem, dB: b.q, remB: b.rem,
      a: { cx: aC.cx, cy: aC.cy, owner: aOwner },
      b: { cx: bC.cx, cy: bC.cy, owner: bOwner },
    };
    const ctx = removeCtx(op);
    op.sPok = openingPokBlind(sTotal, rShares, ctx, deriveOpeningNonce(rShares, ctx, 'lp-rm-share-v'), deriveOpeningNonce(rShares, ctx, 'lp-rm-share-r'));
    {
      const pid2 = poolIdWithProtocolFee(assetA, assetB, Number(feeBps), protocolFeeRecipient ?? ZERO_RCPT, Number(protocolFeeBps) || 0);
      const lpAsset2 = lpShareId(pid2);
      op.shareChange = shareChange.map((c) => {
        const cc = commitXY(BigInt(c.value), BigInt(c.blinding));
        return { cx: cc.cx, cy: cc.cy, owner: c.owner, value: BigInt(c.value), blinding: BigInt(c.blinding), asset: lpAsset2 };
      });
      const sLeaves = op.shareChange.map((c) => leaf(lpAsset2, c.cx, c.cy, c.owner));
      const sK = kernelSign({ inputs: [{ value: sTotal, blinding: BigInt(rShares) }], outputs: op.shareChange, fee: BigInt(dShares), outLeaves: sLeaves });
      op.shareKernelR = bytesToHex(sK.R.toRawBytes(true));
      op.shareKernelZ = bytesToHex(be32(sK.z));
      if (op.shareChange.length) {
        op.changeRangeProof = bytesToHex(rangeProve(op.shareChange.map((c) => c.value), op.shareChange.map((c) => c.blinding)).proof);
      }
    }
    op.aSig = openingSigma(netA, rA, ctx, deriveOpeningNonce(rA, ctx, 'lp-rm-a'));
    op.bSig = openingSigma(op.dB, rB, ctx, deriveOpeningNonce(rB, ctx, 'lp-rm-b'));
    return op;
  }

  function verifyRemove(op, { merkleRootFrom, spendRoot }) {
    const fail = (m) => { throw new Error('lp_remove: ' + m); };
    if (spendRoot === ZERO32 || !spendRoot) fail('membership requires a non-zero spend root');
    const pid = poolIdWithProtocolFee(op.assetA, op.assetB, op.feeBps, op.protocolFeeRecipient ?? ZERO_RCPT, op.protocolFeeBps ?? 0), lpAsset = lpShareId(pid);
    if (merkleRootFrom(leaf(lpAsset, op.share.cx, op.share.cy, op.share.owner), op.share.leafIndex, op.share.path) !== spendRoot) fail('share membership');
    const ctx = removeCtx(op);
    if (!verifyOpeningPokBlind(op.share.cx, op.share.cy, op.sPok.R, op.sPok.zV, op.sPok.zR, ctx)) fail('share opening PoK');
    for (const c of (op.shareChange || [])) if (c.asset !== lpAsset) fail('share change asset != lpAsset');
    if (!(op.sharesPre > 0n && op.dShares > 0n && op.dShares <= op.sharesPre)) fail('shares in range');
    if (op.sharesPre - op.dShares < MINIMUM_LIQUIDITY) fail('would breach MINIMUM_LIQUIDITY floor');
    const a = floorDiv(op.reserveAPre * op.dShares, op.sharesPre);
    const b = floorDiv(op.reserveBPre * op.dShares, op.sharesPre);
    if (a.q !== op.dA || a.rem !== op.remA) fail('dA proportional');
    if (b.q !== op.dB || b.rem !== op.remB) fail('dB proportional');
    const fee = BigInt(op.fee ?? 0n);
    if (!(fee < op.dA)) fail('fee >= A withdrawal');
    const netA = op.dA - fee;
    if (!verifyOpeningSigma(op.a.cx, op.a.cy, netA, op.aSig.R, op.aSig.z, ctx)) fail('A opening (net of relay fee)');
    if (!verifyOpeningSigma(op.b.cx, op.b.cy, op.dB, op.bSig.R, op.bSig.z, ctx)) fail('B opening');
    return {
      settlement: {
        poolId: pid, reserveAPre: op.reserveAPre, reserveBPre: op.reserveBPre, sharesPre: op.sharesPre,
        reserveAPost: op.reserveAPre - op.dA, reserveBPost: op.reserveBPre - op.dB, sharesPost: op.sharesPre - op.dShares,
      },
      fees: fee > 0n ? [{ assetId: op.assetA, value: fee }] : [],
      nullifiers: [spentNullifier(lpAsset, op.share, fail)],
      leaves: [
        leaf(op.assetA, op.a.cx, op.a.cy, op.a.owner), leaf(op.assetB, op.b.cx, op.b.cy, op.b.owner),
        ...(op.shareChange || []).map((c) => leaf(lpAsset, c.cx, c.cy, c.owner)),
      ],
    };
  }

  return { poolId, poolIdWithProtocolFee, lpShareId, buildAdd, verifyAdd, buildRemove, verifyRemove, isqrt, MINIMUM_LIQUIDITY, lpAddShares };
}
