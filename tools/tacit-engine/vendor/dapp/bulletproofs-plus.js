
import { secp, sha256, concatBytes, hexToBytes, bytesToHex } from './vendor/tacit-deps.min.js';

export const SECP_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
export const N_BITS = 64;
export const BPP_MAX_M = 8;
export const BPP_MAX_NM = N_BITS * BPP_MAX_M;

const BPP_DOMAIN = 'tacit-bpp-v1';

export function modN(x) { return ((x % SECP_N) + SECP_N) % SECP_N; }

export function modInv(a) {
  let x = modN(a);
  if (x === 0n) throw new Error('bpp: modInv(0)');
  let result = 1n, base = x, exp = SECP_N - 2n;
  while (exp > 0n) {
    if (exp & 1n) result = modN(result * base);
    base = modN(base * base);
    exp >>= 1n;
  }
  return result;
}

export function batchInv(xs) {
  const n = xs.length;
  if (n === 0) return [];
  const partial = new Array(n);
  partial[0] = modN(xs[0]);
  for (let i = 1; i < n; i++) partial[i] = modN(partial[i - 1] * xs[i]);
  let inv = modInv(partial[n - 1]);
  const out = new Array(n);
  for (let i = n - 1; i >= 0; i--) {
    out[i] = i === 0 ? inv : modN(inv * partial[i - 1]);
    inv = modN(inv * xs[i]);
  }
  return out;
}

export function randomScalar() {
  if (!globalThis.crypto?.getRandomValues) throw new Error('bpp: CSPRNG unavailable');
  for (let attempt = 0; attempt < 32; attempt++) {
    const b = new Uint8Array(32);
    globalThis.crypto.getRandomValues(b);
    const s = bytes32ToBigint(b);
    if (s !== 0n && s < SECP_N) return s;
  }
  throw new Error('bpp: failed to draw a random scalar');
}

export function bytes32ToBigint(b) {
  let r = 0n;
  for (let i = 0; i < 32; i++) r = (r << 8n) | BigInt(b[i]);
  return r;
}

export function bigintToBytes32(n) {
  const m = modN(n);
  return hexToBytes(m.toString(16).padStart(64, '0'));
}

export const G = secp.ProjectivePoint.BASE;
export const ZERO = secp.ProjectivePoint.ZERO;

export function pointToBytes(P) { return P.toRawBytes(true); }
export function bytesToPoint(b) { return secp.ProjectivePoint.fromHex(bytesToHex(b)); }

export function safeMult(P, s) {
  const x = modN(s);
  return x === 0n ? ZERO : P.multiply(x);
}

function _msmWindowSize(activeCount) {
  if (activeCount < 32)   return 3;
  if (activeCount < 128)  return 4;
  if (activeCount < 1024) return 5;
  return 6;
}

export function msm(scalars, points) {
  if (scalars.length !== points.length) throw new Error('bpp: msm length mismatch');
  const n = scalars.length;
  if (n === 0) return ZERO;

  const reduced = new Array(n);
  let activeCount = 0;
  for (let i = 0; i < n; i++) {
    const s = modN(scalars[i]);
    reduced[i] = s;
    if (s !== 0n) activeCount++;
  }
  if (activeCount === 0) return ZERO;

  if (activeCount <= 4) {
    let acc = ZERO;
    for (let i = 0; i < n; i++) {
      if (reduced[i] !== 0n) acc = acc.add(points[i].multiply(reduced[i]));
    }
    return acc;
  }

  const c = _msmWindowSize(activeCount);
  const numBuckets = 1 << c;
  const numWindows = Math.ceil(256 / c);
  const cBig = BigInt(c);
  const mask = (1n << cBig) - 1n;

  let acc = ZERO;
  for (let w = numWindows - 1; w >= 0; w--) {
    if (w !== numWindows - 1) {
      for (let d = 0; d < c; d++) acc = acc.add(acc);
    }

    const buckets = new Array(numBuckets);
    for (let b = 0; b < numBuckets; b++) buckets[b] = ZERO;

    const shift = BigInt(w * c);
    for (let i = 0; i < n; i++) {
      const s = reduced[i];
      if (s === 0n) continue;
      const v = Number((s >> shift) & mask);
      if (v === 0) continue;
      buckets[v] = buckets[v].add(points[i]);
    }

    let runningSum = ZERO;
    let windowTotal = ZERO;
    for (let b = numBuckets - 1; b >= 1; b--) {
      runningSum = runningSum.add(buckets[b]);
      windowTotal = windowTotal.add(runningSum);
    }

    acc = acc.add(windowTotal);
  }

  return acc;
}

export function vecAdd(a, b) {
  if (a.length !== b.length) throw new Error('bpp: vecAdd length mismatch');
  const r = new Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = modN(a[i] + b[i]);
  return r;
}

export function vecSub(a, b) {
  if (a.length !== b.length) throw new Error('bpp: vecSub length mismatch');
  const r = new Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = modN(a[i] - b[i]);
  return r;
}

export function vecScalarMul(v, s) {
  const r = new Array(v.length);
  for (let i = 0; i < v.length; i++) r[i] = modN(v[i] * s);
  return r;
}

export function vecScalarAdd(v, s) {
  const r = new Array(v.length);
  for (let i = 0; i < v.length; i++) r[i] = modN(v[i] + s);
  return r;
}

export function vecScalarSub(v, s) {
  const r = new Array(v.length);
  for (let i = 0; i < v.length; i++) r[i] = modN(v[i] - s);
  return r;
}

export function vecHadamard(a, b) {
  if (a.length !== b.length) throw new Error('bpp: vecHadamard length mismatch');
  const r = new Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = modN(a[i] * b[i]);
  return r;
}

export function vecPow(x, n) {
  const r = new Array(n);
  let p = 1n;
  for (let i = 0; i < n; i++) { r[i] = p; p = modN(p * x); }
  return r;
}

export function vecOnes(n) { return new Array(n).fill(1n); }

export function weightedInnerProduct(a, b, y) {
  if (a.length !== b.length) throw new Error('bpp: weightedInnerProduct length mismatch');
  let res = 0n;
  let yPower = 1n;
  for (let i = 0; i < a.length; i++) {
    yPower = modN(yPower * y);
    res = modN(res + modN(a[i] * b[i]) * yPower);
  }
  return res;
}

export function hadamardFold(v, a, b) {
  if ((v.length & 1) !== 0) throw new Error('bpp: hadamardFold needs even-length vector');
  const sz = v.length / 2;
  const out = new Array(sz);
  for (let i = 0; i < sz; i++) {
    out[i] = v[i].multiply(modN(a)).add(v[sz + i].multiply(modN(b)));
  }
  return out;
}

function _hashToCurveSecp(domain, idx) {
  const domainBytes = new TextEncoder().encode(domain);
  const idxLE = new Uint8Array(4);
  new DataView(idxLE.buffer).setUint32(0, idx >>> 0, true);
  for (let counter = 0; counter < 256; counter++) {
    const seed = sha256(concatBytes(domainBytes, idxLE, new Uint8Array([counter])));
    const candidate = concatBytes(new Uint8Array([0x02]), seed);
    try {
      const p = secp.ProjectivePoint.fromHex(bytesToHex(candidate));
      if (!p.equals(ZERO)) return p;
    } catch {}
  }
  throw new Error(`bpp: _hashToCurveSecp(${domain}, ${idx}) failed`);
}

let _BPP_GVEC = null, _BPP_HVEC = null, _BPP_H = null;
export function bppH() {
  if (_BPP_H) return _BPP_H;
  let H = null;
  const hSeed = sha256(new TextEncoder().encode('tacit-generator-H-v1'));
  for (let counter = 0; counter < 256; counter++) {
    const x = sha256(concatBytes(hSeed, new Uint8Array([counter])));
    try {
      const p = secp.ProjectivePoint.fromHex(bytesToHex(concatBytes(new Uint8Array([0x02]), x)));
      if (!p.equals(ZERO)) { H = p; break; }
    } catch {}
  }
  if (!H) throw new Error('bpp: failed to derive H');
  return (_BPP_H = H);
}
export function bppGens() {
  if (_BPP_GVEC) return { Gvec: _BPP_GVEC, Hvec: _BPP_HVEC, H: _BPP_H };
  const gv = [], hv = [];
  for (let i = 0; i < BPP_MAX_NM; i++) {
    gv.push(_hashToCurveSecp('tacit-bp-G-v1', i));
    hv.push(_hashToCurveSecp('tacit-bp-H-v1', i));
  }
  const H = bppH();
  _BPP_GVEC = Object.freeze(gv);
  _BPP_HVEC = Object.freeze(hv);
  return { Gvec: _BPP_GVEC, Hvec: _BPP_HVEC, H };
}

export function pedersenCommit(v, gamma) {
  const H = bppH();
  return safeMult(H, BigInt(v)).add(safeMult(G, BigInt(gamma)));
}

export function bppTranscript() {
  const parts = [];
  const _u32 = n => {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, n >>> 0, true);
    return b;
  };
  const _push = (labelBytes, dataBytes) => {
    parts.push(_u32(labelBytes.length));
    parts.push(labelBytes);
    parts.push(_u32(dataBytes.length));
    parts.push(dataBytes);
  };
  return {
    append(label, bytes) {
      _push(new TextEncoder().encode(label), bytes);
    },
    challenge(label) {
      const labelBytes = new TextEncoder().encode(label);
      parts.push(_u32(labelBytes.length));
      parts.push(labelBytes);
      const h = sha256(concatBytes(...parts));
      parts.push(_u32(h.length));
      parts.push(h);
      let c = modN(bytes32ToBigint(h));
      if (c === 0n) {
        const h2 = sha256(concatBytes(h, new Uint8Array([0x01])));
        c = modN(bytes32ToBigint(h2));
        if (c === 0n) throw new Error('bpp transcript: 0 challenge');
      }
      return c;
    },
  };
}

export function bppRangeProve(values, blindings, _allowOutOfRangeForTest = false) {
  const m = values.length;
  if (m !== blindings.length) throw new Error('bpp: values/blindings length mismatch');
  if (![1, 2, 4, 8].includes(m)) throw new Error(`bpp: unsupported aggregation m=${m}`);

  const logN = 6;
  const N = N_BITS;
  const logM = Math.log2(m) | 0;
  const logMN = logM + logN;
  const MN = m * N;

  const { Gvec: GvecFull, Hvec: HvecFull, H } = bppGens();
  const Gvec = GvecFull.slice(0, MN);
  const Hvec = HvecFull.slice(0, MN);

  const V = new Array(m);
  for (let j = 0; j < m; j++) {
    if (typeof values[j] !== 'bigint') throw new Error(`bpp: values[${j}] must be bigint`);
    const v = values[j];
    if (!_allowOutOfRangeForTest && (v < 0n || v >= (1n << BigInt(N)))) {
      throw new Error(`bpp: value[${j}]=${v} out of range [0, 2^${N})`);
    }
    V[j] = pedersenCommit(v, blindings[j]);
  }

  const aL = new Array(MN);
  const aR = new Array(MN);
  for (let j = 0; j < m; j++) {
    const v = j < values.length ? values[j] : 0n;
    for (let i = 0; i < N; i++) {
      const bit = (v >> BigInt(i)) & 1n;
      aL[j * N + i] = bit;
      aR[j * N + i] = modN(bit - 1n);
    }
  }

  for (let attempt = 0; attempt < 16; attempt++) {
    try {
      return _bppRangeProveAttempt({ m, MN, logMN, Gvec, Hvec, H, V, aL, aR, blindings });
    } catch (e) {
      if (e?.message?.includes('zero challenge')) continue;
      throw e;
    }
  }
  throw new Error('bpp: 16 retries exhausted (broken randomness?)');
}

function _bppRangeProveAttempt({ m, MN, logMN, Gvec, Hvec, H, V, aL, aR, blindings }) {
  const transcript = bppTranscript();
  transcript.append('domain', new TextEncoder().encode(BPP_DOMAIN));
  transcript.append('M', new Uint8Array([m & 0xff]));
  for (const Vj of V) transcript.append('V', pointToBytes(Vj));

  const alpha = randomScalar();
  let A = msm(aL, Gvec).add(msm(aR, Hvec)).add(safeMult(G, alpha));
  transcript.append('A', pointToBytes(A));

  const y = transcript.challenge('y');
  if (y === 0n) throw new Error('bpp: zero challenge (y)');
  const z = transcript.challenge('z');
  if (z === 0n) throw new Error('bpp: zero challenge (z)');
  const zSq = modN(z * z);

  const d = new Array(MN).fill(0n);
  d[0] = zSq;
  for (let i = 1; i < N_BITS; i++) d[i] = modN(d[i - 1] * 2n);
  for (let j = 1; j < m; j++) {
    for (let i = 0; i < N_BITS; i++) {
      d[j * N_BITS + i] = modN(d[(j - 1) * N_BITS + i] * zSq);
    }
  }

  const yPowers = vecPow(y, MN + 2);

  const aL1 = vecScalarSub(aL, z);
  const aR_plus_z = vecScalarAdd(aR, z);
  const d_y = new Array(MN);
  for (let i = 0; i < MN; i++) {
    d_y[i] = modN(d[i] * yPowers[MN - i]);
  }
  const aR1 = vecAdd(aR_plus_z, d_y);

  let alpha1 = alpha;
  let zp = zSq;
  const yMN1 = yPowers[MN + 1];
  for (let j = 0; j < m; j++) {
    const term = modN(modN(zp * yMN1) * modN(BigInt(blindings[j])));
    alpha1 = modN(alpha1 + term);
    zp = modN(zp * zSq);
  }

  let Gprime = Gvec.slice();
  let Hprime = Hvec.slice();
  let aprime = aL1.slice();
  let bprime = aR1.slice();
  let nprime = MN;

  const yInv = modInv(y);
  const yInvPow = new Array(MN);
  yInvPow[0] = 1n;
  for (let i = 1; i < MN; i++) yInvPow[i] = modN(yInvPow[i - 1] * yInv);

  const Lvec = new Array(logMN);
  const Rvec = new Array(logMN);

  for (let round = 0; round < logMN; round++) {
    nprime /= 2;

    const aprimeLo = aprime.slice(0, nprime);
    const aprimeHi = aprime.slice(nprime);
    const bprimeLo = bprime.slice(0, nprime);
    const bprimeHi = bprime.slice(nprime);
    const cL = weightedInnerProduct(aprimeLo, bprimeHi, y);

    const aprimeHiScaled = vecScalarMul(aprimeHi, yPowers[nprime]);
    const cR = weightedInnerProduct(aprimeHiScaled, bprimeLo, y);

    const dL = randomScalar();
    const dR = randomScalar();

    const GprimeHi = Gprime.slice(nprime);
    const HprimeLo = Hprime.slice(0, nprime);
    const GprimeLo = Gprime.slice(0, nprime);
    const HprimeHi = Hprime.slice(nprime);
    const yInvNp = yInvPow[nprime];
    const aprimeLo_weighted = vecScalarMul(aprimeLo, yInvNp);
    const L_pt = msm(aprimeLo_weighted, GprimeHi)
      .add(msm(bprimeHi, HprimeLo))
      .add(safeMult(H, cL))
      .add(safeMult(G, dL));

    const aprimeHi_weighted = vecScalarMul(aprimeHi, yPowers[nprime]);
    const R_pt = msm(aprimeHi_weighted, GprimeLo)
      .add(msm(bprimeLo, HprimeHi))
      .add(safeMult(H, cR))
      .add(safeMult(G, dR));

    Lvec[round] = L_pt;
    Rvec[round] = R_pt;

    transcript.append('L', pointToBytes(L_pt));
    transcript.append('R', pointToBytes(R_pt));
    const u = transcript.challenge('u');
    if (u === 0n) throw new Error('bpp: zero challenge (u)');
    const uInv = modInv(u);

    const factorGhi = modN(yInvNp * u);
    Gprime = hadamardFold(Gprime, uInv, factorGhi);
    Hprime = hadamardFold(Hprime, u, uInv);
    const factorAhi = modN(uInv * yPowers[nprime]);
    aprime = vecAdd(vecScalarMul(aprimeLo, u), vecScalarMul(aprimeHi, factorAhi));
    bprime = vecAdd(vecScalarMul(bprimeLo, uInv), vecScalarMul(bprimeHi, u));

    const uSq = modN(u * u);
    const uInvSq = modN(uInv * uInv);
    alpha1 = modN(alpha1 + modN(dL * uSq) + modN(dR * uInvSq));
  }

  const r = randomScalar();
  const s = randomScalar();
  const d_ = randomScalar();
  const eta = randomScalar();

  const ry_bprime = modN(modN(r * y) * bprime[0]);
  const sy_aprime = modN(modN(s * y) * aprime[0]);
  const A1_H_scalar = modN(ry_bprime + sy_aprime);
  const A1 = Gprime[0].multiply(modN(r))
    .add(Hprime[0].multiply(modN(s)))
    .add(safeMult(G, d_))
    .add(safeMult(H, A1_H_scalar));

  const rys = modN(modN(r * y) * s);
  const B = safeMult(G, eta).add(safeMult(H, rys));

  transcript.append('A1', pointToBytes(A1));
  transcript.append('B', pointToBytes(B));
  const e = transcript.challenge('e');
  if (e === 0n) throw new Error('bpp: zero challenge (e)');
  const eSq = modN(e * e);

  const r1 = modN(modN(aprime[0] * e) + r);
  const s1 = modN(modN(bprime[0] * e) + s);
  const d1 = modN(modN(d_ * e) + eta + modN(alpha1 * eSq));

  const parts = [
    pointToBytes(A),
    pointToBytes(A1),
    pointToBytes(B),
    bigintToBytes32(r1),
    bigintToBytes32(s1),
    bigintToBytes32(d1),
  ];
  for (let k = 0; k < logMN; k++) {
    parts.push(pointToBytes(Lvec[k]));
    parts.push(pointToBytes(Rvec[k]));
  }
  return { proof: concatBytes(...parts), commitments: V };
}

function _sumOfScalarPowers(x, n) {
  if (n === 0) throw new Error('bpp: sum_of_scalar_powers needs n > 0');
  if (n === 1) return modN(x);
  let res = 0n;
  let xpow = 1n;
  for (let i = 1; i <= n; i++) {
    xpow = modN(xpow * x);
    res = modN(res + xpow);
  }
  return res;
}

function _sumOfEvenPowers(x, n) {
  if ((n & (n - 1)) !== 0) throw new Error('bpp: sum_of_even_powers needs n power of 2');
  if (n === 0) throw new Error('bpp: sum_of_even_powers needs n > 0');
  let x1 = modN(x * x);
  let res = x1;
  let nn = n;
  while (nn > 2) {
    res = modN(res + modN(x1 * res));
    x1 = modN(x1 * x1);
    nn = nn / 2;
  }
  return res;
}

// What bppRangeVerify checks, as scalars on the generators every proof shares (G, H and the first MN of Gvec and Hvec) and on the
// proof's own points: the proof holds when their multi-scalar product is the identity. null for a proof that does not parse or is
// not shaped as one should be.
function bppVerifyTerms(commitments, proofBytes) {
  const m = commitments.length;
  if (![1, 2, 4, 8].includes(m)) return null;

  const logN = 6;
  const N = N_BITS;
  const logM = Math.log2(m) | 0;
  const logMN = logM + logN;
  const MN = m * N;

  const expectedLen = 99 + 96 + logMN * 66;
  if (!proofBytes || proofBytes.length !== expectedLen) return null;

  let off = 0;
  let A, A1, B;
  try {
    A  = bytesToPoint(proofBytes.slice(off, off + 33)); off += 33;
    A1 = bytesToPoint(proofBytes.slice(off, off + 33)); off += 33;
    B  = bytesToPoint(proofBytes.slice(off, off + 33)); off += 33;
  } catch { return null; }
  const r1 = bytes32ToBigint(proofBytes.slice(off, off + 32)); off += 32;
  const s1 = bytes32ToBigint(proofBytes.slice(off, off + 32)); off += 32;
  const d1 = bytes32ToBigint(proofBytes.slice(off, off + 32)); off += 32;
  if (r1 >= SECP_N || s1 >= SECP_N || d1 >= SECP_N) return null;
  const Lvec = new Array(logMN), Rvec = new Array(logMN);
  try {
    for (let k = 0; k < logMN; k++) {
      Lvec[k] = bytesToPoint(proofBytes.slice(off, off + 33)); off += 33;
      Rvec[k] = bytesToPoint(proofBytes.slice(off, off + 33)); off += 33;
    }
  } catch { return null; }
  if (off !== proofBytes.length) return null;

  const transcript = bppTranscript();
  transcript.append('domain', new TextEncoder().encode(BPP_DOMAIN));
  transcript.append('M', new Uint8Array([m & 0xff]));
  try {
    for (const Vj of commitments) transcript.append('V', pointToBytes(Vj));
  } catch { return null; }
  transcript.append('A', pointToBytes(A));
  const y = transcript.challenge('y');
  const z = transcript.challenge('z');
  if (y === 0n || z === 0n) return null;
  const zSq = modN(z * z);

  const challenges = new Array(logMN);
  for (let k = 0; k < logMN; k++) {
    transcript.append('L', pointToBytes(Lvec[k]));
    transcript.append('R', pointToBytes(Rvec[k]));
    challenges[k] = transcript.challenge('u');
    if (challenges[k] === 0n) return null;
  }

  transcript.append('A1', pointToBytes(A1));
  transcript.append('B', pointToBytes(B));
  const e = transcript.challenge('e');
  if (e === 0n) return null;
  const eSq = modN(e * e);

  const toInvert = [...challenges, y];
  const inverses = batchInv(toInvert);
  const challengesInv = inverses.slice(0, logMN);
  const yInv = inverses[logMN];

  let y_MN = y;
  let tempMN = MN;
  while (tempMN > 1) {
    y_MN = modN(y_MN * y_MN);
    tempMN /= 2;
  }
  const y_MN_1 = modN(y_MN * y);

  const d = new Array(MN).fill(0n);
  d[0] = zSq;
  for (let i = 1; i < N; i++) d[i] = modN(d[i - 1] * 2n);
  for (let j = 1; j < m; j++) {
    for (let i = 0; i < N; i++) {
      d[j * N + i] = modN(d[(j - 1) * N + i] * zSq);
    }
  }

  const challengesCache = new Array(1 << logMN);
  challengesCache[0] = challengesInv[0];
  challengesCache[1] = challenges[0];
  for (let j = 1; j < logMN; j++) {
    const slots = 1 << (j + 1);
    for (let s = slots; s-- > 0;) {
      if (s & 1) {
        challengesCache[s] = modN(challengesCache[s >> 1] * challenges[j]);
      } else {
        challengesCache[s] = modN(challengesCache[s >> 1] * challengesInv[j]);
      }
    }
  }

  const { Gvec, Hvec, H } = bppGens();

  const sum_y_MN = _sumOfScalarPowers(y, MN);
  const sum_d_val = modN(modN((1n << BigInt(N)) - 1n) * _sumOfEvenPowers(z, 2 * m));

  const H_term1 = modN(modN(r1 * y) * s1);
  const zSq_minus_z = modN(zSq - z);
  const H_inner1 = modN(zSq_minus_z * sum_y_MN);
  const H_inner2 = modN(modN(y_MN_1 * z) * sum_d_val);
  const H_inner = modN(H_inner1 + H_inner2);
  const H_scalar = modN(H_term1 + modN(eSq * H_inner));
  const G_scalar = d1;

  const V_scalars = new Array(m);
  {
    let zp = zSq;
    const baseFactor = modN(SECP_N - modN(eSq * y_MN_1));
    for (let j = 0; j < m; j++) {
      V_scalars[j] = modN(baseFactor * zp);
      zp = modN(zp * zSq);
    }
  }

  const A_scalar = modN(SECP_N - eSq);
  const A1_scalar = modN(SECP_N - e);
  const B_scalar = modN(SECP_N - 1n);

  const L_scalars = new Array(logMN);
  const R_scalars = new Array(logMN);
  const minus_eSq = modN(SECP_N - eSq);
  for (let k = 0; k < logMN; k++) {
    const uSq = modN(challenges[k] * challenges[k]);
    const uInvSq = modN(challengesInv[k] * challengesInv[k]);
    L_scalars[k] = modN(minus_eSq * uSq);
    R_scalars[k] = modN(minus_eSq * uInvSq);
  }

  const Gi_scalars = new Array(MN);
  const Hi_scalars = new Array(MN);
  let e_r1_y_inv_i = modN(e * r1);
  const e_s1 = modN(e * s1);
  const eSq_z = modN(eSq * z);
  const minus_eSq_z = modN(SECP_N - eSq_z);
  let minus_eSq_y_MN_minus_i = modN(SECP_N - modN(eSq * y_MN));
  const MN_minus_1 = MN - 1;

  for (let i = 0; i < MN; i++) {
    const g_i = modN(modN(e_r1_y_inv_i * challengesCache[i]) + eSq_z);
    Gi_scalars[i] = g_i;

    const revIdx = (MN_minus_1) ^ i;
    const h_i_a = modN(e_s1 * challengesCache[revIdx]);
    const h_i_c = modN(minus_eSq_y_MN_minus_i * d[i]);
    const h_i = modN(modN(h_i_a + minus_eSq_z) + h_i_c);
    Hi_scalars[i] = h_i;

    e_r1_y_inv_i = modN(e_r1_y_inv_i * yInv);
    minus_eSq_y_MN_minus_i = modN(minus_eSq_y_MN_minus_i * yInv);
  }

  const own = [[V_scalars[0], commitments[0]]];
  for (let j = 1; j < m; j++) own.push([V_scalars[j], commitments[j]]);
  own.push([A_scalar, A], [A1_scalar, A1], [B_scalar, B]);
  for (let k = 0; k < logMN; k++) own.push([L_scalars[k], Lvec[k]], [R_scalars[k], Rvec[k]]);
  return { g: G_scalar, h: H_scalar, gi: Gi_scalars, hi: Hi_scalars, own };
}

// The sum of the terms, each weighted, as one multi-scalar multiplication over the shared generators and every proof's own points.
function bppTermsSum(list, weights) {
  const { Gvec, Hvec, H } = bppGens();
  const width = list.reduce((w, t) => Math.max(w, t.gi.length), 0);
  let g = 0n, h = 0n;
  const gi = new Array(width).fill(0n), hi = new Array(width).fill(0n);
  const scalars = [], points = [];
  list.forEach((t, k) => {
    const w = weights ? weights[k] : 1n;
    g = modN(g + w * t.g);
    h = modN(h + w * t.h);
    for (let i = 0; i < t.gi.length; i++) {
      gi[i] = modN(gi[i] + w * t.gi[i]);
      hi[i] = modN(hi[i] + w * t.hi[i]);
    }
    for (const [s, P] of t.own) { scalars.push(w === 1n ? s : modN(w * s)); points.push(P); }
  });
  scalars.push(g, h);
  points.push(G, H);
  for (let i = 0; i < width; i++) { scalars.push(gi[i], hi[i]); points.push(Gvec[i], Hvec[i]); }
  return msm(scalars, points);
}

export function bppRangeVerify(commitments, proofBytes) {
  const t = bppVerifyTerms(commitments, proofBytes);
  return t !== null && bppTermsSum([t], null).equals(ZERO);
}

// Many proofs checked together: each one's terms are weighted by a random scalar and added, and the sum must be the identity. A
// proof that does not hold leaves a sum that is not the identity except for a one-in-2^256 chance of the weights, so this accepts
// what bppRangeVerify accepts of every proof and refuses when any one of them is refused; it does not say which. The proofs share
// the generators Gi and Hi, so all of them together cost little more than the points of their own, a few dozen each, plus one pass
// over the shared ones: tens of times less than checking them one by one. `items` is [{ commitments, proof }].
export function bppRangeVerifyBatch(items) {
  if (!items.length) return true;
  const list = [];
  for (const { commitments, proof } of items) {
    const t = bppVerifyTerms(commitments, proof);
    if (t === null) return false;
    list.push(t);
  }
  return bppTermsSum(list, list.length === 1 ? null : list.map(() => randomScalar())).equals(ZERO);
}
