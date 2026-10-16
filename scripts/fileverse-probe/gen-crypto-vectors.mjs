#!/usr/bin/env node
// Writes crypto-vectors.json for the Swift port (prd §1346), from vectors.json
// (which Fileverse's own libraries wrote). It adds what the Swift halves are
// tested against separately: the portal's 32-byte scalar (noble's
// randomSecretKey(portalSeed), as the API derives it; the page stores it
// directly as appDecryptionKey) and the compressed ECDH point of that scalar
// with the lock's ephemeral key. A test portal's key, not anybody's.
import { secp256k1 } from "@noble/curves/secp256k1.js";
import { readFileSync, writeFileSync } from "node:fs";
const v = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
const b64 = (s) => new Uint8Array(Buffer.from(s, "base64"));
const scalar = secp256k1.utils.randomSecretKey(b64(v.portalSeed));
const eph = b64(v.metadata.appLock.lockedFileKey.split("__n__")[0]);
const point = secp256k1.getSharedSecret(scalar, eph);
writeFileSync(new URL("./crypto-vectors.json", import.meta.url), JSON.stringify({
  _about: "From vectors.json (Fileverse's own libraries). scalar = randomSecretKey(portalSeed); sharedPoint = compressed ECDH(scalar, the appLock's ephemeral key); publicKey = the scalar's compressed public key.",
  scalar: Buffer.from(scalar).toString("base64"),
  publicKey: Buffer.from(secp256k1.getPublicKey(scalar, true)).toString("base64"),
  ephemeral: Buffer.from(eph).toString("base64"),
  sharedPoint: Buffer.from(point).toString("base64"),
  metadata: JSON.stringify(v.metadata),
  content: v.content,
  expect: v.expect,
}, null, 1));
console.log("wrote crypto-vectors.json", point.length, "byte point");
