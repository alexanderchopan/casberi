
import { derivePositionOwnerPriv, privBytes } from './confidential-recovery.js';

const enc = new TextEncoder();
const dec = new TextDecoder();
const hexOf = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
const bytesOf = (h) => Uint8Array.from((String(h == null ? '' : h).replace(/^0x/, '').match(/../g) || []).map((x) => parseInt(x, 16)));
const cat = (a, b) => { const o = new Uint8Array(a.length + b.length); o.set(a, 0); o.set(b, a.length); return o; };
const lc = (h) => String(h == null ? '' : h).toLowerCase();

export function defaultStorage() {
  try { if (typeof localStorage !== 'undefined' && localStorage) return localStorage; } catch { }
  return { getItem: () => null, setItem: () => {}, removeItem: () => {} };
}
const readJson = (storage, key, fallback) => {
  try { const v = JSON.parse(storage.getItem(key) || 'null'); return v == null ? fallback : v; } catch { return fallback; }
};
const writeJson = (storage, key, value) => {
  try {
    const json = JSON.stringify(value);
    storage.setItem(key, json);
    return storage.getItem(key) === json;
  } catch { return false; }
};

export const isSealed = (b) => !!b && typeof b === 'object' && b.alg === 'a256gcm' && typeof b.ct === 'string' && typeof b.iv === 'string';

export function makeSecretStore({ sha256, subtle, randomBytes } = {}) {
  if (typeof sha256 !== 'function') throw new Error('secret-store: sha256 is required');
  const _subtle = subtle !== undefined ? subtle : ((globalThis.crypto && globalThis.crypto.subtle) || null);
  const _rand = randomBytes || ((n) => globalThis.crypto.getRandomValues(new Uint8Array(n)));
  const available = () => !!_subtle;
  const keyFor = async (walletPriv, domain) => {
    if (!_subtle) throw new Error('secret-store: WebCrypto is unavailable on this origin — nothing was written');
    const pb = walletPriv == null ? null : privBytes(walletPriv);
    if (!pb || pb.length !== 32 || pb.every((b) => b === 0)) throw new Error('secret-store: a 32-byte wallet key is required');
    const km = sha256(cat(enc.encode('tacit-secret-store-v1/' + domain), pb));
    return _subtle.importKey('raw', km, 'AES-GCM', false, ['encrypt', 'decrypt']);
  };
  async function seal(walletPriv, domain, value) {
    const key = await keyFor(walletPriv, domain);
    const iv = _rand(12);
    const ct = new Uint8Array(await _subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(JSON.stringify(value))));
    return { v: 1, alg: 'a256gcm', iv: hexOf(iv), ct: hexOf(ct) };
  }
  async function open(walletPriv, domain, blob) {
    if (!isSealed(blob)) return null;
    try {
      const key = await keyFor(walletPriv, domain);
      const pt = await _subtle.decrypt({ name: 'AES-GCM', iv: bytesOf(blob.iv) }, key, bytesOf(blob.ct));
      return JSON.parse(dec.decode(new Uint8Array(pt)));
    } catch { return null; }
  }
  return { seal, open, isSealed, available };
}

export const STEALTH_SEND_LS_KEY = 'tacit:stealthSends:v1';
const STEALTH_DOMAIN = 'stealth-send';
const STEALTH_SECRETS = ['lBlinding', 'refundPriv'];

export function makeStealthSendStore({ sha256, storage = defaultStorage(), subtle, randomBytes } = {}) {
  const vault = makeSecretStore({ sha256, subtle, randomBytes });
  const session = [];
  const stored = () => { const v = readJson(storage, STEALTH_SEND_LS_KEY, []); return Array.isArray(v) ? v : []; };
  const list = () => [...stored(), ...session];
  const split = (rec) => {
    const pub = { ...rec }; const secrets = {};
    for (const k of STEALTH_SECRETS) { if (pub[k] != null) secrets[k] = pub[k]; delete pub[k]; }
    return { pub, secrets };
  };

  async function add(walletPriv, rec) {
    const { pub, secrets } = split(rec);
    try {
      const sec = await vault.seal(walletPriv, STEALTH_DOMAIN, secrets);
      const all = stored(); all.push({ ...pub, sec });
      if (!writeJson(storage, STEALTH_SEND_LS_KEY, all)) throw new Error('storage unavailable');
      return { persisted: true };
    } catch {
      session.push({ ...rec });
      return { persisted: false };
    }
  }

  async function secretsFor(walletPriv, rec) {
    if (!rec) return null;
    if (rec.sec) return await vault.open(walletPriv, STEALTH_DOMAIN, rec.sec);
    const { secrets } = split(rec);
    return secrets.refundPriv && secrets.lBlinding ? secrets : null;
  }

  function remove(lockLeaf) {
    const keep = stored().filter((r) => lc(r.lockLeaf) !== lc(lockLeaf));
    writeJson(storage, STEALTH_SEND_LS_KEY, keep);
    for (let i = session.length - 1; i >= 0; i--) if (lc(session[i].lockLeaf) === lc(lockLeaf)) session.splice(i, 1);
  }

  async function migrate(walletPriv) {
    const all = stored();
    const out = []; let sealedCount = 0, failed = 0;
    for (const rec of all) {
      if (!rec || rec.sec || !STEALTH_SECRETS.some((k) => rec[k] != null)) { out.push(rec); continue; }
      const { pub, secrets } = split(rec);
      try { out.push({ ...pub, sec: await vault.seal(walletPriv, STEALTH_DOMAIN, secrets) }); sealedCount++; }
      catch { out.push(rec); failed++; }
    }
    if (sealedCount) writeJson(storage, STEALTH_SEND_LS_KEY, out);
    return { sealed: sealedCount, failed };
  }

  return { list, add, remove, secretsFor, migrate, sealingAvailable: vault.available };
}

export const CDP_POSITIONS_LS_KEY = 'tacit-cdp-positions-v1';
const CDP_DOMAIN = 'cdp-position';
const CDP_SECRETS = ['positionOwnerPriv', 'debtNk', 'debtBlinding'];

export function makeCdpPositionStore({ sha256, hmac, secp, curveOrder, storage = defaultStorage(), subtle, randomBytes } = {}) {
  if (typeof hmac !== 'function' || !secp) throw new Error('cdp-position-store: hmac and secp are required');
  const N = BigInt(curveOrder || secp.CURVE.n);
  const vault = makeSecretStore({ sha256, subtle, randomBytes });
  const session = [];
  const stored = () => { const v = readJson(storage, CDP_POSITIONS_LS_KEY, []); return Array.isArray(v) ? v : []; };
  const list = () => [...stored(), ...session];
  const derive = (walletPriv, controller, keyNonce) => derivePositionOwnerPriv({ hmac, sha256, curveOrder: N }, walletPriv, controller, keyNonce);
  const xOnlyOf = (priv) => '0x' + hexOf(secp.getPublicKey(bytesOf(priv), true).subarray(1));
  const split = (rec) => {
    const pub = { ...rec }; const secrets = {};
    for (const k of CDP_SECRETS) { if (pub[k] != null) secrets[k] = pub[k]; delete pub[k]; }
    return { pub, secrets };
  };

  async function add(walletPriv, rec) {
    const { pub, secrets } = split(rec);
    const leftover = { ...secrets };
    if (Number.isInteger(pub.keyNonce) && pub.positionOwner
      && lc(xOnlyOf(derive(walletPriv, pub.controller, pub.keyNonce))) === lc(pub.positionOwner)) delete leftover.positionOwnerPriv;
    if (pub.debtAnchor) { delete leftover.debtNk; delete leftover.debtBlinding; }
    if (!Object.keys(leftover).length) {
      const all = stored(); all.push(pub);
      if (writeJson(storage, CDP_POSITIONS_LS_KEY, all)) return { persisted: true, sealed: false };
      session.push({ ...rec });
      return { persisted: false, sealed: false };
    }
    try {
      const sec = await vault.seal(walletPriv, CDP_DOMAIN, leftover);
      const all = stored(); all.push({ ...pub, sec });
      if (!writeJson(storage, CDP_POSITIONS_LS_KEY, all)) throw new Error('storage unavailable');
      return { persisted: true, sealed: true };
    } catch {
      session.push({ ...rec });
      return { persisted: false, sealed: false };
    }
  }

  async function ownerPrivFor(walletPriv, rec) {
    if (!rec) return null;
    const owner = lc(rec.positionOwner || '');
    if (owner && Number.isInteger(rec.keyNonce) && rec.controller) {
      const d = derive(walletPriv, rec.controller, rec.keyNonce);
      if (lc(xOnlyOf(d)) === owner) return d;
    }
    if (rec.sec) {
      const s = await vault.open(walletPriv, CDP_DOMAIN, rec.sec);
      if (s && s.positionOwnerPriv) return s.positionOwnerPriv;
    }
    return rec.positionOwnerPriv || null;
  }

  async function debtKeysFor(walletPriv, rec, deriveOutput) {
    if (rec && rec.debtAnchor && typeof deriveOutput === 'function') {
      const k = deriveOutput(walletPriv, rec.debtAnchor, 'cdpDebt', 0);
      return { debtNk: k.nk, debtBlinding: k.blindingHex };
    }
    if (rec && rec.sec) {
      const s = await vault.open(walletPriv, CDP_DOMAIN, rec.sec);
      if (s && s.debtNk) return { debtNk: s.debtNk, debtBlinding: s.debtBlinding };
    }
    if (rec && rec.debtNk) return { debtNk: rec.debtNk, debtBlinding: rec.debtBlinding };
    return null;
  }

  function remove(pred) {
    const keep = stored().filter((r) => !pred(r));
    writeJson(storage, CDP_POSITIONS_LS_KEY, keep);
    for (let i = session.length - 1; i >= 0; i--) if (pred(session[i])) session.splice(i, 1);
  }

  async function migrate(walletPriv, { maxNonceScan = 64 } = {}) {
    const all = stored();
    const out = []; let derivableCount = 0, sealedCount = 0, failed = 0;
    for (const rec of all) {
      if (!rec || rec.sec || !CDP_SECRETS.some((k) => rec[k] != null)) { out.push(rec); continue; }
      const { pub, secrets } = split(rec);
      const owner = lc(pub.positionOwner || '');
      let keyNonce = owner && pub.controller && Number.isInteger(pub.keyNonce) ? pub.keyNonce : null;
      if (owner && pub.controller) {
        if (keyNonce != null && lc(xOnlyOf(derive(walletPriv, pub.controller, keyNonce))) !== owner) keyNonce = null;
        if (keyNonce == null) {
          for (let k = 0; k < maxNonceScan; k++) {
            if (lc(xOnlyOf(derive(walletPriv, pub.controller, k))) === owner) { keyNonce = k; break; }
          }
        }
      }
      const leftover = { ...secrets };
      if (keyNonce != null) delete leftover.positionOwnerPriv;
      if (pub.debtAnchor) { delete leftover.debtNk; delete leftover.debtBlinding; }
      if (!Object.keys(leftover).length) { out.push({ ...pub, keyNonce }); derivableCount++; continue; }
      try {
        const sealedRec = { ...pub, sec: await vault.seal(walletPriv, CDP_DOMAIN, leftover) };
        if (keyNonce != null) sealedRec.keyNonce = keyNonce;
        out.push(sealedRec); sealedCount++;
      } catch { out.push(rec); failed++; }
    }
    if (derivableCount || sealedCount) writeJson(storage, CDP_POSITIONS_LS_KEY, out);
    return { derivable: derivableCount, sealed: sealedCount, failed };
  }

  return { list, add, remove, ownerPrivFor, debtKeysFor, migrate, sealingAvailable: vault.available };
}

export const FARM_RECORDS_LS_KEY = 'tacit:farm-position-records:v1';
const FARM_DOMAIN = 'farm-position';

export function makeImportedFarmStore({ sha256, storage = defaultStorage(), subtle, randomBytes } = {}) {
  const vault = makeSecretStore({ sha256, subtle, randomBytes });
  const session = new Map();
  const stored = () => { const v = readJson(storage, FARM_RECORDS_LS_KEY, {}); return v && typeof v === 'object' ? v : {}; };

  async function list(walletPriv) {
    const out = new Map(session);
    for (const [k, rec] of Object.entries(stored())) {
      if (!rec) continue;
      if (rec.sec) {
        const s = await vault.open(walletPriv, FARM_DOMAIN, rec.sec);
        if (s && s.ownerPriv) out.set(k, { ...rec, ownerPriv: s.ownerPriv, sec: undefined });
        continue;
      }
      out.set(k, rec);
    }
    return [...out.values()];
  }

  async function add(walletPriv, rec) {
    const { ownerPriv, ...pub } = rec;
    session.set(pub.receiptLeaf, { ...rec });
    try {
      const sec = await vault.seal(walletPriv, FARM_DOMAIN, { ownerPriv });
      const all = stored();
      all[pub.receiptLeaf] = { ...pub, sec };
      if (!writeJson(storage, FARM_RECORDS_LS_KEY, all)) throw new Error('storage unavailable');
      return { persisted: true };
    } catch {
      return { persisted: false };
    }
  }

  async function migrate(walletPriv) {
    const all = stored();
    let sealedCount = 0, failed = 0;
    for (const [k, rec] of Object.entries(all)) {
      if (!rec || rec.sec || !rec.ownerPriv) continue;
      const { ownerPriv, ...pub } = rec;
      try { all[k] = { ...pub, sec: await vault.seal(walletPriv, FARM_DOMAIN, { ownerPriv }) }; sealedCount++; }
      catch { failed++; }
    }
    if (sealedCount) writeJson(storage, FARM_RECORDS_LS_KEY, all);
    return { sealed: sealedCount, failed };
  }

  return { list, add, migrate, sealingAvailable: vault.available };
}
