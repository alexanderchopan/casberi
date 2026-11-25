export function makeBurnDepositAssembler({ dsha256, cat, bytesToHex }) {
  function merkleSiblings(txids, index) {
    const sibs = [];
    let layer = txids.map((t) => Uint8Array.from(t));
    let idx = index >>> 0;
    while (layer.length > 1) {
      const sibIdx = (idx ^ 1) < layer.length ? (idx ^ 1) : idx;
      sibs.push(bytesToHex(layer[sibIdx]));
      const next = [];
      for (let i = 0; i < layer.length; i += 2) {
        const l = layer[i];
        const r = i + 1 < layer.length ? layer[i + 1] : layer[i];
        next.push(dsha256(cat([l, r])));
      }
      layer = next;
      idx = idx >>> 1;
    }
    return sibs;
  }
  function merkleRoot(txids) {
    if (!txids.length) throw new Error('merkleRoot: empty block');
    let layer = txids.map((t) => Uint8Array.from(t));
    while (layer.length > 1) {
      const next = [];
      for (let i = 0; i < layer.length; i += 2) {
        const l = layer[i];
        const r = i + 1 < layer.length ? layer[i + 1] : layer[i];
        next.push(dsha256(cat([l, r])));
      }
      layer = next;
    }
    return bytesToHex(layer[0]);
  }

  const ZERO32 = new Uint8Array(32);
  function witnessPath(record, label) {
    if (!Array.isArray(record.blockTxids) || !Array.isArray(record.blockWtxids)) {
      throw new Error(`${label}: blockTxids and blockWtxids required`);
    }
    if (record.blockTxids.length !== record.blockWtxids.length || record.index <= 0 || record.index >= record.blockTxids.length) {
      throw new Error(`${label}: witness arrays/index invalid (protocol tx must follow coinbase)`);
    }
    if (typeof record.coinbase !== 'string' || !record.coinbase.startsWith('0x')) {
      throw new Error(`${label}: raw coinbase required`);
    }
    const wtxids = record.blockWtxids.map((x, i) => i === 0 ? ZERO32 : x);
    return {
      wtxidSiblings: merkleSiblings(wtxids, record.index),
      coinbase: record.coinbase,
      coinbaseTxidSiblings: merkleSiblings(record.blockTxids, 0),
    };
  }

  // Everything the guest needs to place one transaction in its block: its index, its txid path and the block's root,
  // its wtxid path and the coinbase that commits to the wtxid tree. Read from the whole block's txid and wtxid lists, or
  // taken as already worked out (`record.proof`, the same fields this returns), which is how a record is kept once its
  // block has been read: a few hundred bytes for good instead of the block read again.
  const isHex32 = (x) => typeof x === 'string' && /^0x[0-9a-fA-F]{64}$/.test(x);
  function inclusionOf(record, label) {
    const p = record.proof;
    if (p) {
      if (!Number.isInteger(p.index) || p.index <= 0 || !isHex32(p.confirmedBlockRoot) || typeof p.coinbase !== 'string' || !p.coinbase.startsWith('0x')
        || ![p.merkleSiblings, p.wtxidSiblings, p.coinbaseTxidSiblings].every((a) => Array.isArray(a) && a.every(isHex32))) {
        throw new Error(`${label}: inclusion proof malformed`);
      }
      return p;
    }
    const w = witnessPath(record, label);
    return {
      index: record.index, merkleSiblings: merkleSiblings(record.blockTxids, record.index), confirmedBlockRoot: merkleRoot(record.blockTxids),
      wtxidSiblings: w.wtxidSiblings, coinbase: w.coinbase, coinbaseTxidSiblings: w.coinbaseTxidSiblings,
    };
  }

  function buildBurnDepositStatic({ etch, provHeaders = [], cxfers, cmints = [], poolMemberships = [] }) {
    const ew = etch ? inclusionOf(etch, 'etch') : null;
    return {
      etchTx: etch ? etch.tx : '0x',
      etchIndex: etch ? ew.index : 0,
      etchSiblings: etch ? ew.merkleSiblings : [],
      etchWtxidSiblings: etch ? ew.wtxidSiblings : [],
      etchCoinbase: etch ? ew.coinbase : '0x',
      etchCoinbaseTxidSiblings: etch ? ew.coinbaseTxidSiblings : [],
      provHeaders,
      poolMemberships: poolMemberships.map((pm) => ({
        outpoint: pm.outpoint, cx: pm.cx, cy: pm.cy, owner: pm.owner,
        noteClass: pm.noteClass, chainBinding: pm.chainBinding, leafIndex: pm.leafIndex, path: pm.path,
      })),
      cxfers: cxfers.map((c, i) => {
        const w = inclusionOf(c, `cxfer[${i}]`);
        return {
          tx: c.tx,
          inputCommitments: c.inputs.map((x) => x.commitment),
          outputVouts: c.outputs.map((x) => x.vout),
          burnedAmount: c.burnedAmount || 0,
          inputSkip: c.inputSkip || 0,
          merkleSiblings: w.merkleSiblings,
          merkleIndex: w.index,
          confirmedBlockRoot: w.confirmedBlockRoot,
          wtxidSiblings: w.wtxidSiblings,
          coinbase: w.coinbase,
          coinbaseTxidSiblings: w.coinbaseTxidSiblings,
        };
      }),
      cmints: cmints.map((cm, i) => {
        const w = inclusionOf(cm, `cmint[${i}]`);
        return {
          revealTx: cm.revealTx,
          commitTx: cm.commitTx,
          merkleSiblings: w.merkleSiblings,
          merkleIndex: w.index,
          revealWtxidSiblings: w.wtxidSiblings,
          revealCoinbase: w.coinbase,
          revealCoinbaseTxidSiblings: w.coinbaseTxidSiblings,
        };
      }),
    };
  }

  function serializeProvenanceBlob(stat) {
    const hexToBytes = (h) => {
      h = h.startsWith('0x') ? h.slice(2) : h;
      const a = new Uint8Array(h.length / 2);
      for (let i = 0; i < a.length; i++) a[i] = parseInt(h.slice(2 * i, 2 * i + 2), 16);
      return a;
    };
    const parts = [];
    const u32 = (v) => { const b = new Uint8Array(4); b[0] = v & 0xff; b[1] = (v >>> 8) & 0xff; b[2] = (v >>> 16) & 0xff; b[3] = (v >>> 24) & 0xff; parts.push(b); };
    const u64 = (v) => { const b = new Uint8Array(8); let n = BigInt(v); for (let i = 0; i < 8; i++) { b[i] = Number(n & 0xffn); n >>= 8n; } parts.push(b); };
    const raw = (h) => { const b = hexToBytes(h); parts.push(b); return b; };
    const bytes = (h) => { const b = hexToBytes(h); u32(b.length); parts.push(b); };
    const fixed = (h, n) => { const b = hexToBytes(h); if (b.length !== n) throw new Error(`blob: expected ${n} bytes`); parts.push(b); };
    const v32 = (arr) => { u32(arr.length); for (const x of arr) fixed(x, 32); };
    const v33 = (arr) => { u32(arr.length); for (const x of arr) fixed(x, 33); };
    const vu32 = (arr) => { u32(arr.length); for (const x of arr) u32(x >>> 0); };

    bytes(stat.etchTx);
    u32(stat.etchIndex >>> 0);
    v32(stat.etchSiblings);
    v32(stat.etchWtxidSiblings);
    bytes(stat.etchCoinbase);
    v32(stat.etchCoinbaseTxidSiblings);
    u32(stat.cmints.length);
    for (const c of stat.cmints) {
      bytes(c.revealTx);
      bytes(c.commitTx);
      v32(c.merkleSiblings);
      u32(c.merkleIndex >>> 0);
      v32(c.revealWtxidSiblings);
      bytes(c.revealCoinbase);
      v32(c.revealCoinbaseTxidSiblings);
    }
    u32(stat.cxfers.length);
    for (const p of stat.cxfers) {
      bytes(p.tx);
      v33(p.inputCommitments);
      vu32(p.outputVouts);
      u64(p.burnedAmount || 0);
      u32((p.inputSkip || 0) >>> 0);
      u32(p.merkleIndex >>> 0);
      v32(p.merkleSiblings);
      fixed(p.confirmedBlockRoot, 32);
      v32(p.wtxidSiblings);
      bytes(p.coinbase);
      v32(p.coinbaseTxidSiblings);
    }
    const pms = stat.poolMemberships || [];
    u32(pms.length);
    for (const m of pms) {
      fixed(m.outpoint, 32);
      fixed(m.cx, 32);
      fixed(m.cy, 32);
      fixed(m.owner, 32);
      u32(m.noteClass >>> 0);
      fixed(m.chainBinding, 32);
      u64(m.leafIndex);
      v32(m.path);
    }
    return cat(parts);
  }

  function assembleBurnDeposit({ burnWtxidSiblings, burnCbTxidSiblings, burned, burnedNoteLeaf, burnedTxid, burnedVout, nu, dest, target, scanState, provHeaders, blob }) {
    return {
      burnWtxidSiblings,
      burnCbTxidSiblings,
      burnedCx: burned.cx,
      burnedCy: burned.cy,
      ...scanState.foldBurnDepositCore(burnedTxid, burnedVout, burnedNoteLeaf, dest, nu, target),
      provHeaders: provHeaders || [],
      blob: blob || '0x',
    };
  }

  return { assembleBurnDeposit, buildBurnDepositStatic, serializeProvenanceBlob, merkleSiblings, merkleRoot, witnessPath, inclusionOf };
}
