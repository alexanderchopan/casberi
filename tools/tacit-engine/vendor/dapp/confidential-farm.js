
import { signSchnorr } from './bulletproofs.js';
import { secp } from './vendor/tacit-deps.min.js';

export function makeConfidentialFarm({ keccak256, pool }) {
  const enc = new TextEncoder();
  const CDP_DEBT_DOMAIN = enc.encode('tacit-cdp-debt-v1');

  const isValidXonly = (ownerHex) => {
    try { secp.ProjectivePoint.fromHex('02' + String(ownerHex).replace(/^0x/, '')); return true; } catch { return false; }
  };

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
  const addr20 = (a) => bN(a, 20);
  const k = (...parts) => keccak256(concat(parts));
  const priv32 = (p) => (p instanceof Uint8Array ? p : bN(p, 32));

  const debtAssetId = (controller) => hx(k(CDP_DEBT_DOMAIN, addr20(controller)));
  const controllerWord = (controller) => hx(concat([new Uint8Array(12), addr20(controller)]));

  const sigma = (domain, chainBinding, asset, bind, note, amounts, label, extraNotes = []) => {
    if (!pool) throw new Error('opening sigma requires the confidential-pool helper');
    const notes = [[note.cx, note.cy, note.owner], ...extraNotes];
    const ctx = pool.intentContext(domain, chainBinding, asset, bind, notes, amounts.map(BigInt));
    const nonce = pool.deriveOpeningNonce(note.blinding, ctx, label);
    const sig = pool.openingSigma(BigInt(note.value), note.blinding, ctx, nonce);
    return { sigR: sig.R, sigZ: sig.z };
  };

  const farmBondLegSigma = ({ chainBinding, controller, nonce, owner, lpAsset, note, index, nLegs }) => {
    if (nLegs == null || BigInt(nLegs) < 1n) throw new Error('farm-bond: leg sigma needs the bond leg count');
    return sigma('tacit-farm-bond-leg-v1', chainBinding, lpAsset, nonce, note,
      [note.value, index, nLegs],
      'farm-bond-leg', [[controllerWord(controller), nonce, owner]]);
  };

  const farmHarvestRewardSigma = ({ chainBinding, rewardAsset, harvestNonce, note, reward, fee = 0n }) =>
    sigma('tacit-farm-harvest-reward-v1', chainBinding, rewardAsset, harvestNonce, note,
      [reward != null ? BigInt(reward) : BigInt(note.value), BigInt(fee)], 'farm-harvest-reward');

  const farmUnbondReleaseSigma = ({ chainBinding, lpAsset, nonce, note, shares, fee = 0n }) =>
    sigma('tacit-farm-unbond-release-v1', chainBinding, lpAsset, nonce, note,
      [shares != null ? BigInt(shares) : BigInt(note.value), BigInt(fee)], 'farm-unbond-release');

  const buildBondOp = ({ chainBinding, spendRoot, controller, owner, nonce, lpAsset, legs }) => {
    if (!isValidXonly(owner)) throw new Error('farm bond: owner is not a valid x-only public key');
    return {
      chainBinding, spendRoot, controller, owner, nonce, lpAsset,
      legs: legs.map((leg) => {
        const note = { cx: leg.cx, cy: leg.cy, owner, value: leg.value, blinding: leg.blinding };
        const sig = farmBondLegSigma({ chainBinding, controller, nonce, owner, lpAsset, note, index: leg.index, nLegs: legs.length });
        return { cx: leg.cx, cy: leg.cy, value: leg.value, index: leg.index, path: leg.path, sigR: sig.sigR, sigZ: sig.sigZ, owner: leg.owner, nk: leg.nk };
      }),
    };
  };

  const buildHarvestOp = ({ chainBinding, spendRoot, controller, owner, ownerPriv, rewardOwner, shares, nonce, harvestNonce, reward, oldIndex, oldPath, lpAsset, rewardAsset, rewardNote, fee = 0n }) => {
    const f = BigInt(fee);
    if (f > BigInt(reward)) throw new Error('farm-harvest: fee exceeds reward');
    const note = { cx: rewardNote.cx, cy: rewardNote.cy, owner: rewardOwner, value: BigInt(reward) - f, blinding: rewardNote.blinding };
    const sig = farmHarvestRewardSigma({ chainBinding, rewardAsset, harvestNonce, note, reward, fee: f });
    const farmId = controllerWord(controller);
    const receipt = pool.farmReceiptLeaf(farmId, lpAsset, shares, owner, nonce);
    const ownerMsg = pool.evmLpHarvestOwnerMsg({ farmId, oldLeaf: receipt, reward: BigInt(reward), fee: f, newNonce: harvestNonce, rewardAsset, rewardCx: rewardNote.cx, rewardCy: rewardNote.cy, rewardOwner });
    const ownerSig = hx(signSchnorr(ownerMsg, priv32(ownerPriv)));
    return {
      chainBinding, spendRoot, controller, owner, rewardOwner, shares,
      nonce, harvestNonce, reward, fee: Number(f), lpAsset, oldIndex, oldPath, rewardAsset,
      rewardCx: rewardNote.cx, rewardCy: rewardNote.cy, sigR: sig.sigR, sigZ: sig.sigZ, ownerSig,
    };
  };

  const buildUnbondOp = ({ chainBinding, spendRoot, controller, owner, ownerPriv, lpOwner, shares, nonce, lpAsset, oldIndex, oldPath, releaseNote, fee = 0n, stakeAssetRegistered = false }) => {
    if (BigInt(fee) !== 0n && !stakeAssetRegistered) {
      throw new Error('farm-unbond: a relay fee is payable only for a pool-registered stake asset (an AMM LP-share id is not registered — self-settle with fee = 0, or pass stakeAssetRegistered after checking assets(lpAsset).registered)');
    }
    const f = BigInt(fee);
    if (f > BigInt(shares)) throw new Error('farm-unbond: fee exceeds shares');
    const note = { cx: releaseNote.cx, cy: releaseNote.cy, owner: lpOwner, value: BigInt(shares) - f, blinding: releaseNote.blinding };
    const sig = farmUnbondReleaseSigma({ chainBinding, lpAsset, nonce, note, shares, fee: f });
    const farmId = controllerWord(controller);
    const receipt = pool.farmReceiptLeaf(farmId, lpAsset, shares, owner, nonce);
    const ownerMsg = pool.evmLpUnbondOwnerMsg({ farmId, receipt, shares: BigInt(shares), fee: f, lpAsset, releaseCx: releaseNote.cx, releaseCy: releaseNote.cy, releaseOwner: lpOwner });
    const ownerSig = hx(signSchnorr(ownerMsg, priv32(ownerPriv)));
    return {
      chainBinding, spendRoot, controller, owner, lpOwner, shares, nonce, lpAsset,
      oldIndex, oldPath, fee: Number(f), releaseCx: releaseNote.cx, releaseCy: releaseNote.cy, sigR: sig.sigR, sigZ: sig.sigZ, ownerSig,
    };
  };

  return {
    debtAssetId,
    farmReceiptLeaf: pool.farmReceiptLeaf,
    farmReceiptNullifier: pool.farmReceiptNullifier,
    farmBondLegSigma, farmHarvestRewardSigma, farmUnbondReleaseSigma,
    buildBondOp, buildHarvestOp, buildUnbondOp,
  };
}
