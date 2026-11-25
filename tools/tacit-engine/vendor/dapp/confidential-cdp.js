
const TREE_DEPTH = 32;

export function makeConfidentialCdp({ keccak256, pool, signSchnorr }) {
  const enc = new TextEncoder();
  const CDP_EVENT_TOPIC0 = {
    CdpMinted: '0x' + [...keccak256(enc.encode('CdpMinted(bytes32,uint256,uint256)'))].map((x) => x.toString(16).padStart(2, '0')).join(''),
    CdpClosed: '0x' + [...keccak256(enc.encode('CdpClosed(bytes32,uint256)'))].map((x) => x.toString(16).padStart(2, '0')).join(''),
    CdpLiquidated: '0x' + [...keccak256(enc.encode('CdpLiquidated(bytes32,uint256,uint256)'))].map((x) => x.toString(16).padStart(2, '0')).join(''),
  };
  const CDP_POSITION_DOMAIN = enc.encode('tacit-cdp-position-v1');
  const CDP_DEBT_DOMAIN = enc.encode('tacit-cdp-debt-v1');
  const CDP_CLOSE_DOMAIN = enc.encode('tacit-cdp-close-auth-v1');
  const CDP_TOPUP_DOMAIN = enc.encode('tacit-cdp-topup-auth-v1');
  const SPENT = enc.encode('spent');

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
  const addr20 = (a) => bN(a, 20);
  const be = (v, n) => {
    let x = BigInt(v);
    const o = new Uint8Array(n);
    for (let i = n - 1; i >= 0; i--) { o[i] = Number(x & 0xffn); x >>= 8n; }
    return o;
  };
  const k = (...parts) => keccak256(concat(parts));

  const debtAssetId = (controller) => hx(k(CDP_DEBT_DOMAIN, addr20(controller)));

  const basketLeg = (asset, value) => hx(k(b32(asset), be(value, 32)));

  const basketRoot = (legsHex) => {
    const zeros = [];
    { let z = new Uint8Array(32); for (let i = 0; i < TREE_DEPTH; i++) { zeros.push(z); z = keccak256(concat([z, z])); } }
    if (legsHex.length === 0) {
      let h = new Uint8Array(32);
      for (let i = 0; i < TREE_DEPTH; i++) h = keccak256(concat([h, h]));
      return hx(h);
    }
    let level = legsHex.map(b32);
    for (let i = 0; i < TREE_DEPTH; i++) {
      const next = [];
      for (let j = 0; j * 2 < level.length; j++) {
        const l = level[2 * j];
        const r = 2 * j + 1 < level.length ? level[2 * j + 1] : zeros[i];
        next.push(keccak256(concat([l, r])));
      }
      level = next;
    }
    return hx(level[0]);
  };

  const positionLeaf = (controller, debtAsset, basketRootHex, debtValue, rateSnapshot, owner, nonce) =>
    hx(k(CDP_POSITION_DOMAIN, addr20(controller), b32(debtAsset), b32(basketRootHex), be(debtValue, 32),
      b32(rateSnapshot), b32(owner), b32(nonce)));

  const positionNullifier = (leafHex) => hx(k(CDP_POSITION_DOMAIN, b32(leafHex), SPENT));

  const cbtcMintCommitment = (cx, cy) => hx(k(b32(cx), b32(cy)));

  const sigma = (domain, chainBinding, asset, bind, note, amounts, label, extraNotes = []) => {
    if (!pool) throw new Error('opening sigma requires the confidential-pool helper');
    const notes = [[note.cx, note.cy, note.owner], ...extraNotes];
    const ctx = pool.intentContext(domain, chainBinding, asset, bind, notes, amounts.map(BigInt));
    const nonce = pool.deriveOpeningNonce(note.blinding, ctx, label);
    const sig = pool.openingSigma(BigInt(note.value), note.blinding, ctx, nonce);
    return { sigR: sig.R, sigZ: sig.z };
  };
  const controllerWord = (controller) => hx(concat([new Uint8Array(12), addr20(controller)]));
  const cdpMintCollateralSigma = ({ chainBinding, controller, nonce, owner, asset, note, debtValue, index, rateSnapshot, fee = 0n, debtCx, debtCy, debtOwner, nLegs }) => {
    if (nLegs == null) throw new Error('cdp-mint collateral sigma: nLegs (basket size) is required');
    return sigma('tacit-cdp-mint-collateral-v1', chainBinding, asset, nonce, note,
      [note.value, debtValue, index, fee, nLegs], 'cdp-mint-collateral',
      [[controllerWord(controller), nonce, owner], [rateSnapshot, nonce, owner], [debtCx, debtCy, debtOwner]]);
  };
  const cdpMintDebtSigma = ({ chainBinding, controller, nonce, owner, note, debtValue, fee = 0n, rateSnapshot }) =>
    sigma('tacit-cdp-mint-debt-v1', chainBinding, debtAssetId(controller), nonce, note,
      [debtValue != null ? BigInt(debtValue) : BigInt(note.value), BigInt(fee)], 'cdp-mint-debt',
      [[controllerWord(controller), nonce, owner], [rateSnapshot, nonce, owner]]);
  const cdpCloseReleaseSigma = ({ chainBinding, positionLeaf: position, asset, note, value, fee = 0n }) =>
    sigma('tacit-cdp-close-release-v1', chainBinding, asset, position, note,
      [value != null ? BigInt(value) : BigInt(note.value), BigInt(fee)], 'cdp-close-release');
  const cdpCloseDebtSigma = ({ chainBinding, positionLeaf: position, debtAsset, debtValue, index, note }) =>
    sigma('tacit-cdp-close-debt-v1', chainBinding, debtAsset, position, note,
      [note.value, debtValue, index], 'cdp-close-debt');
  const cdpLiquidateDebtSigma = ({ chainBinding, positionLeaf: position, debtAsset, debtValue, index, note, liquidator, fee = 0n }) =>
    sigma('tacit-cdp-liquidate-debt-v1', chainBinding, debtAsset, position, note,
      [note.value, debtValue, index, BigInt(fee)], 'cdp-liquidate-debt',
      [[controllerWord(liquidator), hx(new Uint8Array(32)), hx(new Uint8Array(32))]]);
  const cdpTopupCollateralSigma = ({ chainBinding, oldPositionLeaf, controller, newNonce, owner, asset, note, debtValue, index }) =>
    sigma('tacit-cdp-topup-collateral-v1', chainBinding, asset, oldPositionLeaf, note,
      [note.value, debtValue, index], 'cdp-topup-collateral', [[controllerWord(controller), newNonce, owner]]);
  const cbtcMintSigma = ({ chainBinding, cbtcAssetId, outpoint, note, vBtc, fee = 0n }) => {
    const bearer = { ...note, owner: '0x' + '00'.repeat(32) };
    return sigma('tacit-cbtc-mint-intent-v1', chainBinding, cbtcAssetId, outpoint, bearer,
      [BigInt(vBtc != null ? vBtc : note.value), BigInt(fee)], 'cbtc-mint');
  };

  const buildCdpMintOp = ({ chainBinding, controller, owner, debtOwner, debtValue, nonce, rateSnapshot, fee = 0n, collateral = [], spendRoot, debtBlinding, acknowledgeFeeShortfall = false }) => {
    if (!pool) throw new Error('buildCdpMintOp requires the confidential-pool helper');
    if (BigInt(fee) > 0n && !acknowledgeFeeShortfall) {
      throw new Error('buildCdpMintOp: a nonzero fee mints the debt note short of the recorded debtValue — the position becomes unclosable at face value. Pass acknowledgeFeeShortfall: true to proceed anyway, or mint fee-free (self-settled).');
    }
    const legsSorted = [...collateral].sort((a, b) => (BigInt(a.asset) < BigInt(b.asset) ? -1 : (BigInt(a.asset) > BigInt(b.asset) ? 1 : 0)));
    const net = BigInt(debtValue) - BigInt(fee);
    const Z32 = '0x' + '00'.repeat(32);
    const dOwner = BigInt(debtValue) > 0n ? debtOwner : owner;
    const debtC = BigInt(debtValue) > 0n ? pool.commitXY(net, debtBlinding) : { cx: Z32, cy: Z32 };
    const legs = legsSorted.map((leg) => {
      const note = { cx: leg.cx, cy: leg.cy, value: leg.value, owner, blinding: leg.blinding };
      const sig = cdpMintCollateralSigma({
        chainBinding, controller, nonce, owner, asset: leg.asset, note, debtValue,
        index: leg.leafIndex, rateSnapshot, fee, debtCx: debtC.cx, debtCy: debtC.cy, debtOwner: dOwner,
        nLegs: BigInt(legsSorted.length),
      });
      return { asset: leg.asset, cx: leg.cx, cy: leg.cy, owner: leg.owner, nk: leg.nk, value: String(BigInt(leg.value)), index: Number(leg.leafIndex), path: leg.path, sigR: sig.sigR, sigZ: sig.sigZ };
    });
    const op = { chainBinding, spendRoot, controller, owner, debtOwner: dOwner, debtValue: String(BigInt(debtValue)), nonce, rateSnapshot, legs, fee: String(BigInt(fee)) };
    if (BigInt(debtValue) > 0n) {
      const note = { cx: debtC.cx, cy: debtC.cy, value: net, owner: dOwner, blinding: debtBlinding };
      const sig = cdpMintDebtSigma({ chainBinding, controller, nonce, owner, note, debtValue, fee, rateSnapshot });
      op.debt = { cx: debtC.cx, cy: debtC.cy, sigR: sig.sigR, sigZ: sig.sigZ };
    }
    return op;
  };

  const buildWrapCdpMintOp = ({ chainBinding, controller, owner, debtOwner, debtValue, nonce, rateSnapshot, fee = 0n, deposits = [], debtBlinding, acknowledgeFeeShortfall = false }) => {
    if (!pool) throw new Error('buildWrapCdpMintOp requires the confidential-pool helper');
    if (BigInt(debtValue) <= 0n) throw new Error('buildWrapCdpMintOp: a wrap-and-borrow mints a debt note (use a plain wrap for a deposit alone)');
    if (!debtOwner) throw new Error('buildWrapCdpMintOp: debtOwner (H of the debt note\'s secret) is required');
    if (BigInt(nonce) !== 0n) throw new Error('buildWrapCdpMintOp: the position nonce must be 0 (keeper-liquidatable)');
    if (!deposits.length) throw new Error('buildWrapCdpMintOp: at least one deposit');
    if (BigInt(fee) > 0n && !acknowledgeFeeShortfall) {
      throw new Error('buildWrapCdpMintOp: a nonzero fee mints the debt note short of the recorded debtValue — the position becomes unclosable at face value. Pass acknowledgeFeeShortfall: true to proceed anyway, or mint fee-free.');
    }
    const legsSorted = [...deposits].sort((a, b) => (BigInt(a.asset) < BigInt(b.asset) ? -1 : (BigInt(a.asset) > BigInt(b.asset) ? 1 : 0)));
    for (let i = 0; i < legsSorted.length; i++) {
      if (BigInt(legsSorted[i].value) <= 0n) throw new Error('buildWrapCdpMintOp: a deposit of zero value');
      if (i > 0 && BigInt(legsSorted[i].asset) === BigInt(legsSorted[i - 1].asset)) throw new Error('buildWrapCdpMintOp: one deposit per asset (the basket is strictly asset-sorted)');
    }
    const net = BigInt(debtValue) - BigInt(fee);
    const debtC = pool.commitXY(net, debtBlinding);
    const legs = legsSorted.map((d) => {
      const value = BigInt(d.value), { cx, cy } = pool.commitXY(value, d.blinding);
      const depositId = pool.depositId(d.asset, value, cx, cy, owner);
      const sig = sigma('tacit-wrap-cdp-mint-collateral-v1', chainBinding, d.asset, depositId, { cx, cy, owner, value, blinding: d.blinding },
        [value, BigInt(debtValue), BigInt(fee), BigInt(legsSorted.length)], 'wrap',
        [[controllerWord(controller), nonce, owner], [rateSnapshot, nonce, owner], [debtC.cx, debtC.cy, debtOwner]]);
      return { asset: d.asset, value: String(value), cx, cy, sigR: sig.sigR, sigZ: sig.sigZ, depositId, commit: pool.depositCommit(cx, cy, owner) };
    });
    const dsig = cdpMintDebtSigma({ chainBinding, controller, nonce, owner, note: { cx: debtC.cx, cy: debtC.cy, value: net, owner: debtOwner, blinding: debtBlinding }, debtValue, fee, rateSnapshot });
    return {
      chainBinding, controller, owner, debtValue: String(BigInt(debtValue)), nonce, rateSnapshot, fee: String(BigInt(fee)),
      debt: { cx: debtC.cx, cy: debtC.cy, debtOwner, sigR: dsig.sigR, sigZ: dsig.sigZ },
      legs: legs.map(({ asset, value, cx, cy, sigR, sigZ }) => ({ asset, value, cx, cy, sigR, sigZ })),
      depositIds: legs.map((l) => l.depositId),
      commits: legs.map((l) => l.commit),
    };
  };

  const buildCdpCloseOp = ({ chainBinding, controller, owner, ownerPriv, debtValue, nonce, rateSnapshot, basket = [], positionIndex, positionPath, spendRoot, cdpPositionRoot, fee = 0n, releaseBlindings = [], releaseOwners = [], debtNotes = [] }) => {
    if (!pool) throw new Error('buildCdpCloseOp requires the confidential-pool helper');
    if (!signSchnorr || !ownerPriv) throw new Error('buildCdpCloseOp requires ownerPriv + signSchnorr (owner-authorized close)');
    const debtAsset = debtAssetId(controller);
    const sortedBasket = [...basket].sort((a, b) => (BigInt(a.asset) < BigInt(b.asset) ? -1 : (BigInt(a.asset) > BigInt(b.asset) ? 1 : 0)));
    const basketRootHex = basketRoot(sortedBasket.map((leg) => basketLeg(leg.asset, leg.value)));
    const position = positionLeaf(controller, debtAsset, basketRootHex, debtValue, rateSnapshot, owner, nonce);
    const legs = sortedBasket.map((leg, i) => {
      const legFee = i === 0 ? BigInt(fee) : 0n;
      const net = BigInt(leg.value) - legFee;
      const { cx, cy } = pool.commitXY(net, releaseBlindings[i]);
      const relOwner = releaseOwners[i];
      const note = { cx, cy, value: net, owner: relOwner, blinding: releaseBlindings[i] };
      const sig = cdpCloseReleaseSigma({ chainBinding, positionLeaf: position, asset: leg.asset, note, value: leg.value, fee: legFee });
      return { asset: leg.asset, value: String(BigInt(leg.value)), cx, cy, owner: relOwner, sigR: sig.sigR, sigZ: sig.sigZ };
    });
    const debts = debtNotes.map((d) => {
      const dOwner = d.owner ?? owner;
      const note = { cx: d.cx, cy: d.cy, value: d.value, owner: dOwner, blinding: d.blinding };
      const sig = cdpCloseDebtSigma({ chainBinding, positionLeaf: position, debtAsset, debtValue, index: d.leafIndex, note });
      return { cx: d.cx, cy: d.cy, owner: dOwner, nk: d.nk, value: String(BigInt(d.value)), index: Number(d.leafIndex), path: d.path, sigR: sig.sigR, sigZ: sig.sigZ };
    });
    const releasedBytes = concat([
      ...legs.map((l) => concat([b32(l.asset), be(l.value, 8), b32(l.cx), b32(l.cy)])),
      be(fee, 8),
    ]);
    const ownerSig = hx(signSchnorr(k(CDP_CLOSE_DOMAIN, b32(chainBinding), b32(position), releasedBytes), b32(ownerPriv)));
    return { chainBinding, spendRoot, cdpPositionRoot, controller, owner, debtValue: String(BigInt(debtValue)), nonce, rateSnapshot, positionIndex: Number(positionIndex), positionPath, legs, fee: String(BigInt(fee)), debts, ownerSig };
  };

  const buildCdpLiquidateOp = ({ chainBinding, controller, owner, debtValue, nonce, rateSnapshot, basket = [], positionIndex, positionPath, spendRoot, cdpPositionRoot, liquidator, debtNotes = [], fee = 0n }) => {
    if (!pool) throw new Error('buildCdpLiquidateOp requires the confidential-pool helper');
    const debtAsset = debtAssetId(controller);
    const sortedBasket = [...basket].sort((a, b) => (BigInt(a.asset) < BigInt(b.asset) ? -1 : (BigInt(a.asset) > BigInt(b.asset) ? 1 : 0)));
    const basketRootHex = basketRoot(sortedBasket.map((leg) => basketLeg(leg.asset, leg.value)));
    const position = positionLeaf(controller, debtAsset, basketRootHex, debtValue, rateSnapshot, owner, nonce);
    const debts = debtNotes.map((d) => {
      const dOwner = d.owner ?? owner;
      const note = { cx: d.cx, cy: d.cy, value: d.value, owner: dOwner, blinding: d.blinding };
      const sig = cdpLiquidateDebtSigma({ chainBinding, positionLeaf: position, debtAsset, debtValue, index: d.leafIndex, note, liquidator, fee });
      return { cx: d.cx, cy: d.cy, owner: dOwner, nk: d.nk, value: String(BigInt(d.value)), index: Number(d.leafIndex), path: d.path, sigR: sig.sigR, sigZ: sig.sigZ };
    });
    return {
      chainBinding, spendRoot, cdpPositionRoot, controller, owner, debtValue: String(BigInt(debtValue)), nonce,
      rateSnapshot, liquidator, positionIndex: Number(positionIndex), positionPath, fee: String(BigInt(fee)),
      legs: sortedBasket.map((leg) => ({ asset: leg.asset, value: String(BigInt(leg.value)) })), debts,
    };
  };

  const buildCbtcMintOp = ({ chainBinding, outpoint, vBtc, blinding, fee = 0n }) => {
    if (!pool) throw new Error('buildCbtcMintOp requires the confidential-pool helper');
    if (BigInt(fee) >= BigInt(vBtc)) throw new Error('buildCbtcMintOp: fee must be < vBtc');
    const net = BigInt(vBtc) - BigInt(fee);
    const { cx, cy } = pool.commitXY(net, blinding);
    const sig = cbtcMintSigma({ chainBinding, cbtcAssetId: pool.CBTC_ZK_ASSET_ID, outpoint, note: { cx, cy, value: net, blinding }, vBtc, fee });
    return { chainBinding, outpoint, vBtc: String(BigInt(vBtc)), fee: String(BigInt(fee)), cx, cy, sigR: sig.sigR, sigZ: sig.sigZ };
  };

  const byAsset = (a, b) => (BigInt(a.asset) < BigInt(b.asset) ? -1 : (BigInt(a.asset) > BigInt(b.asset) ? 1 : 0));
  const buildCdpTopupOp = ({ chainBinding, controller, owner, ownerPriv, debtValue, oldNonce, newNonce, rateSnapshot, oldBasket = [], addedCollateral = [], positionIndex, positionPath, spendRoot, cdpPositionRoot }) => {
    if (!pool) throw new Error('buildCdpTopupOp requires the confidential-pool helper');
    if (!signSchnorr || !ownerPriv) throw new Error('buildCdpTopupOp requires ownerPriv + signSchnorr (owner-authorized top-up)');
    const debtAsset = debtAssetId(controller);
    const sortedOld = [...oldBasket].sort(byAsset);
    const oldBasketRootHex = basketRoot(sortedOld.map((leg) => basketLeg(leg.asset, leg.value)));
    const oldPosition = positionLeaf(controller, debtAsset, oldBasketRootHex, debtValue, rateSnapshot, owner, oldNonce);
    const addedLegs = [...addedCollateral].sort(byAsset).map((leg) => {
      const note = { cx: leg.cx, cy: leg.cy, value: leg.value, owner: leg.owner, blinding: leg.blinding };
      const sig = cdpTopupCollateralSigma({ chainBinding, oldPositionLeaf: oldPosition, controller, newNonce, owner, asset: leg.asset, note, debtValue, index: leg.leafIndex });
      return { asset: leg.asset, cx: leg.cx, cy: leg.cy, owner: leg.owner, nk: leg.nk, value: String(BigInt(leg.value)), index: Number(leg.leafIndex), path: leg.path, sigR: sig.sigR, sigZ: sig.sigZ };
    });
    const sortedAdded = [...addedCollateral].sort(byAsset);
    const sortedNew = [];
    for (let i = 0, j = 0; i < sortedOld.length || j < sortedAdded.length;) {
      const o = sortedOld[i], a = sortedAdded[j];
      if (a === undefined || (o !== undefined && BigInt(o.asset) < BigInt(a.asset))) { sortedNew.push(o); i += 1; }
      else if (o === undefined || BigInt(a.asset) < BigInt(o.asset)) { sortedNew.push(a); j += 1; }
      else { sortedNew.push({ asset: o.asset, value: BigInt(o.value) + BigInt(a.value) }); i += 1; j += 1; }
    }
    const newBasketRootHex = basketRoot(sortedNew.map((leg) => basketLeg(leg.asset, leg.value)));
    const newPosition = positionLeaf(controller, debtAsset, newBasketRootHex, debtValue, rateSnapshot, owner, newNonce);
    const addedBytes = concat([
      ...sortedNew.map((leg) => b32(basketLeg(leg.asset, leg.value))),
      be(debtValue, 8),
    ]);
    const ownerSig = hx(signSchnorr(
      k(CDP_TOPUP_DOMAIN, b32(chainBinding), b32(oldPosition), b32(positionNullifier(oldPosition)), b32(newPosition), addedBytes),
      b32(ownerPriv),
    ));
    return { chainBinding, spendRoot, cdpPositionRoot, controller, owner, debtValue: String(BigInt(debtValue)), oldNonce, newNonce, rateSnapshot, positionIndex: Number(positionIndex), positionPath, oldLegs: sortedOld.map((leg) => ({ asset: leg.asset, value: String(BigInt(leg.value)) })), addedLegs, ownerSig };
  };

  return {
    debtAssetId, basketLeg, basketRoot, positionLeaf, positionNullifier, cbtcMintCommitment,
    cdpMintCollateralSigma, cdpMintDebtSigma, cdpCloseReleaseSigma, cdpCloseDebtSigma,
    cdpLiquidateDebtSigma, cdpTopupCollateralSigma, cbtcMintSigma,
    buildCdpMintOp, buildWrapCdpMintOp, buildCdpCloseOp, buildCdpLiquidateOp, buildCbtcMintOp, buildCdpTopupOp,
    CDP_EVENT_TOPIC0,
  };
}
