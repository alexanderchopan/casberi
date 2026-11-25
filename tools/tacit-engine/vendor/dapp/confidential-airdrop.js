
const PLAIN_LEN = 112;
const MAX_DENOM_PER_OP = 7;
const POW2 = [1, 2, 4, 8];

export function makeConfidentialAirdrop({ stealth, secp, sha256, keccak256, curveOrder, pool, transfer }) {
  const Pt = secp.ProjectivePoint, G = Pt.BASE, N = BigInt(curveOrder);
  const enc = new TextEncoder();
  const EPH_DOMAIN = enc.encode('tacit-airdrop-eph-v1');
  const BLIND_DOMAIN = enc.encode('tacit-airdrop-blind-v1');
  const REFUND_DOMAIN = enc.encode('tacit-airdrop-refund-v1');

  const hx = (b) => '0x' + [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  const hb = (h) => Uint8Array.from((String(h).replace(/^0x/, '').match(/../g) || []).map((x) => parseInt(x, 16)));
  const cat = (a) => { const o = new Uint8Array(a.reduce((s, x) => s + x.length, 0)); let p = 0; for (const x of a) { o.set(x, p); p += x.length; } return o; };
  const b32 = (h) => { const b = hb(h); if (b.length > 32) throw new Error('over 32 bytes'); const o = new Uint8Array(32); o.set(b, 32 - b.length); return o; };
  const be = (v, n) => { let x = BigInt(v); const o = new Uint8Array(n); for (let i = n - 1; i >= 0; i--) { o[i] = Number(x & 0xffn); x >>= 8n; } return o; };
  const bBig = (b) => { let x = 0n; for (const y of b) x = (x << 8n) | BigInt(y); return x; };
  const modN = (x) => ((x % N) + N) % N;
  const pt = (h) => { const s = String(h).replace(/^0x/, ''); return s.length === 64 ? Pt.fromHex('02' + s) : Pt.fromHex(s); };
  const kBig = (...parts) => modN(bBig(keccak256(cat(parts))));

  const ksXor = (data, ss) => {
    const o = new Uint8Array(data.length);
    let off = 0, c = 0;
    while (off < data.length) { const blk = sha256(cat([ss, Uint8Array.of(c++ & 0xff)])); for (let i = 0; i < 32 && off < data.length; i++, off++) o[off] = data[off] ^ blk[i]; }
    return o;
  };

  const ephPriv = (lockerScanPriv, recipientSpendPub, i, salt) =>
    kBig(EPH_DOMAIN, b32(salt), b32(lockerScanPriv), hb(recipientSpendPub), be(i, 4)) || 1n;
  const lockBlinding = (lockerScanPriv, i, salt) =>
    '0x' + (kBig(BLIND_DOMAIN, b32(salt), b32(lockerScanPriv), be(i, 4)) || 1n).toString(16).padStart(64, '0');
  const refundPriv = (lockerScanPriv, i, salt) =>
    kBig(REFUND_DOMAIN, b32(salt), b32(lockerScanPriv), be(i, 4)) || 1n;
  const refundPubOf = (priv) => hx(G.multiply(modN(BigInt(priv))).toRawBytes(true).slice(1));

  const sealStealthMemo = ({ recipientSpendPub, ephemeralPriv, asset, amount, lBlinding, deadline, refundPub }) => {
    const ss = sha256(pt(recipientSpendPub).multiply(BigInt(ephemeralPriv)).toRawBytes(true));
    const plain = cat([b32(asset), be(amount, 8), b32(lBlinding), be(deadline, 8), b32(refundPub)]);
    return hx(cat([G.multiply(BigInt(ephemeralPriv)).toRawBytes(true), ksXor(plain, ss)]));
  };

  const openStealthMemo = ({ recipientSpendPriv, leaf, memoHex }) => {
    try {
      const b = hb(memoHex);
      if (b.length < 33 + PLAIN_LEN) return null;
      const ephemeralPub = hx(b.subarray(0, 33));
      const p = ksXor(b.subarray(33, 33 + PLAIN_LEN), sha256(pt(ephemeralPub).multiply(modN(BigInt(recipientSpendPriv))).toRawBytes(true)));
      const asset = hx(p.subarray(0, 32)), amount = bBig(p.subarray(32, 40)),
        lBlinding = hx(p.subarray(40, 72)),
        deadline = bBig(p.subarray(72, 80)), refundPub = hx(p.subarray(80, 112));
      const { ownerPub } = stealth.recoverOneTimeKey({ recipientSpendPriv, ephemeralPub });
      const { cx: lCx, cy: lCy } = pool.commitXY(amount, lBlinding);
      const lockLeaf = stealth.stealthLockLeafBlind(asset, lCx, lCy, ownerPub, deadline, refundPub);
      if (lockLeaf.toLowerCase() !== String(leaf).toLowerCase()) return null;
      return { ephemeralPub, asset, amount, lCx, lCy, lBlinding, deadline, refundPub, ownerPub };
    } catch { return null; }
  };

  const SENDER_TAIL_LEN = 177;
  const SENDER_TAIL_DOMAIN = enc.encode('tacit-stealth-sender-v1');
  const senderTailKey = (senderPriv, ephemeralPub) =>
    sha256(cat([pt(ephemeralPub).multiply(modN(BigInt(senderPriv))).toRawBytes(true), SENDER_TAIL_DOMAIN]));

  const sealStealthSenderTail = ({ senderPriv, ephemeralPub, asset, amount, lBlinding, deadline, refundPriv, ownerPub, recipientPub }) => {
    const plain = cat([
      b32(asset), be(amount, 8), b32(lBlinding), be(deadline, 8),
      b32(refundPriv), b32(ownerPub), hb(recipientPub),
    ]);
    return hx(ksXor(plain, senderTailKey(senderPriv, ephemeralPub)));
  };

  const openStealthSenderTail = ({ senderPriv, ephemeralPub, leaf, tailHex }) => {
    try {
      const t = hb(tailHex);
      if (t.length !== SENDER_TAIL_LEN) return null;
      const p = ksXor(t, senderTailKey(senderPriv, ephemeralPub));
      const asset = hx(p.subarray(0, 32)), amount = bBig(p.subarray(32, 40)),
        lBlinding = hx(p.subarray(40, 72)), deadline = bBig(p.subarray(72, 80)),
        refundPriv = hx(p.subarray(80, 112)), ownerPub = hx(p.subarray(112, 144)),
        recipientPub = hx(p.subarray(144, 177));
      const refundPub = hx(G.multiply(modN(BigInt(refundPriv))).toRawBytes(true).slice(1));
      const { cx: lCx, cy: lCy } = pool.commitXY(amount, lBlinding);
      const lockLeaf = stealth.stealthLockLeafBlind(asset, lCx, lCy, ownerPub, deadline, refundPub);
      if (lockLeaf.toLowerCase() !== String(leaf).toLowerCase()) return null;
      return { asset, amount, lCx, lCy, lBlinding, deadline, refundPriv, refundPub, ownerPub, recipientPub };
    } catch { return null; }
  };

  function buildAirdrop({ chainBinding, asset, lockerNk, lockerScanPriv, deadline, spendRoot, recipients, fundingNotes, salt = '0x' + '00'.repeat(32) }) {
    if (recipients.length !== fundingNotes.length) throw new Error('airdrop: one funding note per recipient');
    const locker = pool.nkToOwner(lockerNk);
    const ops = [], leaves = [], memos = [];
    recipients.forEach((r, i) => {
      const amount = BigInt(r.amount);
      const ePriv = ephPriv(lockerScanPriv, r.recipientSpendPub, i, salt);
      const { ownerPub } = stealth.oneTimeAddress({ recipientSpendPub: r.recipientSpendPub, ephemeralPriv: ePriv });
      const lBlinding = lockBlinding(lockerScanPriv, i, salt);
      const refundPub = refundPubOf(refundPriv(lockerScanPriv, i, salt));
      const nNote = { ...fundingNotes[i], secret: lockerNk };
      const op = stealth.buildStealthLock({ chainBinding, asset, locker, refundPub, ownerPub, amount, deadline, spendRoot, nNote, lBlinding });
      ops.push(op);
      leaves.push(op.lockLeaf);
      memos.push(sealStealthMemo({ recipientSpendPub: r.recipientSpendPub, ephemeralPriv: ePriv, asset, amount, lBlinding, deadline, refundPub }));
    });
    return { ops, leaves, memos };
  }

  function scanAirdrop({ recipientSpendPriv, events }) {
    const mine = [];
    for (const ev of events) {
      try {
        const m = openStealthMemo({ recipientSpendPriv, leaf: ev && ev.leaf, memoHex: ev && ev.memo });
        if (!m) continue;
        const { oneTimePriv } = stealth.recoverOneTimeKey({ recipientSpendPriv, ephemeralPub: m.ephemeralPub });
        mine.push({ ...m, oneTimePriv, leaf: ev.leaf });
      } catch { }
    }
    return mine;
  }

  const FUND_DOMAIN = enc.encode('tacit-airdrop-fund-v1');
  const outBlinding = (lockerScanPriv, role, i, salt) =>
    (kBig(FUND_DOMAIN, b32(salt), b32(lockerScanPriv), Uint8Array.of(role), be(i, 4)) || 1n);

  function planFunding({ sources, amounts, fee = 0n }) {
    const f = BigInt(fee);
    const totalSrc = sources.reduce((s, x) => s + BigInt(x.value), 0n);
    const totalAmt = amounts.reduce((s, a) => s + BigInt(a), 0n);
    if (totalAmt + f > totalSrc) throw new Error('airdrop funding: sources under-funded');
    const room = sources.map((s) => BigInt(s.value));
    const denom = sources.map(() => []);
    const sorted = amounts.map((a, i) => ({ v: BigInt(a), i })).sort((a, b) => (b.v > a.v ? 1 : b.v < a.v ? -1 : 0));
    for (const a of sorted) {
      const si = room.findIndex((r, k) => denom[k].length < MAX_DENOM_PER_OP && r >= a.v);
      if (si < 0) throw new Error('airdrop funding: cannot pack an amount — need more or larger sources');
      denom[si].push({ amount: a.v, amountIndex: a.i }); room[si] -= a.v;
    }
    const plan = [];
    for (let si = 0; si < sources.length; si++) {
      if (!denom[si].length) continue;
      const opFee = plan.length === 0 ? f : 0n;
      const change = room[si] - opFee;
      if (change < 0n) throw new Error('airdrop funding: first source cannot cover the fee');
      const real = denom[si].length + 1;
      const m = POW2.find((x) => x >= real);
      plan.push({ sourceIndex: si, denom: denom[si], change, fee: opFee, m, pad: m - real });
    }
    if (f > 0n && !plan.length) throw new Error('airdrop funding: fee with no outputs');
    return plan;
  }

  function buildFunding({ asset, sources, amounts, lockerNk, lockerScanPriv, fee = 0n, salt = '0x' + '00'.repeat(32) }) {
    if (!pool || !transfer) throw new Error('airdrop funding needs { pool, transfer } injected');
    if (!asset) throw new Error('airdrop funding needs the asset id');
    const locker = pool.nkToOwner(lockerNk);
    const plan = planFunding({ sources, amounts, fee });
    const denomNotes = new Array(amounts.length);
    let padCounter = 0;
    const ops = plan.map((p) => {
      const src = sources[p.sourceIndex];
      const outs = [];
      for (const d of p.denom) {
        const r = outBlinding(lockerScanPriv, 0, d.amountIndex, salt);
        const { cx, cy } = pool.commitXY(d.amount, r);
        const note = { value: d.amount, blinding: r, owner: locker, secret: lockerNk, cx, cy, role: 'denom', amountIndex: d.amountIndex };
        denomNotes[d.amountIndex] = note; outs.push(note);
      }
      const cr = outBlinding(lockerScanPriv, 1, p.sourceIndex, salt);
      const { cx: ccx, cy: ccy } = pool.commitXY(p.change, cr);
      outs.push({ value: p.change, blinding: cr, owner: locker, secret: lockerNk, cx: ccx, cy: ccy, role: 'change' });
      for (let j = 0; j < p.pad; j++) {
        const pr = outBlinding(lockerScanPriv, 2, padCounter++, salt);
        const { cx, cy } = pool.commitXY(0n, pr);
        outs.push({ value: 0n, blinding: pr, owner: locker, secret: lockerNk, cx, cy, role: 'pad' });
      }
      const t = transfer.buildTransfer({
        inputs: [{ value: BigInt(src.value), blinding: BigInt(src.blinding) }],
        outputs: outs.map((o) => ({ value: o.value, blinding: o.blinding, owner: o.owner })), fee: p.fee,
        assetId: asset,
        domain: 'transfer',
      });
      return { sourceIndex: p.sourceIndex, ...t,
        source: { cx: src.cx, cy: src.cy, owner: locker, leafIndex: src.leafIndex, path: src.path, blinding: src.blinding },
        outNotes: outs };
    });
    return { ops, denomNotes };
  }

  function fundingNotesFor({ denomNotes, membership }) {
    return denomNotes.map((d, i) => ({ cx: d.cx, cy: d.cy, blinding: d.blinding, secret: d.secret, leafIndex: membership[i].leafIndex, path: membership[i].path }));
  }

  async function runAirdrop({ chainBinding, asset, lockerNk, lockerScanPriv, deadline, spendRoot, recipients, sources, fee = 0n, salt = '0x' + '00'.repeat(32), settleSplit, indexDenoms, settleLocks }) {
    const funding = buildFunding({ asset, sources, amounts: recipients.map((r) => r.amount), lockerNk, lockerScanPriv, fee, salt });
    await settleSplit(funding.ops);
    const membership = await indexDenoms(funding.denomNotes);
    const fundingNotes = fundingNotesFor({ denomNotes: funding.denomNotes, membership });
    const drop = buildAirdrop({ chainBinding, asset, lockerNk, lockerScanPriv, deadline, spendRoot, recipients, fundingNotes, salt });
    await settleLocks(drop);
    return { funding, drop };
  }

  function packStealthLockBatch(ops) {
    if (!ops.length) throw new Error('airdrop batch: no ops');
    const { chainBinding, spendRoot } = ops[0];
    for (const o of ops) {
      if (o.chainBinding !== chainBinding || o.spendRoot !== spendRoot) {
        throw new Error('airdrop batch: every lock must share chainBinding + spendRoot (one proof, one header)');
      }
    }
    const pick = (o) => ({ asset: o.asset, locker: o.locker, ownerPub: o.ownerPub, refundPub: o.refundPub, deadline: o.deadline,
      nCx: o.nCx, nCy: o.nCy, nIndex: o.nIndex, nPath: o.nPath, nk: o.nk,
      lCx: o.lCx, lCy: o.lCy, kernelR: o.kernelR, kernelZ: o.kernelZ,
      inPokR: o.inPokR, inPokZv: o.inPokZv, inPokZr: o.inPokZr });
    return { chainBinding, spendRoot, ops: ops.map(pick) };
  }

  return { buildAirdrop, scanAirdrop, sealStealthMemo, openStealthMemo, sealStealthSenderTail, openStealthSenderTail,
    ephPriv, lockBlinding, refundPriv, refundPubOf,
    planFunding, buildFunding, fundingNotesFor, runAirdrop, packStealthLockBatch };
}
