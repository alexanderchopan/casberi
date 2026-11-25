
import { randomScalar } from './bulletproofs-plus.js';

export function makeConfidentialDefiActions({ pool, cdp, farm, relay, id, chainBindingHex, secp, ephRand = randomScalar }) {
  const ZERO = '0x' + '00'.repeat(32);
  const owned = ({ value, blinding, asset, cx, cy, owner, secret }) => {
    if (owner == null || secret == null) throw new Error('defi: a minted note needs its own fresh nk and owner');
    if (String(pool.nkToOwner(secret)).toLowerCase() !== String(owner).toLowerCase()) throw new Error('defi: minted note owner is not H(nk)');
    return { value: value.toString(), blinding, secret, asset, owner, cx, cy, ownerPub: id.pubHex };
  };

  const ZERO32 = '0x' + '00'.repeat(32);
  async function openCdp({ controller, debtValue, rateSnapshot, fee = 0n, collateral, spendRoot, debtBlinding, positionOwner, debtNk, acknowledgeFeeShortfall = false, selfSettle = null, waitOpts }) {
    if (!positionOwner) throw new Error('openCdp: positionOwner (fresh per-position owner) is required');
    if (BigInt(debtValue) > 0n && !debtNk) throw new Error('openCdp: debtNk (fresh secret for the minted debt note) is required when debtValue > 0');
    const pOwner = positionOwner;
    const debtOwner = BigInt(debtValue) > 0n ? pool.nkToOwner(debtNk) : null;
    const op = cdp.buildCdpMintOp({ chainBinding: chainBindingHex(), controller, owner: pOwner, debtOwner, debtValue, nonce: ZERO32, rateSnapshot, fee, collateral, spendRoot, debtBlinding, acknowledgeFeeShortfall });
    let leaves = [], outputs = [];
    if (BigInt(debtValue) > 0n) {
      const debtAsset = cdp.debtAssetId(controller);
      leaves = [pool.leaf(debtAsset, op.debt.cx, op.debt.cy, debtOwner)];
      outputs = [owned({ value: BigInt(debtValue) - BigInt(fee), blinding: debtBlinding, asset: debtAsset, cx: op.debt.cx, cy: op.debt.cy, owner: debtOwner, secret: debtNk })];
    }
    return settleVia({ type: 'cdpmint', op, leaves, outputs, ephRand }, selfSettle, waitOpts);
  }

  async function proveWrapCdpMint({ controller, debtValue, rateSnapshot, deposits, debtBlinding, positionOwner, debtNk, waitOpts }) {
    if (!positionOwner) throw new Error('wrapCdpMint: positionOwner (fresh per-position owner) is required');
    if (!debtNk) throw new Error('wrapCdpMint: debtNk (fresh secret for the minted debt note) is required');
    const debtOwner = pool.nkToOwner(debtNk);
    const withBlinding = deposits.map((d) => ({ ...d, blinding: d.blinding ?? '0x' + randomScalar().toString(16).padStart(64, '0') }));
    const { commits, ...op } = cdp.buildWrapCdpMintOp({ chainBinding: chainBindingHex(), controller, owner: positionOwner, debtOwner, debtValue, nonce: ZERO32, rateSnapshot, fee: 0n, deposits: withBlinding, debtBlinding });
    const debtAsset = cdp.debtAssetId(controller);
    const leaves = [pool.leaf(debtAsset, op.debt.cx, op.debt.cy, debtOwner)];
    const outputs = [owned({ value: BigInt(debtValue), blinding: debtBlinding, asset: debtAsset, cx: op.debt.cx, cy: op.debt.cy, owner: debtOwner, secret: debtNk })];
    const proven = await relay.prove({ type: 'wrapcdpmint', op, leaves, outputs, ephRand }, waitOpts);
    if (proven.status !== 'proven' || !proven.publicValues || !proven.proof) throw new Error(`The proof did not come back (${proven.status || 'no answer'}). Nothing was sent.`);
    return { ...proven, op, commits };
  }

  async function closeCdp({ controller, debtValue, rateSnapshot, basket, positionIndex, positionPath, spendRoot, cdpPositionRoot, fee = 0n, releaseBlindings, releaseNks, debtNotes, positionOwner, positionOwnerPriv, selfSettle = null, waitOpts }) {
    if (!positionOwner || !positionOwnerPriv) throw new Error('closeCdp: positionOwner + positionOwnerPriv (the fresh per-position key) are required to authorize the close');
    const legCount = (basket || []).length;
    if (!Array.isArray(releaseNks) || releaseNks.length !== legCount) {
      throw new Error(`closeCdp: releaseNks (one fresh secret per released leg) is required — got ${Array.isArray(releaseNks) ? releaseNks.length : 0} for ${legCount} leg(s)`);
    }
    const pOwner = positionOwner;
    if (selfSettle) fee = 0n;
    const order = basket.map((leg, i) => i).sort((a, b) => (BigInt(basket[a].asset) < BigInt(basket[b].asset) ? -1 : (BigInt(basket[a].asset) > BigInt(basket[b].asset) ? 1 : 0)));
    const sortedNks = order.map((i) => releaseNks[i]);
    const sortedBlindings = order.map((i) => releaseBlindings[i]);
    const releaseOwners = sortedNks.map((nk) => pool.nkToOwner(nk));
    const op = cdp.buildCdpCloseOp({ chainBinding: chainBindingHex(), controller, owner: pOwner, ownerPriv: positionOwnerPriv, debtValue, nonce: ZERO32, rateSnapshot, basket, positionIndex, positionPath, spendRoot, cdpPositionRoot, fee, releaseBlindings: sortedBlindings, releaseOwners, debtNotes });
    const leaves = op.legs.map((leg, i) => pool.leaf(leg.asset, leg.cx, leg.cy, releaseOwners[i]));
    const outputs = op.legs.map((leg, i) => owned({ value: BigInt(leg.value) - (i === 0 ? BigInt(fee) : 0n), blinding: sortedBlindings[i], asset: leg.asset, cx: leg.cx, cy: leg.cy, owner: releaseOwners[i], secret: sortedNks[i] }));
    return settleVia({ type: 'cdpclose', op, leaves, outputs, ephRand }, selfSettle, waitOpts);
  }

  async function liquidateCdp({ controller, owner, debtValue, rateSnapshot, basket, positionIndex, positionPath, spendRoot, cdpPositionRoot, liquidator, debtNotes, fee = 0n, waitOpts }) {
    const op = cdp.buildCdpLiquidateOp({ chainBinding: chainBindingHex(), controller, owner, debtValue, nonce: ZERO32, rateSnapshot, basket, positionIndex, positionPath, spendRoot, cdpPositionRoot, liquidator, debtNotes, fee });
    const spec = { type: 'cdpliquidate', op, leaves: [], outputs: [], ephRand };
    return BigInt(fee) > 0n ? relay.settle(spec, waitOpts) : relay.prove(spec, waitOpts);
  }

  async function topupCdp({ controller, debtValue, rateSnapshot, oldBasket, addedCollateral, positionIndex, positionPath, spendRoot, cdpPositionRoot, positionOwner, positionOwnerPriv, selfSettle = null, waitOpts }) {
    if (!positionOwner || !positionOwnerPriv) throw new Error('topupCdp: positionOwner + positionOwnerPriv (the position\'s fresh key) are required to authorize the top-up');
    const op = cdp.buildCdpTopupOp({ chainBinding: chainBindingHex(), controller, owner: positionOwner, ownerPriv: positionOwnerPriv, debtValue, oldNonce: ZERO32, newNonce: ZERO32, rateSnapshot, oldBasket, addedCollateral, positionIndex, positionPath, spendRoot, cdpPositionRoot });
    return settleVia({ type: 'cdptopup', op, leaves: [], outputs: [], ephRand }, selfSettle, waitOpts);
  }

  async function mintCbtc({ outpoint, vBtc, blinding, selfSettle = null, waitOpts }) {
    const op = cdp.buildCbtcMintOp({ chainBinding: chainBindingHex(), outpoint, vBtc, blinding });
    const leaf = pool.leaf(pool.CBTC_ZK_ASSET_ID, op.cx, op.cy, ZERO);
    return settleVia({ type: 'cbtcmint', op, leaves: [leaf], outputs: [{ seedDerived: true }], ephRand }, selfSettle, waitOpts);
  }

  const controller32 = (c) => '0x' + '00'.repeat(12) + String(c).replace(/^0x/, '').slice(-40);

  async function settleVia(spec, selfSettle, waitOpts) {
    if (!selfSettle) return relay.settle(spec, waitOpts);
    if (relay.ownProving?.()) {
      const own = await relay.prove(spec, waitOpts);
      return { jobId: own.jobId, ...(await selfSettle({ jobId: own.jobId, publicValues: own.publicValues, proof: own.proof, memos: own.memos })) };
    }
    const job = await relay.submitOp({ ...spec, mode: 'prove' }, waitOpts);
    const proven = job.status === 'proven' || job.status === 'settled' ? await relay.status(job.jobId) : await relay.waitForProof(job.jobId, waitOpts);
    if (proven.status === 'settled') return { ...proven, jobId: job.jobId };
    const memos = typeof relay.provenMemos === 'function' ? relay.provenMemos(proven, spec, job.sealedMemos) : job.sealedMemos;
    return { jobId: job.jobId, ...(await selfSettle({ jobId: job.jobId, publicValues: proven.publicValues, proof: proven.proof, memos })) };
  }

  async function bondFarm({ controller, nonce, lpAsset, legs, spendRoot, receiptOwner, selfSettle = null, waitOpts }) {
    if (!receiptOwner) throw new Error('bondFarm: receiptOwner (fresh per-position BIP-340 x-only pubkey) is required');
    const op = farm.buildBondOp({ chainBinding: chainBindingHex(), spendRoot, controller, owner: receiptOwner, nonce, lpAsset, legs });
    const shares = legs.reduce((s, l) => s + BigInt(l.value), 0n);
    const receipt = pool.farmReceiptLeaf(controller32(controller), lpAsset, shares, receiptOwner, nonce);
    return settleVia({ type: 'farmbond', op, leaves: [receipt], outputs: [{ seedDerived: true }], ephRand }, selfSettle, waitOpts);
  }

  async function harvestFarm({ controller, shares, nonce, harvestNonce, reward, oldIndex, oldPath, lpAsset, rewardAsset, rewardNote, rewardNk, fee = 0n, spendRoot, receiptOwner, receiptOwnerPriv, selfSettle = null, waitOpts }) {
    if (!receiptOwner || !receiptOwnerPriv) throw new Error('harvestFarm: receiptOwner + receiptOwnerPriv (the position\'s fresh key) are required to authorize the harvest');
    if (!rewardNk) throw new Error('harvestFarm: rewardNk (fresh secret for the minted reward note) is required');
    const rewardOwner = pool.nkToOwner(rewardNk);
    const op = farm.buildHarvestOp({ chainBinding: chainBindingHex(), spendRoot, controller, owner: receiptOwner, ownerPriv: receiptOwnerPriv, rewardOwner, shares, nonce, harvestNonce, reward, oldIndex, oldPath, lpAsset, rewardAsset, rewardNote, fee });
    const rewardLeaf = pool.leaf(rewardAsset, op.rewardCx, op.rewardCy, rewardOwner);
    const outputs = [owned({ value: BigInt(reward) - BigInt(fee), blinding: rewardNote.blinding, asset: rewardAsset, cx: op.rewardCx, cy: op.rewardCy, owner: rewardOwner, secret: rewardNk })];
    return settleVia({ type: 'farmharvest', op, leaves: [rewardLeaf], outputs, ephRand }, selfSettle, waitOpts);
  }

  async function unbondFarm({ controller, shares, nonce, lpAsset, oldIndex, oldPath, releaseNote, lpNk, fee = 0n, stakeAssetRegistered = false, spendRoot, receiptOwner, receiptOwnerPriv, selfSettle = null, waitOpts }) {
    if (!receiptOwner || !receiptOwnerPriv) throw new Error('unbondFarm: receiptOwner + receiptOwnerPriv (the position\'s fresh key) are required to authorize the unbond');
    if (!lpNk) throw new Error('unbondFarm: lpNk (fresh secret for the released LP-share note) is required');
    const lpOwner = pool.nkToOwner(lpNk);
    const op = farm.buildUnbondOp({ chainBinding: chainBindingHex(), spendRoot, controller, owner: receiptOwner, ownerPriv: receiptOwnerPriv, lpOwner, shares, nonce, lpAsset, oldIndex, oldPath, releaseNote, fee, stakeAssetRegistered });
    const releaseLeaf = pool.leaf(lpAsset, releaseNote.cx, releaseNote.cy, lpOwner);
    const outputs = [owned({ value: BigInt(shares) - BigInt(fee), blinding: releaseNote.blinding, asset: lpAsset, cx: releaseNote.cx, cy: releaseNote.cy, owner: lpOwner, secret: lpNk })];
    return settleVia({ type: 'farmunbond', op, leaves: [releaseLeaf], outputs, ephRand }, selfSettle, waitOpts);
  }

  const save = (p) => bondFarm(p);
  const harvestSavings = (p) => harvestFarm(p);
  const withdrawSavings = (p) => unbondFarm(p);

  return { openCdp, proveWrapCdpMint, closeCdp, liquidateCdp, topupCdp, mintCbtc, bondFarm, harvestFarm, unbondFarm, save, harvestSavings, withdrawSavings };
}
