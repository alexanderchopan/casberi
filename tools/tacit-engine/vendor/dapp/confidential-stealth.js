
export function makeConfidentialStealth({ keccak256, secp, signSchnorr, curveOrder, pool, transfer }) {
  const Pt = secp.ProjectivePoint;
  const G = Pt.BASE;
  const N = BigInt(curveOrder);
  const enc = new TextEncoder();
  const LOCK_DOMAIN = enc.encode('tacit-stealth-lock-v1');
  const LOCK_BLIND_DOMAIN = enc.encode('tacit-stealth-lock-blind-v1');
  const CLAIM_DOMAIN = enc.encode('tacit-stealth-claim-v1');
  const REFUND_DOMAIN = enc.encode('tacit-stealth-refund-auth-v1');
  const ECDH_DOMAIN = enc.encode('tacit-stealth-ecdh-v1');

  const hx = (b) => '0x' + [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  const concat = (arrs) => {
    const n = arrs.reduce((s, a) => s + a.length, 0);
    const o = new Uint8Array(n);
    let p = 0;
    for (const a of arrs) { o.set(a, p); p += a.length; }
    return o;
  };
  const bN = (h, n) => {
    const s = String(h).replace(/^0x/, '').padStart(n * 2, '0');
    if (s.length !== n * 2) throw new Error(`expected ${n}-byte value, got ${s.length / 2}`);
    const o = new Uint8Array(n);
    for (let i = 0; i < n; i++) o[i] = parseInt(s.slice(i * 2, i * 2 + 2), 16);
    return o;
  };
  const b32 = (h) => bN(h, 32);
  const be = (v, n) => {
    let x = BigInt(v);
    const o = new Uint8Array(n);
    for (let i = n - 1; i >= 0; i--) { o[i] = Number(x & 0xffn); x >>= 8n; }
    return o;
  };
  const bToBig = (b) => { let x = 0n; for (const y of b) x = (x << 8n) | BigInt(y); return x; };
  const modN = (x) => ((x % N) + N) % N;
  const k = (...parts) => keccak256(concat(parts));
  const compress = (P) => P.toRawBytes(true);
  const xOnly = (P) => P.toRawBytes(true).slice(1);
  const ptFrom = (hexCompressedOrXonly) => {
    const s = String(hexCompressedOrXonly).replace(/^0x/, '');
    return s.length === 64 ? Pt.fromHex('02' + s) : Pt.fromHex(s);
  };

  const stealthLockLeaf = (asset, cx, cy, ownerPub, amount, deadline, locker) =>
    hx(k(LOCK_DOMAIN, b32(asset), b32(cx), b32(cy), b32(ownerPub), be(amount, 8), be(deadline, 8), b32(locker)));
  const stealthLockLeafBlind = (asset, cx, cy, ownerPub, deadline, locker) =>
    hx(k(LOCK_BLIND_DOMAIN, b32(asset), b32(cx), b32(cy), b32(ownerPub), be(deadline, 8), b32(locker)));
  const stealthClaimMsg = (chainBinding, lockLeaf, mCx, mCy, mOwner, amount, fee) =>
    k(CLAIM_DOMAIN, b32(chainBinding), b32(lockLeaf), b32(mCx), b32(mCy), b32(mOwner), be(amount, 8), be(fee, 8));
  const stealthClaimMsgBlind = (chainBinding, lockLeaf, mCx, mCy, mOwner, fee) =>
    k(CLAIM_DOMAIN, b32(chainBinding), b32(lockLeaf), b32(mCx), b32(mCy), b32(mOwner), enc.encode('blind'), be(fee, 8));
  const stealthRefundMsg = (chainBinding, lockLeaf, oCx, oCy, fee, oOwner) =>
    k(REFUND_DOMAIN, b32(chainBinding), b32(lockLeaf), b32(oCx), b32(oCy), be(fee, 8), b32(oOwner));

  const _shared = (sharedPt) => modN(bToBig(keccak256(concat([ECDH_DOMAIN, compress(sharedPt)]))));

  const oneTimeAddress = ({ recipientSpendPub, ephemeralPriv }) => {
    const B = ptFrom(recipientSpendPub);
    const e = modN(BigInt(ephemeralPriv));
    const s = _shared(B.multiply(e));
    const O = B.add(G.multiply(s));
    return { ephemeralPub: hx(compress(G.multiply(e))), ownerPub: hx(xOnly(O)) };
  };

  const recoverOneTimeKey = ({ recipientSpendPriv, ephemeralPub }) => {
    const b = modN(BigInt(recipientSpendPriv));
    const E = ptFrom(ephemeralPub);
    const s = _shared(E.multiply(b));
    const oneTimePriv = modN(b + s);
    return { oneTimePriv: hx(be(oneTimePriv, 32)), ownerPub: hx(xOnly(G.multiply(oneTimePriv))) };
  };

  const scanLock = ({ recipientSpendPriv, ephemeralPub, ownerPub }) =>
    recoverOneTimeKey({ recipientSpendPriv, ephemeralPub }).ownerPub.toLowerCase() === String(ownerPub).toLowerCase();

  const signClaim = ({ oneTimePriv, claimMsg }) => hx(signSchnorr(claimMsg, b32(oneTimePriv)));

  const buildStealthLock = ({ chainBinding, asset, locker, refundPub, ownerPub, amount, deadline, spendRoot, nNote, lBlinding }) => {
    if (!nNote || nNote.secret == null) throw new Error('buildStealthLock: nNote.secret (the note\'s own nk) is required — the guest reads it via native_nu right after nPath (exec-stealthlock.rs), so an op built without it can never settle');
    const { cx: lCx, cy: lCy } = pool.commitXY(amount, lBlinding);
    const lockLeaf = stealthLockLeafBlind(asset, lCx, lCy, ownerPub, deadline, refundPub);
    const kt = transfer.kernelSign({ inputs: [{ value: BigInt(amount), blinding: BigInt(nNote.blinding) }],
      outputs: [{ value: BigInt(amount), blinding: BigInt(lBlinding) }], fee: 0n, outLeaves: [lockLeaf] });
    const pokCtx = pool.intentContext('tacit-stealth-lock-input-v1', chainBinding, asset, asset,
      [[nNote.cx, nNote.cy, locker], [lCx, lCy, ownerPub]], [BigInt(deadline)]);
    const nonceV = pool.deriveOpeningNonce(nNote.blinding, pokCtx, 'stealth-lock-v');
    const nonceR = pool.deriveOpeningNonce(nNote.blinding, pokCtx, 'stealth-lock-r');
    const pok = pool.openingPokBlind(BigInt(amount), nNote.blinding, pokCtx, nonceV, nonceR);
    return { chainBinding, spendRoot, asset, locker, refundPub, ownerPub, deadline: Number(deadline),
      nCx: nNote.cx, nCy: nNote.cy, nIndex: nNote.leafIndex, nPath: nNote.path, nk: nNote.secret,
      lCx, lCy, lockLeaf, kernelR: hx(kt.R.toRawBytes(true)), kernelZ: hx(be(kt.z, 32)),
      inPokR: pok.R, inPokZv: pok.zV, inPokZr: pok.zR };
  };

  const buildStealthClaim = ({ chainBinding, asset, lCx, lCy, ownerPub, amount, deadline, locker, lBlinding, lockSetRoot, lIndex, lPath, oneTimePriv, mOwner, fee = 0n, mBlinding }) => {
    const net = BigInt(amount) - BigInt(fee);
    const kt = transfer.buildTransfer({ inputs: [{ value: BigInt(amount), blinding: BigInt(lBlinding) }],
      outputs: [{ value: net, blinding: BigInt(mBlinding), owner: mOwner }], fee: BigInt(fee), assetId: asset });
    const { cx: mCx, cy: mCy } = pool.commitXY(net, mBlinding);
    const lockLeaf = stealthLockLeafBlind(asset, lCx, lCy, ownerPub, deadline, locker);
    const claimMsg = stealthClaimMsgBlind(chainBinding, lockLeaf, mCx, mCy, mOwner, fee);
    const ownerSig = signClaim({ oneTimePriv, claimMsg });
    return { blind: 1, chainBinding, lockSetRoot, asset, lCx, lCy, ownerPub, deadline: Number(deadline),
      locker, lIndex, lPath, mCx, mCy, mOwner, fee: Number(fee),
      kernelR: hx(kt.kernel.R.toRawBytes(true)), kernelZ: hx(be(kt.kernel.z, 32)), mRange: kt.rangeProof, ownerSig };
  };

  const STEALTH_MAX_DEADLINE = (1n << 64n) - 1n;
  function recoverProtocolFeeLock({ asset, poolId, firstInputNu, reserveAPre, reserveBPre, cut, recipientX }) {
    const rHex = pool.protofeeBlind(firstInputNu, poolId, reserveAPre, reserveBPre, asset, cut, recipientX);
    const lBlinding = modN(bToBig(b32(rHex)));
    const { cx: lCx, cy: lCy } = pool.commitXY(cut, lBlinding);
    const lockLeaf = stealthLockLeaf(asset, lCx, lCy, recipientX, cut, STEALTH_MAX_DEADLINE, recipientX);
    return { asset, lCx, lCy, lBlinding, amount: BigInt(cut), deadline: STEALTH_MAX_DEADLINE, locker: recipientX, ownerPub: recipientX, lockLeaf };
  }

  const buildStealthClaimAmount = ({ chainBinding, asset, lCx, lCy, ownerPub, amount, deadline, locker, lockSetRoot, lIndex, lPath, oneTimePriv, mOwner, fee = 0n, mBlinding }) => {
    const amountB = BigInt(amount), feeB = BigInt(fee), deadlineB = BigInt(deadline);
    if (feeB >= amountB) throw new Error('stealth-claim (amount): fee must be < the locked amount');
    const net = amountB - feeB;
    const { cx: mCx, cy: mCy } = pool.commitXY(net, mBlinding);
    const lockLeaf = stealthLockLeaf(asset, lCx, lCy, ownerPub, amountB, deadlineB, locker);
    const mCtx = pool.intentContext('tacit-stealth-claim-out-v1', chainBinding, asset, asset,
      [[mCx, mCy, mOwner]], [amountB, feeB]);
    const nonce = pool.deriveOpeningNonce(mBlinding, mCtx, 'stealth-claim-amount-m');
    const sig = pool.openingSigma(net, mBlinding, mCtx, nonce);
    const claimMsg = stealthClaimMsg(chainBinding, lockLeaf, mCx, mCy, mOwner, amountB, feeB);
    const ownerSig = signClaim({ oneTimePriv, claimMsg });
    return { blind: 0, chainBinding, lockSetRoot, asset, lCx, lCy, ownerPub,
      amount: amountB.toString(), deadline: deadlineB.toString(), locker, lIndex, lPath,
      mCx, mCy, mOwner, fee: Number(feeB),
      mSigR: sig.R, mSigZ: sig.z, ownerSig };
  };

  const buildStealthRefund = ({ chainBinding, asset, lCx, lCy, ownerPub, amount, deadline, locker, lockerPriv, refundOwner, lockSetRoot, lIndex, lPath, lBlinding, fee = 0n, oBlinding }) => {
    const net = BigInt(amount) - BigInt(fee);
    const kt = transfer.buildTransfer({ inputs: [{ value: BigInt(amount), blinding: BigInt(lBlinding) }],
      outputs: [{ value: net, blinding: BigInt(oBlinding), owner: refundOwner }], fee: BigInt(fee), assetId: asset });
    const { cx: oCx, cy: oCy } = pool.commitXY(net, oBlinding);
    const lockLeaf = stealthLockLeafBlind(asset, lCx, lCy, ownerPub, deadline, locker);
    const lockerSig = hx(signSchnorr(stealthRefundMsg(chainBinding, lockLeaf, oCx, oCy, fee, refundOwner), b32(lockerPriv)));
    return { chainBinding, lockSetRoot, asset, lCx, lCy, ownerPub, deadline: Number(deadline),
      locker, refundOwner, lIndex, lPath, oCx, oCy, fee: Number(fee),
      kernelR: hx(kt.kernel.R.toRawBytes(true)), kernelZ: hx(be(kt.kernel.z, 32)), oRange: kt.rangeProof, lockerSig };
  };

  const buildBridgeStealthMint = ({ chainBinding, bitcoinBurnRoot, asset, poolRoot, burned, ownerPub, amount, deadline, locker, lBlinding, bmNext, bmIndex, bmPath, fee = 0n }) => {
    const net = BigInt(amount) - BigInt(fee);
    const { cx: lCx, cy: lCy } = pool.commitXY(net, lBlinding);
    const kt = transfer.kernelSign({ inputs: [{ value: BigInt(amount), blinding: BigInt(burned.blinding) }],
      outputs: [{ value: net, blinding: BigInt(lBlinding) }], fee: BigInt(fee), outLeaves: [] });
    const { proof: lRange } = transfer.rangeProve([net], [BigInt(lBlinding)]);
    let inOwner = burned.owner;
    if (burned.sourceClass != null && Number(burned.sourceClass) === 0) {
      if (burned.spentTxid == null || burned.spentVout == null) throw new Error('bridge-stealth-mint: a deposit note needs its spent outpoint');
      const key = pool.outpointKey(burned.spentTxid, Number(burned.spentVout));
      if (inOwner != null && String(inOwner).toLowerCase() !== String(key).toLowerCase()) {
        throw new Error('bridge-stealth-mint: deposit note owner must be its burned outpoint key');
      }
      inOwner = key;
    }
    return { chainBinding, bitcoinBurnRoot, poolRoot, asset, ownerPub, deadline: Number(deadline), locker,
      inCx: burned.cx, inCy: burned.cy, inOwner, inIndex: burned.leafIndex, inPath: burned.path,
      sourceClass: Number(burned.sourceClass), spentTxid: burned.spentTxid, spentVout: Number(burned.spentVout),
      lCx, lCy, bmNext, bmIndex, bmPath, fee: Number(fee),
      kernelR: hx(kt.R.toRawBytes(true)), kernelZ: hx(be(kt.z, 32)), lRange: hx(lRange) };
  };

  const buildSendUnwrap = ({ chainBinding, asset, note, recipient, payout, fee = 0n, opDeadline = 0n, change, spendRoot }) => {
    const payoutB = BigInt(payout), feeB = BigInt(fee), deadlineB = BigInt(opDeadline);
    const publicExit = payoutB + feeB;
    const outputs = change.map((c) => ({ value: BigInt(c.value), blinding: BigInt(c.blinding), owner: c.owner }));
    const sumChange = outputs.reduce((s, o) => s + o.value, 0n);
    const noteValue = BigInt(note.value);
    if (noteValue !== sumChange + publicExit) throw new Error('send-unwrap: value ≠ Σchange + payout + fee');
    const kt = transfer.buildTransfer({ inputs: [{ value: noteValue, blinding: BigInt(note.blinding) }],
      outputs, fee: publicExit, assetId: asset });
    const { cx, cy } = pool.commitXY(noteValue, note.blinding);
    const recip32 = '0x' + '00'.repeat(12) + String(recipient).replace(/^0x/, '');
    const ctx = pool.intentContext('tacit-send-unwrap-intent-v1', chainBinding, asset, recip32,
      [[cx, cy, note.owner]], [payoutB, feeB, deadlineB]);
    const nonceV = pool.deriveOpeningNonce(note.blinding, ctx, 'send-unwrap-v');
    const nonceR = pool.deriveOpeningNonce(note.blinding, ctx, 'send-unwrap-r');
    const pok = pool.openingPokBlind(noteValue, note.blinding, ctx, nonceV, nonceR);
    const changeMeta = kt.outC.map((P, j) => { const { cx: ccx, cy: ccy } = pool.commitXY(outputs[j].value, outputs[j].blinding); return { cx: ccx, cy: ccy, owner: outputs[j].owner }; });
    return { chainBinding, spendRoot, asset,
      input: { cx, cy, owner: note.owner, leafIndex: note.leafIndex, path: note.path, nk: note.nk ?? note.secret, secret: note.secret },
      recipient, payout: Number(payoutB), fee: Number(feeB), opDeadline: Number(deadlineB),
      pokR: pok.R, pokZv: pok.zV, pokZr: pok.zR,
      change: changeMeta,
      rangeProof: '0x' + [...kt.rangeProof].map((b) => b.toString(16).padStart(2, '0')).join(''),
      kernelR: hx(kt.kernel.R.toRawBytes(true)), kernelZ: hx(be(kt.kernel.z, 32)),
      _ctx: ctx };
  };

  return {
    stealthLockLeaf, stealthLockLeafBlind, stealthClaimMsg, stealthClaimMsgBlind, stealthRefundMsg, oneTimeAddress, recoverOneTimeKey, scanLock, signClaim,
    buildStealthLock, buildStealthClaim, buildStealthRefund, buildBridgeStealthMint, buildSendUnwrap,
    recoverProtocolFeeLock, buildStealthClaimAmount,
  };
}
