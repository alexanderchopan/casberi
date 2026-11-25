
import { makeConfidentialPool, isLegacyBridgeAsset } from './confidential-pool.js';
import { verifySchnorr, signSchnorr, pedersenCommit, pointToBytes, bigintToBytes32, modN, bpRangeVerify, bpRangeVerifyBatch, bpClassicProofLen } from './bulletproofs.js';
import { bppRangeVerify, bppRangeVerifyBatch, bytesToPoint as bppPoint, bppRangeProve } from './bulletproofs-plus.js';
import { sha256 as _sha256 } from './vendor/tacit-deps.min.js';
import { makeBurnDepositProvenance } from './burn-deposit-provenance.js';
import { makeBurnDepositAssembler } from './burn-deposit-assembler.js';

const strip = (h) => (h.startsWith('0x') ? h.slice(2) : h);
const hexToBytes = (h) => {
  h = strip(h);
  const a = new Uint8Array(h.length / 2);
  for (let i = 0; i < a.length; i++) a[i] = parseInt(h.slice(2 * i, 2 * i + 2), 16);
  return a;
};
const bytesToHex = (b) => '0x' + [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
const cat = (arrs) => {
  const t = arrs.reduce((n, a) => n + a.length, 0);
  const o = new Uint8Array(t);
  let off = 0;
  for (const a of arrs) { o.set(a, off); off += a.length; }
  return o;
};

function readVarint(d, pos) {
  if (pos >= d.length) return null;
  const f = d[pos];
  if (f < 0xfd) return [f, 1];
  if (f === 0xfd) { if (pos + 2 >= d.length) return null; return [d[pos + 1] | (d[pos + 2] << 8), 3]; }
  if (f === 0xfe) { if (pos + 4 >= d.length) return null; return [(d[pos + 1] | (d[pos + 2] << 8) | (d[pos + 3] << 16) | (d[pos + 4] * 0x1000000)) >>> 0, 5]; }
  if (pos + 8 >= d.length) return null;
  let v = 0;
  for (let i = 0; i < 8; i++) v += d[pos + 1 + i] * 2 ** (8 * i);
  return [v, 9];
}

function nonwitnessTxExactLen(tx) {
  if (tx.length < 4) return false;
  let pos = 4;
  let r = readVarint(tx, pos); if (!r) return false; const inCount = r[0]; if (inCount === 0) return false; pos += r[1];
  for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return false; pos += r[1] + r[0] + 4; }
  r = readVarint(tx, pos); if (!r) return false; const outCount = r[0]; if (outCount === 0) return false; pos += r[1];
  for (let i = 0; i < outCount; i++) { pos += 8; r = readVarint(tx, pos); if (!r) return false; pos += r[1] + r[0]; }
  pos += 4;
  return pos === tx.length;
}
function makeComputeTxidBytes(dsha) {
  return function computeTxidBytes(tx) {
    const segwit = tx.length > 5 && tx[4] === 0x00 && tx[5] === 0x01;
    if (tx.length === 64 && !segwit && !nonwitnessTxExactLen(tx)) return null;
    if (!segwit) return dsha(tx);
    const version = tx.subarray(0, 4);
    let pos = 6;
    const inputsStart = pos;
    let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; if (inCount === 0) return null; pos += r[1];
    for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
    r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; if (outCount === 0) return null; pos += r[1];
    for (let i = 0; i < outCount; i++) { pos += 8; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0]; }
    const outputsEnd = pos;
    for (let i = 0; i < inCount; i++) {
      r = readVarint(tx, pos); if (!r) return null; const wc = r[0]; pos += r[1];
      for (let j = 0; j < wc; j++) { r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0]; }
    }
    if (outputsEnd > tx.length || pos + 4 !== tx.length) return null;
    const locktime = tx.subarray(pos, pos + 4);
    const stripped = cat([version, tx.subarray(inputsStart, outputsEnd), locktime]);
    if (stripped.length === 64 && !nonwitnessTxExactLen(stripped)) return null;
    return dsha(stripped);
  };
}

function extractInputs(txHex) {
  const tx = hexToBytes(txHex);
  if (tx.length < 5) return null;
  let pos = 4;
  if (tx[4] === 0x00 && tx.length >= 6 && tx[5] === 0x01) pos = 6;
  let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; if (inCount === 0) return null; pos += r[1];
  const inputs = [];
  for (let i = 0; i < inCount; i++) {
    if (pos + 36 > tx.length) return null;
    const txid = tx.subarray(pos, pos + 32);
    const vout = (tx[pos + 32] | (tx[pos + 33] << 8) | (tx[pos + 34] << 16) | (tx[pos + 35] * 0x1000000)) >>> 0;
    inputs.push({ prevTxid: bytesToHex(txid), prevVout: vout });
    pos += 36;
    r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4;
  }
  return inputs;
}

function isStrictDerSigWithSighash(sig) {
  if (!sig || sig.length < 9 || sig.length > 73 || sig[0] !== 0x30) return false;
  if (sig[1] !== sig.length - 3) return false;
  if (sig[2] !== 0x02) return false;
  const rlen = sig[3];
  if (rlen === 0 || 4 + rlen + 2 > sig.length) return false;
  if (sig[4 + rlen] !== 0x02) return false;
  const slen = sig[5 + rlen];
  if (slen === 0) return false;
  return 6 + rlen + slen === sig.length - 1;
}

function inputFirstWitnessItem(txHex, vinIndex) {
  const tx = hexToBytes(txHex);
  if (tx.length < 6 || tx[4] !== 0x00 || tx[5] !== 0x01) return null;
  let pos = 6;
  let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; if (inCount === 0 || vinIndex >= inCount) return null; pos += r[1];
  for (let i = 0; i < inCount; i++) {
    pos += 36; if (pos > tx.length) return null;
    r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4;
  }
  r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
  for (let i = 0; i < outCount; i++) {
    pos += 8; if (pos > tx.length) return null;
    r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0];
  }
  for (let i = 0; i < inCount; i++) {
    r = readVarint(tx, pos); if (!r) return null; const itemCount = r[0]; pos += r[1];
    if (i === vinIndex) {
      if (itemCount !== 1 && itemCount !== 2) return null;
      r = readVarint(tx, pos); if (!r) return null; const ilen = r[0]; pos += r[1];
      const end = pos + ilen; if (end > tx.length) return null;
      const sig = tx.subarray(pos, end);
      if (itemCount === 1) return sig;
      r = readVarint(tx, end); if (!r) return null; const plen = r[0]; const pkStart = end + r[1];
      const pkEnd = pkStart + plen; if (pkEnd > tx.length || plen !== 33) return null;
      const pk0 = tx[pkStart]; if (pk0 !== 0x02 && pk0 !== 0x03) return null;
      if (!isStrictDerSigWithSighash(sig)) return null;
      return sig;
    }
    for (let k = 0; k < itemCount; k++) { r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0]; }
  }
  return null;
}

function sigBindsAllOutputs(sig) {
  if (!sig || sig.length === 0) return false;
  if (sig.length === 64) return true;
  return (sig[sig.length - 1] & 0x7f) === 0x01;
}

function noteSpendsBindOutputs(txHex, noteOutpoints) {
  const inputs = extractInputs(txHex);
  if (!inputs) return false;
  const strip = (h) => String(h).replace(/^0x/, '').toLowerCase();
  for (const [txid, vout] of noteOutpoints) {
    const want = strip(txid);
    const idx = inputs.findIndex((i) => strip(i.prevTxid) === want && i.prevVout === (vout >>> 0));
    if (idx < 0) return false;
    if (!sigBindsAllOutputs(inputFirstWitnessItem(txHex, idx))) return false;
  }
  return true;
}

function extractTaprootEnvelope(txHex) {
  const tx = hexToBytes(txHex);
  if (tx.length < 6 || tx[4] !== 0x00 || tx[5] !== 0x01) return null;
  let pos = 6;
  let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; if (inCount === 0) return null; pos += r[1];
  for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
  r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
  for (let i = 0; i < outCount; i++) { pos += 8; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0]; }
  r = readVarint(tx, pos); if (!r) return null; const witCount = r[0]; pos += r[1];
  if (witCount < 2) return null;
  r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0];
  r = readVarint(tx, pos); if (!r) return null; const scriptLen = r[0]; pos += r[1];
  if (pos + scriptLen > tx.length) return null;
  const script = tx.subarray(pos, pos + scriptLen);
  if (script.length < 36) return null;
  let sp = 0;
  if (script[sp] !== 32) return null; sp += 1;
  sp += 32;
  if (sp >= script.length || script[sp] !== 0xac) return null; sp += 1;
  if (sp + 1 >= script.length || script[sp] !== 0x00 || script[sp + 1] !== 0x63) return null; sp += 2;
  const chunks = [];
  while (sp < script.length) {
    if (script[sp] === 0x68) break;
    const op = script[sp]; sp += 1;
    if (op >= 1 && op <= 75) {
      if (sp + op > script.length) return null;
      chunks.push(script.subarray(sp, sp + op)); sp += op;
    } else if (op === 0x4c) {
      if (sp >= script.length) return null;
      const ln = script[sp]; sp += 1;
      if (sp + ln > script.length) return null;
      chunks.push(script.subarray(sp, sp + ln)); sp += ln;
    } else if (op === 0x4d) {
      if (sp + 1 >= script.length) return null;
      const ln = script[sp] | (script[sp + 1] << 8); sp += 2;
      if (sp + ln > script.length) return null;
      chunks.push(script.subarray(sp, sp + ln)); sp += ln;
    } else if (op === 0x4e) {
      if (sp + 3 >= script.length) return null;
      const ln = (script[sp] | (script[sp + 1] << 8) | (script[sp + 2] << 16) | (script[sp + 3] * 0x1000000)) >>> 0; sp += 4;
      if (sp + ln > script.length) return null;
      chunks.push(script.subarray(sp, sp + ln)); sp += ln;
    } else {
      return null;
    }
  }
  const payload = cat(chunks);
  const FRAME = [0x54, 0x41, 0x43, 0x49, 0x54, 0x01];
  if (payload.length <= 6 || !FRAME.every((b, i) => payload[i] === b)) return null;
  return bytesToHex(payload.subarray(6));
}

function parseCetch(envHex) {
  const env = hexToBytes(envHex);
  if (env.length < 1 || env[0] !== 0x21) return null;
  let p = 1;
  const tlen = env[p]; p += 1;
  if (tlen < 1 || tlen > 16) return null;
  p += tlen;
  if (p >= env.length) return null;
  const decimals = env[p]; p += 1;
  if (decimals > 8) return null;
  if (p + 33 + 8 + 2 > env.length) return null;
  const commitment = env.subarray(p, p + 33); p += 33;
  p += 8;
  const rpLen = env[p] | (env[p + 1] << 8); p += 2;
  const rangeProof = env.subarray(p, p + rpLen);
  p += rpLen;
  if (p + 32 > env.length) return null;
  const mintAuthority = env.subarray(p, p + 32);
  return { c0Compressed: bytesToHex(commitment), mintAuthority: bytesToHex(mintAuthority), decimals, rangeProof: bytesToHex(rangeProof) };
}

function parseCmint(envHex) {
  const env = hexToBytes(envHex);
  if (env.length < 1 + 32 + 32 + 33 + 8 + 2 || env[0] !== 0x24) return null;
  const asset = env.subarray(1, 33);
  const etchTxid = env.subarray(33, 65);
  const commitment = env.subarray(65, 98);
  const amountCt = env.subarray(98, 106);
  const rpLen = env[106] | (env[107] << 8);
  const rpStart = 108;
  const rpEnd = rpStart + rpLen;
  if (rpEnd + 64 !== env.length) return null;
  const rangeProof = env.subarray(rpStart, rpEnd);
  const issuerSig = env.subarray(rpEnd, rpEnd + 64);
  return {
    asset: bytesToHex(asset),
    etchTxid: bytesToHex(etchTxid),
    commitment: bytesToHex(commitment),
    encryptedAmount: bytesToHex(amountCt),
    rangeProof: bytesToHex(rangeProof),
    issuerSig: bytesToHex(issuerSig),
  };
}

function parseBurnEnvelope(envHex) {
  const env = hexToBytes(envHex);
  if (env.length !== 161 || env[0] !== 0x2b) return null;
  return {
    asset: bytesToHex(env.subarray(1, 33)),
    nullifier: bytesToHex(env.subarray(65, 97)),
    dest: bytesToHex(env.subarray(97, 129)),
    target: bytesToHex(env.subarray(129, 161)),
  };
}

const CXFER_OPCODES = new Set([0x22, 0x23, 0x26, 0x3c]);
function parseCxferEnvelopeFull(envHex) {
  const env = hexToBytes(envHex);
  if (!env.length || !CXFER_OPCODES.has(env[0])) return null;
  const atomic = env[0] === 0x26 || env[0] === 0x3c;
  const head = atomic ? 1 + 32 + 1 : 1 + 32;
  if (env.length < head + 64 + 1 || (atomic && env[33] === 0)) return null;
  const asset = env.subarray(1, 33);
  const kernelSig = env.subarray(head, head + 64);
  let p = head + 64;
  const n = env[p]; p += 1;
  if (![1, 2, 4, 8].includes(n) || p + n * (33 + 8) + 2 > env.length) return null;
  const commitments = [], encryptedAmounts = [];
  for (let i = 0; i < n; i++) { commitments.push(bytesToHex(env.subarray(p, p + 33))); encryptedAmounts.push(bytesToHex(env.subarray(p + 33, p + 41))); p += 33 + 8; }
  const rpLen = env[p] | (env[p + 1] << 8); p += 2;
  if (p + rpLen !== env.length) return null;
  return { asset: bytesToHex(asset), kernelSig: bytesToHex(kernelSig), commitments, encryptedAmounts, rangeProof: bytesToHex(env.subarray(p, p + rpLen)), assetInputCount: atomic ? env[33] : null };
}
function axferAssetInputCount(envHex) {
  const cx = parseCxferEnvelopeFull(envHex);
  return cx ? cx.assetInputCount : null;
}

const T_CXFER_BOUND = 0x39;
function parseCxferBoundEnvelope(envHex) {
  const env = hexToBytes(envHex);
  if (env.length < 1 + 32 + 32 + 64 + 1 || env[0] !== T_CXFER_BOUND) return null;
  const target = env.subarray(1, 33);
  const asset = env.subarray(33, 65);
  const kernelSig = env.subarray(65, 129);
  let p = 129;
  const n = env[p]; p += 1;
  if (![1, 2, 4, 8].includes(n) || p + n * (33 + 8) + 2 > env.length) return null;
  const commitments = [];
  for (let i = 0; i < n; i++) { commitments.push(bytesToHex(env.subarray(p, p + 33))); p += 33 + 8; }
  const rpLen = env[p] | (env[p + 1] << 8); p += 2;
  if (p + rpLen !== env.length) return null;
  return { target: bytesToHex(target), asset: bytesToHex(asset), kernelSig: bytesToHex(kernelSig), commitments, rangeProof: bytesToHex(env.subarray(p, p + rpLen)) };
}

function _coerce(x, n, what) {
  const b = x instanceof Uint8Array ? x : hexToBytes(x);
  if (n != null && b.length !== n) throw new Error(`${what} must be ${n} bytes`);
  return b;
}
function encodeCxferBoundEnvelope({ target, asset, kernelSig, outputs, rangeProof }) {
  const t = _coerce(target, 32, 'target_chain_binding');
  const a = _coerce(asset, 32, 'assetId');
  const ks = _coerce(kernelSig, 64, 'kernel_sig');
  if (![1, 2, 4, 8].includes(outputs.length)) throw new Error('outputs.length must be in {1,2,4,8}');
  const rp = _coerce(rangeProof, null, 'rangeProof');
  if (rp.length > 0xffff) throw new Error('rangeProof too large');
  const parts = [Uint8Array.of(T_CXFER_BOUND), t, a, ks, Uint8Array.of(outputs.length)];
  for (const o of outputs) {
    parts.push(_coerce(o.commitment, 33, 'commitment'));
    parts.push(_coerce(o.amountCt != null ? o.amountCt : new Uint8Array(8), 8, 'amount_ct'));
  }
  parts.push(Uint8Array.of(rp.length & 0xff, (rp.length >> 8) & 0xff), rp);
  return bytesToHex(cat(parts));
}

function buildTacMigration({ note, targetChainBinding, outBlinding = null, amountCt = null }) {
  if (!note || note.amount == null || note.blinding == null || !note.outpoint) {
    throw new Error('buildTacMigration: note requires { assetId, amount, blinding, outpoint }');
  }
  if (!isLegacyBridgeAsset(note.assetId)) {
    throw new Error('buildTacMigration: only the legacy TAC bridge asset can be migrated');
  }
  const target = _coerce(targetChainBinding, 32, 'targetChainBinding');
  const asset = _coerce(note.assetId, 32, 'assetId');
  const amount = BigInt(note.amount);
  const inBlinding = modN(BigInt(note.blinding));
  const txidBE = hexToBytes(note.outpoint.txid);
  if (txidBE.length !== 32) throw new Error('note.outpoint.txid must be 32 bytes');
  const vout = note.outpoint.vout >>> 0;

  let rOut = outBlinding != null ? modN(BigInt(outBlinding))
    : modN(_beToBig(_sha256(cat([
        new TextEncoder().encode('tacit-tac-migration-blinding-v1'),
        bigintToBytes32(inBlinding), target, txidBE, _voutLE(vout),
      ]))));
  const cOut = pedersenCommit(amount, rOut);
  const cOutBytes = pointToBytes(cOut);

  const kernelMsg = _kernelMsg(asset, [{ txidBE, vout }], [cOutBytes]);
  const excess = modN(rOut - inBlinding);
  const kernelSig = signSchnorr(kernelMsg, bigintToBytes32(excess));

  const rangeProof = bppRangeProve([amount], [rOut]).proof;
  const envelope = encodeCxferBoundEnvelope({
    target, asset, kernelSig,
    outputs: [{ commitment: cOutBytes, amountCt: amountCt != null ? _coerce(amountCt, 8, 'amount_ct') : new Uint8Array(8) }],
    rangeProof,
  });
  return {
    envelope,
    target: bytesToHex(target),
    asset: bytesToHex(asset),
    amount,
    inputOutpoint: { txid: note.outpoint.txid, vout },
    outCommitment: bytesToHex(cOutBytes),
    outBlinding: rOut,
    kernelSig: bytesToHex(kernelSig),
  };
}

function _voutLE(v) { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, v >>> 0, true); return b; }
function _beToBig(b) { let n = 0n; for (const x of b) n = (n << 8n) | BigInt(x); return n; }
function _kernelMsg(asset, inputs, outCommitments) {
  const parts = [new TextEncoder().encode('tacit-kernel-v1'), asset, Uint8Array.of(inputs.length & 0xff)];
  for (const inp of inputs) {
    const rev = new Uint8Array(inp.txidBE); rev.reverse();
    parts.push(rev, _voutLE(inp.vout));
  }
  parts.push(Uint8Array.of(outCommitments.length & 0xff));
  for (const c of outCommitments) parts.push(c);
  parts.push(new Uint8Array(8));
  return _sha256(cat(parts));
}

const PREAUTH_BID_INLINE = { 0x5b: 16 + 33 + 8 + 32 + 8, 0x5c: 16 + 33 + 8 + 8 + 8 + 8 + 32 + 20 + 1 };
function parsePreauthBidEnvelope(envHex) {
  const env = hexToBytes(envHex);
  const inline = PREAUTH_BID_INLINE[env[0]];
  if (inline == null) return null;
  const ksOff = 1 + 32 + 1 + inline;
  if (env.length < ksOff + 64 + 1 + 33 + 2) return null;
  const asset = env.subarray(1, 33), kernelSig = env.subarray(ksOff, ksOff + 64);
  const n = env[ksOff + 64];
  if (n !== 1 && n !== 2) return null;
  let p = ksOff + 64 + 1;
  const commitments = [];
  for (let i = 0; i < n; i++) {
    if (p + 33 > env.length) return null;
    commitments.push(bytesToHex(env.subarray(p, p + 33))); p += 33;
    if (i === 1) p += 8;
  }
  if (p + 2 > env.length) return null;
  const rpLen = env[p] | (env[p + 1] << 8); p += 2;
  if (p + rpLen !== env.length) return null;
  return { asset: bytesToHex(asset), kernelSig: bytesToHex(kernelSig), commitments, rangeProof: bytesToHex(env.subarray(p, p + rpLen)) };
}

const SWAP_BATCH_XSIGMA = 169, SWAP_BATCH_INTENT_LEN = 1 + 33 + 33 + 32 + 169 + 8 + 8 + 4 + 64, SWAP_BATCH_RECEIPT_LEN = 33 + 32 + 169;
function parseSwapBatchEnvelope(envHex) {
  const env = hexToBytes(envHex);
  if (env[0] !== 0x2f) return null;
  let p = 1;
  const u64le = (o) => { let v = 0n; for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(env[o + i]); return v; };
  const u16le = (o) => env[o] | (env[o + 1] << 8);
  try {
    const take = (n) => { const s = p; if (p + n > env.length) throw 0; p += n; return s; };
    const aA = take(32), aB = take(32);
    const niOff = take(1); const ni = env[niOff]; if (ni < 1 || ni > 16) return null;
    const da = take(9); if (env[da] > 1) return null;
    const db = take(9); if (env[db] > 1) return null;
    const rna = take(32), rnb = take(32), fb = take(2), taA = take(8), tbA = take(8), tac = take(33), tbc = take(33);
    const rta = take(32), rtb = take(32);
    const intents = [];
    for (let i = 0; i < ni; i++) {
      const s = take(SWAP_BATCH_INTENT_LEN); const dir = env[s]; if (dir > 1) return null;
      intents.push({ direction: dir, traderPubkey: bytesToHex(env.subarray(s + 1, s + 34)), cInSecp: bytesToHex(env.subarray(s + 34, s + 67)), cInBjj: bytesToHex(env.subarray(s + 67, s + 99)), inXcurveSigma: bytesToHex(env.subarray(s + 99, s + 268)), minOut: u64le(s + 268).toString(), tipAmount: u64le(s + 276).toString(), expiryHeight: _u32le(env, s + 284), intentSig: bytesToHex(env.subarray(s + 288, s + 352)) });
    }
    const receipts = [];
    for (let i = 0; i < ni; i++) {
      const s = take(SWAP_BATCH_RECEIPT_LEN);
      const rpLenOff = take(2); const rpLen = u16le(rpLenOff); const rpOff = take(rpLen);
      receipts.push({
        cOutSecp: bytesToHex(env.subarray(s, s + 33)), cOutBjj: bytesToHex(env.subarray(s + 33, s + 65)),
        outXcurveSigma: bytesToHex(env.subarray(s + 65, s + 65 + SWAP_BATCH_XSIGMA)),
        rangeProof: bytesToHex(env.subarray(rpOff, rpOff + rpLen)),
      });
    }
    const plOff = take(2); const proofLen = u16le(plOff); const prOff = take(proofLen);
    const slOff = take(1); take(env[slOff]);
    if (p !== env.length) return null;
    return {
      assetA: bytesToHex(env.subarray(aA, aA + 32)), assetB: bytesToHex(env.subarray(aB, aB + 32)), nIntents: ni,
      deltaANetSign: env[da], deltaANetMag: u64le(da + 1).toString(), deltaBNetSign: env[db], deltaBNetMag: u64le(db + 1).toString(),
      rNetA: bytesToHex(env.subarray(rna, rna + 32)), rNetB: bytesToHex(env.subarray(rnb, rnb + 32)),
      feeBps: u16le(fb), tipAAmount: u64le(taA).toString(), tipBAmount: u64le(tbA).toString(),
      tipACSecp: bytesToHex(env.subarray(tac, tac + 33)), tipBCSecp: bytesToHex(env.subarray(tbc, tbc + 33)),
      rTipA: bytesToHex(env.subarray(rta, rta + 32)), rTipB: bytesToHex(env.subarray(rtb, rtb + 32)),
      intents, receipts, proof: bytesToHex(env.subarray(prOff, prOff + proofLen)),
    };
  } catch { return null; }
}

const _u64le = (e, o) => { let v = 0n; for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(e[o + i]); return v.toString(); };
const _u32le = (e, o) => { let v = 0; for (let i = 3; i >= 0; i--) v = v * 256 + e[o + i]; return v; };
const _u128le = (e, o) => { let v = 0n; for (let i = 15; i >= 0; i--) v = (v << 8n) | BigInt(e[o + i]); return v.toString(); };
const _h = (e, a, b) => bytesToHex(e.subarray(a, b));

function parseSwapVarEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x32 || e.length < 269) return null;
  if (e[33] !== 0 && e[33] !== 1) return null;
  const rpLen = e[267] | (e[268] << 8), ks = 269 + rpLen;
  if (e.length !== ks + 64 + 64) return null;
  return { type: 'swap_var', poolId: _h(e, 1, 33), direction: e[33], rAPre: _u64le(e, 34), rBPre: _u64le(e, 42), deltaIn: _u64le(e, 50), deltaInMin: _u64le(e, 58), deltaInMax: _u64le(e, 66), deltaOut: _u64le(e, 74), minOut: _u64le(e, 82), tipAmount: _u64le(e, 90), tipAsset: e[98], expiryHeight: _u32le(e, 99), traderPubkey: _h(e, 103, 136), cIn: _h(e, 136, 169), cChangeOrSentinel: _h(e, 169, 202), cReceipt: _h(e, 202, 235), rReceipt: _h(e, 235, 267), rangeProof: _h(e, 269, 269 + rpLen), kernelSig: _h(e, ks, ks + 64), intentSig: _h(e, ks + 64, ks + 128) };
}
function parseSwapRouteEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x33) return null;
  const n = e[1]; if (n < 2 || n > 4) return null;
  if (_h(e, 2, 34) === _h(e, 34, 66)) return null;
  let p = 111; const hops = [];
  for (let i = 0; i < n; i++) {
    const s = p; p += 67; if (p > e.length) return null;
    const direction = e[s + 32]; if (direction !== 0 && direction !== 1) return null;
    hops.push({ poolId: _h(e, s, s + 32), direction, rAPre: _u64le(e, s + 35), rBPre: _u64le(e, s + 43), deltaANetMag: _u64le(e, s + 51), deltaBNetMag: _u64le(e, s + 59) });
  }
  p += 36;
  const cIn = _h(e, p, p + 33); p += 33;
  const cReceipt = _h(e, p, p + 33); p += 33;
  const rReceipt = _h(e, p, p + 32); p += 32;
  if (p + 2 > e.length) return null;
  const rpLen = e[p] | (e[p + 1] << 8); if (rpLen === 0) return null; p += 2 + rpLen;
  if (p + 64 + 64 !== e.length) return null;
  return { type: 'swap_route', traderInputAsset: _h(e, 2, 34), traderOutputAsset: _h(e, 34, 66), minOut: _u64le(e, 66), expiryHeight: _u32le(e, 74), traderPubkey: _h(e, 78, 111), hops, cIn, cReceipt, rReceipt, kernelSig: _h(e, p, p + 64), intentSig: _h(e, p + 64, p + 128) };
}
function parseHarvestEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] === 0x3b && e.length === 346) return { type: 'harvest', farmId: _h(e, 1, 33), amount: _u64le(e, 122), r: _h(e, 130, 162), owner: _h(e, 162, 194), oldNonce: _h(e, 194, 226), newNonce: _h(e, 226, 258), shares: _u64le(e, 258), rpsEntry: _u128le(e, 266), harvesterSig: _h(e, 282, 346) };
  if (e[0] === 0x3e && e.length === 174) return { type: 'farm_refund', farmId: _h(e, 1, 33), launcherPubkey: _h(e, 33, 66), amount: _u64le(e, 66), refundViewHeight: ((e[74] | (e[75] << 8) | (e[76] << 16) | (e[77] << 24)) >>> 0), r: _h(e, 78, 110), launcherSig: _h(e, 110, 174) };
  return null;
}
function parseProtocolFeeClaimEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x31 || e.length !== 207) return null;
  return { type: 'protocol_fee_claim', poolId: _h(e, 1, 33), claimer: _h(e, 33, 66), feeBps: _u32le(e, 66), amount: _u64le(e, 70), cSecp: _h(e, 78, 111), blinding: _h(e, 111, 143), sig: _h(e, 143, 207) };
}
function parseFarmInitEnvelope(envHex) {
  const e = hexToBytes(envHex);
  const HDR = 1 + 32 + 32 + 33 + 32 + 8 + 8 + 4 + 4 + 33;
  if (e[0] !== 0x34 || e.length < HDR + 2) return null;
  const rpLen = e[HDR] | (e[HDR + 1] << 8), ks = HDR + 2 + rpLen, rt = ks + 64 + 64;
  if (e.length !== rt + 4 + 32 + 32) return null;
  return { type: 'farm_init', poolId: _h(e, 1, 33), farmNonce: _h(e, 33, 65), launcherPubkey: _h(e, 65, 98), rewardAsset: _h(e, 98, 130), rewardTotal: _u64le(e, 130), rewardPerBlock: _u64le(e, 138), startHeight: _u32le(e, 146), endHeight: _u32le(e, 150), cChangeOrSentinel: _h(e, 154, 187), kernelSig: _h(e, ks, ks + 64), launcherSig: _h(e, ks + 64, ks + 128), refundExpiry: _u32le(e, rt), refundDestXonly: _h(e, rt + 4, rt + 36), refundBlinding: _h(e, rt + 36, rt + 68) };
}
function parseLpBond(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x35 || e.length < 193) return null;
  const rpLen = e[191] | (e[192] << 8), ks = 193 + rpLen, rt = ks + 64 + 64;
  if (e.length !== rt + 4 + 32 + 32) return null;
  return { type: 'lp_bond', farmId: _h(e, 1, 33), bonderPubkey: _h(e, 33, 66), bondAmount: _u64le(e, 66), entryAcc: _u128le(e, 74), bondViewHeight: _u32le(e, 90), owner: _h(e, 94, 126), nonce: _h(e, 126, 158), kernelSig: _h(e, ks, ks + 64), bonderSig: _h(e, ks + 64, ks + 128), refundExpiry: _u32le(e, rt), refundDestXonly: _h(e, rt + 4, rt + 36), refundBlinding: _h(e, rt + 36, rt + 68) };
}
function parseLpUnbond(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x36 || e.length !== 217) return null;
  return { type: 'lp_unbond', farmId: _h(e, 1, 33), owner: _h(e, 33, 65), nonce: _h(e, 65, 97), shares: _u64le(e, 97), rpsEntry: _u128le(e, 105), lpReturnR: _h(e, 121, 153), unbonderSig: _h(e, 153, 217) };
}

function parseLpAddEnvelope(envHex) {
  const e = hexToBytes(envHex);
  const HEADER = 452, TAIL = 484, V0_LEN = 552;
  if (e[0] !== 0x2D || e.length < TAIL) return null;
  const variant = e[1];
  if (variant !== 0 && variant !== 1) return null;
  let feeBps = 0, capabilityFlags = 0, protocolFeeAddress = '0x' + '00'.repeat(33), protocolFeeBps = 0;
  let expiryHeight = 0, refundABlinding = '0x' + '00'.repeat(32), refundBBlinding = '0x' + '00'.repeat(32);
  if (variant === 0) {
    if (e.length !== V0_LEN) return null;
    expiryHeight = e[TAIL] | (e[TAIL + 1] << 8) | (e[TAIL + 2] << 16) | (e[TAIL + 3] << 24);
    refundABlinding = _h(e, TAIL + 4, TAIL + 36);
    refundBBlinding = _h(e, TAIL + 36, TAIL + 68);
  }
  if (variant === 1) {
    let p = TAIL;
    const need = (n) => { if (!Number.isInteger(n) || n < 0 || p + n > e.length) throw 0; const s = p; p += n; return s; };
    const needLenPrefixed = () => { const l = e[need(1)]; need(l); };
    try {
      const f0 = need(2); feeBps = e[f0] | (e[f0 + 1] << 8);
      needLenPrefixed();
      needLenPrefixed();
      const ac = e[need(1)]; need(1); need(ac * 33);
      const lc = e[need(1)]; need(lc * 64);
      const pa = need(33); protocolFeeAddress = _h(e, pa, pa + 33);
      const pb = need(2); protocolFeeBps = e[pb] | (e[pb + 1] << 8);
      needLenPrefixed();
      capabilityFlags = e[need(1)];
      if (capabilityFlags & 0x04) return null;
      const e0 = need(4);
      expiryHeight = e[e0] | (e[e0 + 1] << 8) | (e[e0 + 2] << 16) | (e[e0 + 3] << 24);
      const a0 = need(32); refundABlinding = _h(e, a0, a0 + 32);
      const b0 = need(32); refundBBlinding = _h(e, b0, b0 + 32);
      if (p !== e.length) return null;
    } catch { return null; }
  }
  return {
    type: 'lp_add', variant,
    assetA: _h(e, 2, 34), assetB: _h(e, 34, 66),
    deltaA: _u64le(e, 66), deltaB: _u64le(e, 74), shareAmount: _u64le(e, 82),
    shareCsecp: _h(e, 90, 123), kernelSigA: _h(e, 324, 388), kernelSigB: _h(e, 388, 452),
    shareR: _h(e, HEADER, TAIL),
    feeBps, capabilityFlags, protocolFeeAddress, protocolFeeBps,
    expiryHeight: expiryHeight >>> 0, refundABlinding, refundBBlinding,
  };
}

function parseLpRemoveEnvelope(envHex) {
  const e = hexToBytes(envHex);
  const RECV_B = 323, KS = 557, R = KS + 64;
  if (e[0] !== 0x2E || e.length < R + 64 + 2) return null;
  const proofLen = e[R + 64] | (e[R + 65] << 8);
  if (e.length !== R + 66 + proofLen) return null;
  return {
    type: 'lp_remove',
    assetA: _h(e, 1, 33), assetB: _h(e, 33, 65),
    shareAmount: _u64le(e, 65), deltaA: _u64le(e, 73), deltaB: _u64le(e, 81),
    recvASecp: _h(e, 89, 122), recvBSecp: _h(e, RECV_B, RECV_B + 33),
    kernelSig: _h(e, KS, KS + 64), rRecvA: _h(e, R, R + 32), rRecvB: _h(e, R + 32, R + 64),
  };
}

function parseCbtcLockEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x66 || e.length !== 197) return null;
  return {
    type: 'cbtc_lock', asset: _h(e, 1, 33),
    lockVout: (e[33] | (e[34] << 8) | (e[35] << 16) | (e[36] * 0x1000000)) >>> 0,
    cx: _h(e, 37, 69), cy: _h(e, 69, 101),
    sigRx: _h(e, 101, 133), sigRy: _h(e, 133, 165), sigZ: _h(e, 165, 197),
  };
}

function parseCbtcRedeemEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x67 || e.length !== 109) return null;
  let v = 0n; for (let j = 7; j >= 0; j--) v = (v << 8n) | BigInt(e[37 + j]);
  return {
    type: 'cbtc_redeem',
    lockTxid: _h(e, 1, 33),
    lockVout: (e[33] | (e[34] << 8) | (e[35] << 16) | (e[36] * 0x1000000)) >>> 0,
    vBtc: v.toString(),
    kernelSig: _h(e, 45, 109),
  };
}

function txOutputValue(rawTxHex, vout) {
  const tx = hexToBytes(rawTxHex.startsWith('0x') ? rawTxHex.slice(2) : rawTxHex);
  let pos = (tx[4] === 0x00 && tx[5] === 0x01) ? 6 : 4;
  let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; pos += r[1];
  for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
  r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
  for (let i = 0; i < outCount; i++) {
    if (i === vout) { let v = 0n; for (let j = 7; j >= 0; j--) v = (v << 8n) | BigInt(tx[pos + j]); return v.toString(); }
    pos += 8; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0];
  }
  return null;
}

function txOutputScript(rawTxHex, vout) {
  const tx = hexToBytes(rawTxHex.startsWith('0x') ? rawTxHex.slice(2) : rawTxHex);
  let pos = (tx[4] === 0x00 && tx[5] === 0x01) ? 6 : 4;
  let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; pos += r[1];
  for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
  r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
  for (let i = 0; i < outCount; i++) {
    pos += 8; r = readVarint(tx, pos); if (!r) return null; const sl = r[0]; pos += r[1];
    if (i === vout) { if (pos + sl > tx.length) return null; return bytesToHex(tx.slice(pos, pos + sl)); }
    pos += sl;
  }
  return null;
}

function parseCrossoutMintEnvelope(envHex) {
  const e = hexToBytes(envHex);
  if (e[0] !== 0x65 || e.length !== 161) return null;
  return { type: 'crossout_mint', asset: _h(e, 1, 33), claimId: _h(e, 33, 65), cx: _h(e, 65, 97), cy: _h(e, 97, 129), owner: _h(e, 129, 161) };
}

function parseEthCallEnvelope(envHex) {
  const e = hexToBytes(envHex);
  const HEADER = 121;
  if (e[0] !== 0x69 || e.length < HEADER) return null;
  const payloadLen = e[119] | (e[120] << 8);
  if (e.length !== HEADER + payloadLen || payloadLen > 1024) return null;
  return {
    type: 'eth_call',
    msgId: _h(e, 1, 33),
    ns: _h(e, 33, 65),
    sender: _h(e, 65, 85),
    destChain: (e[85] << 8) | e[86],
    payloadHash: _h(e, 87, 119),
    payload: _h(e, HEADER, HEADER + payloadLen),
  };
}

function canonicalOutputVout(opcode, i, n) {
  if (opcode === 0x22 || opcode === 0x23 || opcode === 0x26 || opcode === 0x3c || opcode === 0x39) return i;
  if (opcode === 0x37 || opcode === 0x3d) { if (i === 0) return 0; if (i === 1 && n >= 2) return 2; return null; }
  return null;
}
function canonicalBidOutputVout(opcode, i, n, hasRefund) {
  if ((opcode === 0x5b || opcode === 0x5c) && i === 0) return 0;
  if (opcode === 0x5b && i === 1 && n >= 2) return 3;
  if (opcode === 0x5c && i === 1 && n >= 2) return hasRefund ? 4 : 3;
  return null;
}
function preauthBidVarHasRefund(envHex) {
  const env = hexToBytes(envHex);
  if (env[0] !== 0x5c) return false;
  const maxOff = 1 + 32 + 1 + 16 + 33 + 8;
  const fillOff = maxOff + 8 + 8;
  if (env.length < fillOff + 8) return false;
  const rd = (o) => new DataView(env.buffer, env.byteOffset + o, 8).getBigUint64(0, true);
  return rd(fillOff) < rd(maxOff);
}

function classifyConfidentialTx(rawTxHex) {
  const envHex = extractTaprootEnvelope(rawTxHex);
  if (!envHex) return null;
  const burn = parseBurnEnvelope(envHex);
  if (burn) return { type: 'burn', assetId: burn.asset, nullifier: burn.nullifier, dest: burn.dest, target: burn.target };
  const opcode = hexToBytes(envHex)[0];
  const cx = parseCxferEnvelopeFull(envHex);
  if (cx) {
    const vouts = cx.commitments.map((_, i) => canonicalOutputVout(opcode, i, cx.commitments.length));
    if (vouts.some((v) => v === null)) return null;
    return { type: 'cxfer', opcode, assetId: cx.asset, commitments: cx.commitments, kernelSig: cx.kernelSig, rangeProof: cx.rangeProof, vouts, assetInputCount: cx.assetInputCount };
  }
  const cxb = parseCxferBoundEnvelope(envHex);
  if (cxb) {
    const vouts = cxb.commitments.map((_, i) => canonicalOutputVout(opcode, i, cxb.commitments.length));
    if (vouts.some((v) => v === null)) return null;
    return { type: 'cxfer_bound', opcode, target: cxb.target, assetId: cxb.asset, commitments: cxb.commitments, kernelSig: cxb.kernelSig, rangeProof: cxb.rangeProof, vouts };
  }
  const bid = parsePreauthBidEnvelope(envHex);
  if (bid) {
    const hasRefund = preauthBidVarHasRefund(envHex);
    const vouts = bid.commitments.map((_, i) => canonicalBidOutputVout(opcode, i, bid.commitments.length, hasRefund));
    if (vouts.some((v) => v === null)) return null;
    return { type: 'cxfer', opcode, assetId: bid.asset, commitments: bid.commitments, kernelSig: bid.kernelSig, rangeProof: bid.rangeProof, vouts };
  }
  const amm = parseSwapVarEnvelope(envHex) || parseSwapRouteEnvelope(envHex) || parseHarvestEnvelope(envHex)
    || parseProtocolFeeClaimEnvelope(envHex) || parseFarmInitEnvelope(envHex);
  if (amm) return amm;
  const sb = parseSwapBatchEnvelope(envHex);
  if (sb) return { type: 'swap_batch', ...sb };
  const la = parseLpAddEnvelope(envHex);
  if (la) return la;
  const lr = parseLpRemoveEnvelope(envHex);
  if (lr) return lr;
  const cb = parseCbtcLockEnvelope(envHex);
  if (cb) { const vBtc = txOutputValue(rawTxHex, cb.lockVout); return { ...cb, vBtc }; }
  const cr = parseCbtcRedeemEnvelope(envHex);
  if (cr) return cr;
  const co = parseCrossoutMintEnvelope(envHex);
  if (co) return co;
  const ec = parseEthCallEnvelope(envHex);
  if (ec) return ec;
  const lb = parseLpBond(envHex);
  if (lb) return lb;
  const ub = parseLpUnbond(envHex);
  if (ub) return ub;
  return null;
}

export { readVarint, extractInputs, inputFirstWitnessItem, sigBindsAllOutputs, noteSpendsBindOutputs, extractTaprootEnvelope, parseCetch, parseCmint, parseBurnEnvelope, parseCxferEnvelopeFull, axferAssetInputCount, parseCxferBoundEnvelope, encodeCxferBoundEnvelope, buildTacMigration, parsePreauthBidEnvelope, parseSwapBatchEnvelope, parseSwapVarEnvelope, parseSwapRouteEnvelope, parseHarvestEnvelope, parseProtocolFeeClaimEnvelope, parseFarmInitEnvelope, parseLpAddEnvelope, parseLpRemoveEnvelope, parseCbtcLockEnvelope, parseCbtcRedeemEnvelope, parseCrossoutMintEnvelope, parseEthCallEnvelope, txOutputValue, txOutputScript, classifyConfidentialTx };

export function makeBurnDepositKit({ secp, keccak256, sha256 }) {
  const pool = makeConfidentialPool({ secp, keccak256, sha256 });
  const dsha = (b) => sha256(sha256(b));
  const computeTxidBytes = makeComputeTxidBytes(dsha);
  const computeTxid = (txHex) => { const t = computeTxidBytes(hexToBytes(txHex)); return t ? bytesToHex(t) : null; };

  const assetIdFromEtch = (etchTxHex) => {
    const t = computeTxidBytes(hexToBytes(etchTxHex));
    if (!t) return null;
    const pre = new Uint8Array(36);
    pre.set(t, 0);
    return bytesToHex(sha256(pre));
  };

  const parseEtchAnchor = (etchTxHex, assetHex) => {
    const aid = assetIdFromEtch(etchTxHex);
    if (!aid || aid.toLowerCase() !== '0x' + strip(assetHex).toLowerCase()) return null;
    const envHex = extractTaprootEnvelope(etchTxHex);
    if (!envHex) return null;
    const cetch = parseCetch(envHex);
    if (!cetch) return null;
    return { c0Compressed: cetch.c0Compressed, mintAuthority: cetch.mintAuthority };
  };

  const decompress = (cHex) => { try { return secp.ProjectivePoint.fromHex(strip(cHex)); } catch { return null; } };
  const commitmentHashCompressed = (cHex) => { const { cx, cy } = pool.decompressCommitment(cHex); return pool.commitmentHash(cx, cy); };
  const bip340Verify = (sigHex, msgBytes, pxHex) => verifySchnorr(hexToBytes(sigHex), msgBytes, hexToBytes(pxHex));
  const verifyRange = (points, rpHex) => {
    try { return bppRangeVerify(points.map((p) => bppPoint(p.toRawBytes(true))), hexToBytes(rpHex)); }
    catch { return false; }
  };
  const verifyCxferConservation = (asset, inputOutpoints, inputPoints, outputCompressed, rangeProof, kernelSig, burned) =>
    pool.verifyCxferConservation({ asset, inputOutpoints, inputPoints, outsCompressed: outputCompressed, rangeProof, kernelSig, burned: burned || 0 });

  const mirror = makeBurnDepositProvenance({
    outpointKey: pool.outpointKey,
    sha256,
    verifyCxferConservation,
    commitmentHashCompressed,
    decompress,
    extractTaprootEnvelope,
    parseCmint,
    computeTxid,
    extractInputs,
    bip340Verify,
    verifyRange,
    leaf: pool.leaf,
    btcNoteLeaf: pool.btcNoteLeaf,
    btcNoteLeafBound: pool.btcNoteLeafBound,
    merkleRootFrom: pool.merkleRootFrom,
    commitmentHash: pool.commitmentHash,
  });
  const assembler = makeBurnDepositAssembler({ dsha256: dsha, cat, bytesToHex });


  const hexU8 = (h) => hexToBytes(typeof h === 'string' ? h : bytesToHex(h));
  const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  const isZeroBytes = (b) => b.every((x) => x === 0);
  const bitsToTarget = (h) => {
    if (h.length < 76) return null;
    const bits = (h[72] | (h[73] << 8) | (h[74] << 16) | (h[75] * 0x1000000)) >>> 0;
    const exp = bits >>> 24, mant = bits & 0x7fffff;
    if (bits & 0x00800000) return null;
    if (mant === 0) return null;
    if (exp > 32) return null;
    const t = new Uint8Array(32);
    const be4 = (v) => Uint8Array.of((v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff);
    if (exp <= 3) t.set(be4(mant >>> (8 * (3 - exp))), 28);
    else if (exp === 32) t.set(be4(mant).subarray(1), 0);
    else if (exp - 3 + 4 <= 32) t.set(be4(mant), 32 - (exp - 3) - 4);
    return t;
  };
  const beLte = (a, b) => { for (let i = 0; i < 32; i++) { if (a[i] < b[i]) return true; if (a[i] > b[i]) return false; } return true; };
  function headerChainTip(headers) {
    if (!headers.length) return null;
    let prev = null;
    for (const hh of headers) {
      const h = hexU8(hh);
      if (h.length !== 80) return null;
      const bh = dsha(h);
      const target = bitsToTarget(h);
      if (!target) return null;
      if (!beLte(Uint8Array.from(bh).reverse(), target)) return null;
      if (prev && !eqBytes(h.subarray(4, 36), prev)) return null;
      prev = Uint8Array.from(bh);
    }
    return prev;
  }
  function merklePathRoot(txid, siblings, index) {
    let acc = Uint8Array.from(txid); let idx = index >>> 0;
    for (const sib of siblings) { acc = dsha(idx & 1 ? cat([sib, acc]) : cat([acc, sib])); idx >>>= 1; }
    return acc;
  }
  function coinbaseCommitmentOutput(tx) {
    if (tx.length < 4) return null;
    let pos = (tx.length > 5 && tx[4] === 0x00 && tx[5] === 0x01) ? 6 : 4;
    let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; pos += r[1];
    for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
    r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
    let c = null;
    for (let i = 0; i < outCount; i++) {
      pos += 8; r = readVarint(tx, pos); if (!r) return null; pos += r[1];
      const end = pos + r[0]; if (end > tx.length) return null;
      const sc = tx.subarray(pos, end);
      if (sc.length >= 38 && sc[0] === 0x6a && sc[1] === 0x24 && sc[2] === 0xaa && sc[3] === 0x21 && sc[4] === 0xa9 && sc[5] === 0xed) c = sc.subarray(6, 38);
      pos = end;
    }
    return c;
  }
  function coinbaseCommitment(tx) {
    if (tx.length < 6 || tx[4] !== 0x00 || tx[5] !== 0x01) return null;
    let pos = 6;
    let r = readVarint(tx, pos); if (!r) return null; const inCount = r[0]; pos += r[1];
    for (let i = 0; i < inCount; i++) { pos += 36; r = readVarint(tx, pos); if (!r) return null; pos += r[1] + r[0] + 4; }
    r = readVarint(tx, pos); if (!r) return null; const outCount = r[0]; pos += r[1];
    let c = null;
    for (let i = 0; i < outCount; i++) {
      pos += 8; r = readVarint(tx, pos); if (!r) return null; pos += r[1];
      const end = pos + r[0]; if (end > tx.length) return null;
      const sc = tx.subarray(pos, end);
      if (sc.length >= 38 && sc[0] === 0x6a && sc[1] === 0x24 && sc[2] === 0xaa && sc[3] === 0x21 && sc[4] === 0xa9 && sc[5] === 0xed) c = sc.subarray(6, 38);
      pos = end;
    }
    if (!c) return null;
    r = readVarint(tx, pos); if (!r) return null; if (r[0] !== 1) return null; pos += r[1];
    r = readVarint(tx, pos); if (!r) return null; if (r[0] !== 32) return null; pos += r[1];
    if (pos + 32 > tx.length) return null;
    return { commitment: c, reserved: tx.subarray(pos, pos + 32) };
  }
  function witnessCommitted(tx, txIndex, wtxidSiblings, coinbase, cbTxidSiblings, txidRoot) {
    const cbTxid = computeTxidBytes(coinbase);
    if (!cbTxid) return 'no';
    if (!eqBytes(merklePathRoot(cbTxid, cbTxidSiblings, 0), txidRoot)) return 'no';
    const cc = coinbaseCommitment(coinbase);
    if (!cc) return coinbaseCommitmentOutput(coinbase) ? 'abort' : 'no';
    const wroot = merklePathRoot(dsha(tx), wtxidSiblings, txIndex);
    return eqBytes(dsha(cat([wroot, cc.reserved])), cc.commitment) ? 'ok' : 'no';
  }
  function rangeOk(compressedList, proof) {
    try {
      return proof.length === bpClassicProofLen(compressedList.length)
        ? bpRangeVerify(compressedList, proof)
        : bppRangeVerify(compressedList.map((c) => bppPoint(c)), proof);
    } catch { return false; }
  }
  const pointOk = (c33) => { try { secp.ProjectivePoint.fromHex(bytesToHex(c33).slice(2)); return c33.length === 33; } catch { return false; } };
  const chCompressed = (c33) => (pointOk(c33) ? commitmentHashCompressed(bytesToHex(c33)).toLowerCase() : null);
  const opKey = (txid, vout) => pool.outpointKey(bytesToHex(txid), vout >>> 0).toLowerCase();
  function parseBlob(b) {
    let i = 0;
    const u32 = () => { if (i + 4 > b.length) throw 0; const v = (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] * 0x1000000)) >>> 0; i += 4; return v; };
    const u64 = () => { if (i + 8 > b.length) throw 0; let v = 0n; for (let k = 7; k >= 0; k--) v = (v << 8n) | BigInt(b[i + k]); i += 8; return v; };
    const bytes = () => { const n = u32(); if (i + n > b.length) throw 0; const v = b.subarray(i, i + n); i += n; return v; };
    const a = (n) => { if (i + n > b.length) throw 0; const v = b.subarray(i, i + n); i += n; return v; };
    const vec = (n) => { const c = u32(); if (c > 4096) throw 0; const out = []; for (let k = 0; k < c; k++) out.push(a(n)); return out; };
    const vu32 = () => { const c = u32(); if (c > 4096) throw 0; const out = []; for (let k = 0; k < c; k++) out.push(u32()); return out; };
    try {
      const etchTx = bytes(), etchIndex = u32(), etchSiblings = vec(32), etchWtxidSiblings = vec(32);
      const etchCoinbase = bytes(), etchCbTxidSiblings = vec(32);
      const ncm = u32(); if (ncm > 1024) return null;
      const cmints = [];
      for (let k = 0; k < ncm; k++) cmints.push({ revealTx: bytes(), commitTx: bytes(), merkleSiblings: vec(32), merkleIndex: u32(), revealWtxidSiblings: vec(32), revealCoinbase: bytes(), revealCbTxidSiblings: vec(32) });
      const ncx = u32(); if (ncx > 256) return null;
      const prov = [];
      for (let k = 0; k < ncx; k++) prov.push({ tx: bytes(), inputCommitments: vec(33), outputVouts: vu32(), burnedAmount: u64(), inputSkip: u32(), merkleIndex: u32(), merkleSiblings: vec(32), confirmedBlockRoot: a(32), wtxidSiblings: vec(32), coinbase: bytes(), coinbaseTxidSiblings: vec(32) });
      const npm = u32(); if (npm > 256) return null;
      const poolMemberships = [];
      for (let k = 0; k < npm; k++) poolMemberships.push({ outpoint: a(32), cx: a(32), cy: a(32), owner: a(32), noteClass: u32(), chainBinding: a(32), leafIndex: u64(), path: vec(32) });
      if (i !== b.length) return null;
      return { etchTx, etchIndex, etchSiblings, etchWtxidSiblings, etchCoinbase, etchCbTxidSiblings, cmints, prov, poolMemberships };
    } catch { return null; }
  }
  function etchAnchor(etchTx, assetHex) {
    const txid = computeTxidBytes(etchTx);
    if (!txid) return null;
    const pre = new Uint8Array(36); pre.set(txid, 0);
    if (bytesToHex(sha256(pre)).toLowerCase() !== bytesToHex(hexU8(assetHex)).toLowerCase()) return null;
    const env = extractTaprootEnvelope(bytesToHex(etchTx));
    if (!env) return null;
    const ce = parseCetch(env);
    if (!ce) return null;
    const c0 = hexToBytes(ce.c0Compressed);
    if (!pointOk(c0) || !rangeOk([c0], hexToBytes(ce.rangeProof))) return null;
    return { c0, mintAuthority: hexToBytes(ce.mintAuthority), etchTxid: txid };
  }
  function cmintLeaf(assetHex, mintAuthority, etchTxid, revealTx, commitTx) {
    if (isZeroBytes(mintAuthority)) return null;
    const env = extractTaprootEnvelope(bytesToHex(revealTx));
    if (!env) return null;
    const cm = parseCmint(env);
    if (!cm) return null;
    if (!eqBytes(hexToBytes(cm.asset), hexU8(assetHex))) return null;
    if (!eqBytes(hexToBytes(cm.etchTxid), etchTxid)) return null;
    const commitTxid = computeTxidBytes(commitTx);
    if (!commitTxid) return null;
    const rIns = extractInputs(bytesToHex(revealTx));
    if (!rIns || !rIns.length) return null;
    if (!eqBytes(hexToBytes(rIns[0].prevTxid), commitTxid) || rIns[0].prevVout !== 0) return null;
    const cIns = extractInputs(bytesToHex(commitTx));
    if (!cIns || !cIns.length) return null;
    const vle = new Uint8Array(4); new DataView(vle.buffer).setUint32(0, cIns[0].prevVout >>> 0, true);
    const msg = sha256(cat([new TextEncoder().encode('tacit-mint-v1'), hexU8(assetHex), hexToBytes(cIns[0].prevTxid), vle, hexToBytes(cm.commitment), hexToBytes(cm.encryptedAmount)]));
    if (!verifySchnorr(hexToBytes(cm.issuerSig), msg, mintAuthority)) return null;
    const c = hexToBytes(cm.commitment);
    if (!pointOk(c) || !rangeOk([c], hexToBytes(cm.rangeProof))) return null;
    const revealTxid = computeTxidBytes(revealTx);
    if (!revealTxid) return null;
    return [opKey(revealTxid, 0), chCompressed(c)];
  }
  // A hop's other checks run as it is read; the range proofs of all the hops are checked together at the end, since checking them one
  // by one costs seconds each for a deep history. One that fails refuses every hop.
  function verifiedHops(assetHex, prov) {
    const out = [];
    const rangeSink = { classic: [], plus: [] };
    for (const p of prov) {
      const txid = computeTxidBytes(p.tx);
      if (!txid) return null;
      if (!eqBytes(merklePathRoot(txid, p.merkleSiblings, p.merkleIndex), p.confirmedBlockRoot)) return null;
      const w = witnessCommitted(p.tx, p.merkleIndex, p.wtxidSiblings, p.coinbase, p.coinbaseTxidSiblings, p.confirmedBlockRoot);
      if (w !== 'ok') return w === 'abort' ? 'abort' : null;
      const envHex = extractTaprootEnvelope(bytesToHex(p.tx));
      if (!envHex) return null;
      const cx = parseCxferEnvelopeFull(envHex);
      if (!cx) return null;
      if (!eqBytes(hexToBytes(cx.asset), hexU8(assetHex))) return null;
      const all = extractInputs(bytesToHex(p.tx));
      if (!all) return null;
      if (p.inputSkip > all.length) return null;
      let ins;
      if (cx.assetInputCount == null) ins = all.slice(p.inputSkip);
      else if (p.inputSkip !== 1 || 1 + cx.assetInputCount > all.length) return null;
      else ins = all.slice(1, 1 + cx.assetInputCount);
      if (p.inputCommitments.length !== ins.length) return null;
      if (p.outputVouts.length !== cx.commitments.length) return null;
      if (!p.inputCommitments.every(pointOk)) return null;
      const inputPoints = p.inputCommitments.map((c) => secp.ProjectivePoint.fromHex(bytesToHex(c).slice(2)));
      let conserves = false;
      try {
        conserves = pool.verifyCxferConservation({
          asset: assetHex, inputOutpoints: ins.map((x) => [x.prevTxid, x.prevVout]), inputPoints,
          outsCompressed: cx.commitments, rangeProof: cx.rangeProof, kernelSig: cx.kernelSig, burned: p.burnedAmount, rangeSink,
        });
      } catch { conserves = false; }
      if (!conserves) return null;
      const inputs = ins.map((x, k) => [opKey(hexToBytes(x.prevTxid), x.prevVout), chCompressed(p.inputCommitments[k])]);
      const opcode = hexToBytes(envHex)[0];
      const outputs = [];
      for (let k = 0; k < cx.commitments.length; k++) {
        const ch = chCompressed(hexToBytes(cx.commitments[k]));
        if (!ch) return null;
        const canonical = canonicalOutputVout(opcode, k, cx.commitments.length);
        if (canonical === null || p.outputVouts[k] !== canonical) return null;
        outputs.push([canonical, ch]);
      }
      out.push({ txid, inputs, outputs });
    }
    try { return bpRangeVerifyBatch(rangeSink.classic) && bppRangeVerifyBatch(rangeSink.plus) ? out : null; } catch { return null; }
  }
  function dagCommitmentHash(leaves, burnedOutpoint, hops) {
    if (!hops.length) return null;
    const produced = new Map();
    for (const h of hops) {
      if (!h.outputs.length) return null;
      for (const [vout, ch] of h.outputs) { const op = opKey(h.txid, vout); if (produced.has(op)) return null; produced.set(op, ch); }
    }
    const consumed = new Set();
    for (const h of hops) {
      if (!h.inputs.length) return null;
      for (const [op] of h.inputs) { if (consumed.has(op)) return null; consumed.add(op); }
    }
    const reachable = leaves.map(([o, c]) => [o.toLowerCase(), String(c).toLowerCase()]);
    const accepted = hops.map(() => false);
    for (;;) {
      let progress = false;
      hops.forEach((h, k) => {
        if (accepted[k]) return;
        if (h.inputs.every(([op, ch]) => reachable.some(([o, c]) => o === op && c === ch))) {
          accepted[k] = true; progress = true;
          for (const [vout, ch] of h.outputs) reachable.push([opKey(h.txid, vout), ch]);
        }
      });
      if (!progress) break;
    }
    if (accepted.some((x) => !x)) return null;
    if (consumed.has(burnedOutpoint)) return null;
    return produced.has(burnedOutpoint) ? produced.get(burnedOutpoint) : null;
  }
  const burnDepositLeaf = (assetHex, cx, cy, burnedTxidHex, burnedVout) =>
    pool.leaf(assetHex, cx, cy, pool.outpointKey(burnedTxidHex, burnedVout >>> 0));
  function admitBurnDeposit({ burnTxHex, envAsset, envNu, blobHex, provHeaders = [], burnedCx, burnedCy, batchPrevHash }) {
    const burnIns = extractInputs(burnTxHex);
    const burnedTxid = burnIns && burnIns.length ? burnIns[0].prevTxid.toLowerCase() : null;
    const burnedVout = burnIns && burnIns.length ? burnIns[0].prevVout : 0;
    const res = (admitted, reason) => ({
      admitted, reason, burnedTxid, burnedVout,
      burnedNoteLeaf: burnedTxid && burnedCx && burnedCy ? burnDepositLeaf(envAsset, burnedCx, burnedCy, burnedTxid, burnedVout) : null,
    });
    const pb = parseBlob(hexU8(blobHex || '0x'));
    if (!pb) return res(false, 'blob does not parse');
    const tip = headerChainTip(provHeaders);
    if (!tip || !batchPrevHash || bytesToHex(tip).toLowerCase() !== String(batchPrevHash).toLowerCase()) return res(false, 'header chain does not reach the batch anchor');
    const roots = new Set(provHeaders.map((hh) => bytesToHex(hexU8(hh).subarray(36, 68)).toLowerCase()));
    if (!pb.prov.every((c) => roots.has(bytesToHex(c.confirmedBlockRoot).toLowerCase()))) return res(false, 'a hop block is not in the header chain');
    const leaves = [];
    if (pb.etchTx.length) {
      const anchor = etchAnchor(pb.etchTx, envAsset);
      if (!anchor) return res(false, 'etch anchor');
      const etchRoot = merklePathRoot(anchor.etchTxid, pb.etchSiblings, pb.etchIndex);
      if (!roots.has(bytesToHex(etchRoot).toLowerCase())) return res(false, 'etch block not in the header chain');
      const ew = witnessCommitted(pb.etchTx, pb.etchIndex, pb.etchWtxidSiblings, pb.etchCoinbase, pb.etchCbTxidSiblings, etchRoot);
      if (ew !== 'ok') return res(false, ew === 'abort' ? 'etch coinbase downgraded' : 'etch witness not committed');
      const c0Ch = chCompressed(anchor.c0);
      if (!c0Ch) return res(false, 'C_0 not a point');
      leaves.push([opKey(anchor.etchTxid, 0), c0Ch]);
      const seenCommits = [];
      for (const cm of pb.cmints) {
        const revealTxid = computeTxidBytes(cm.revealTx);
        if (!revealTxid) return res(false, 'cmint reveal txid');
        const root = merklePathRoot(revealTxid, cm.merkleSiblings, cm.merkleIndex);
        if (!roots.has(bytesToHex(root).toLowerCase())) return res(false, 'cmint block not in the header chain');
        const commitTxid = computeTxidBytes(cm.commitTx);
        if (!commitTxid) return res(false, 'cmint commit txid');
        if (seenCommits.some((c) => eqBytes(c, commitTxid))) return res(false, 'cmint commit reused');
        seenCommits.push(commitTxid);
        const cw = witnessCommitted(cm.revealTx, cm.merkleIndex, cm.revealWtxidSiblings, cm.revealCoinbase, cm.revealCbTxidSiblings, root);
        if (cw !== 'ok') return res(false, cw === 'abort' ? 'cmint coinbase downgraded' : 'cmint witness not committed');
        const leaf = cmintLeaf(envAsset, anchor.mintAuthority, anchor.etchTxid, cm.revealTx, cm.commitTx);
        if (!leaf) return res(false, 'cmint not authorized');
        leaves.push(leaf);
      }
    }
    if (pb.poolMemberships.length) return res(false, 'pool-membership leaves are refused');
    if (!burnedTxid) return res(false, 'burn tx has no inputs');
    const burnedOutpoint = pool.outpointKey(burnedTxid, burnedVout).toLowerCase();
    if (!pb.prov.length) return res(false, 'empty provenance');
    const hops = verifiedHops(envAsset, pb.prov);
    if (hops === 'abort') return res(false, 'hop coinbase downgraded');
    if (!hops) return res(false, 'a provenance hop does not verify');
    const realCh = dagCommitmentHash(leaves, burnedOutpoint, hops);
    if (!realCh) return res(false, 'burned note does not descend from a supply leaf');
    if (pool.commitmentHash(burnedCx, burnedCy).toLowerCase() !== realCh) return res(false, 'bundle opening does not match the authenticated commitment');
    const leaf = burnDepositLeaf(envAsset, burnedCx, burnedCy, burnedTxid, burnedVout);
    if (pool.nullifier(leaf).toLowerCase() !== String(envNu).toLowerCase()) return res(false, 'envelope nullifier does not match the burned note');
    return res(true, 'admitted');
  }
  function buildBurnDepositEnvelope({ assetId, cx, cy, burnedTxid, burnedVout, dest, target, poolRootField = null }) {
    const leaf = burnDepositLeaf(assetId, cx, cy, burnedTxid, burnedVout);
    const nu = pool.nullifier(leaf);
    const f32 = (h) => { const b = hexU8(h); if (b.length !== 32) throw new Error('burn envelope: 32-byte field expected'); return b; };
    const env = cat([Uint8Array.of(0x2b), f32(assetId), poolRootField ? f32(poolRootField) : new Uint8Array(32), f32(nu), f32(dest), f32(target)]);
    return { envelope: bytesToHex(env), nu, burnedNoteLeaf: leaf };
  }

  return { mirror, assembler, parseEtchAnchor, computeTxidInternal: computeTxid, admitBurnDeposit, buildBurnDepositEnvelope, burnDepositLeaf };
}
