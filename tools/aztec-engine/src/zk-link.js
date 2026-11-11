// zk.money's SHORT LINKS (prd §1748, measured 2026-11-11 off zk.money's own
// wallet code and a real request). `zk.money/r#<17 bytes>` holds a kind byte
// (1 a payment link, 2 a request) and a 16-byte seed, nothing else. The
// request itself was announced once through zk.money's LinkLocator contract
// on Aztec as a private log: fifteen fields of ciphertext under a tag the
// seed derives. Reading one is a hash and one keyless read from the node:
//
//   pre    = poseidon2([kind, seed], 1280004933)
//   tag    = poseidon2([pre], 1280005191)
//   siloed = the tag as it stands on chain, siloed with the locator's address
//   node_getPrivateLogsByTags([siloed]) → logData[1..15]
//
// The app opens the ciphertext itself (`ZkMoneyLink.open`: the seed is the
// key, and the record is signed by a key the seed commits to), so this page
// hands back fields and decides nothing.
import { poseidon2HashWithSeparator } from '@aztec-labs/foundation/crypto/poseidon';
import { Fr } from '@aztec-labs/foundation/curves/bn254';
import { computeSiloedPrivateLogFirstField } from '@aztec-labs/stdlib/hash';
import { AztecAddress } from '@aztec-labs/stdlib/aztec-address';

export const ZK_LINK = {
  // LinkLocator's class in zk.money's v6 manifest, and the address its wallet
  // derives for it: salt 0, no deployer, no initializer, default keys.
  classId: '0x2f64572c012c76450cdf752ab9aca56219b9331efb1747685ae48ab455af620e',
  locator: '0x1335463038d508c578312abc978bd4a97ad56ead3c1c4710d9981a7f57d3a1e4',
  preSeparator: 1280004933,
  tagSeparator: 1280005191,
  // A payload is fifteen fields, after the log's own tag.
  fields: 15,
};

// The tag a link's record stands under on chain. `kind` 1 or 2, `seedHex`
// sixteen bytes; anything else is not a zk.money link.
export async function siloedTag(kind, seedHex) {
  if (![1, 2].includes(kind) || !/^[0-9a-f]{32}$/.test(seedHex)) throw new Error('not a zk.money link');
  const pre = await poseidon2HashWithSeparator([new Fr(BigInt(kind)), new Fr(BigInt('0x' + seedHex))], ZK_LINK.preSeparator);
  const tag = await poseidon2HashWithSeparator([pre], ZK_LINK.tagSeparator);
  return (await computeSiloedPrivateLogFirstField(AztecAddress.fromStringUnsafe(ZK_LINK.locator), tag)).toString();
}

// The node's reply as payloads: for each log, the fifteen fields after its
// tag, as 0x-hex. A log with fewer is not a link's record and is left out.
export function payloads(result) {
  return (Array.isArray(result) ? result : []).flat()
    .map(log => (log?.logData ?? []).slice(1, 1 + ZK_LINK.fields).map(String))
    .filter(fields => fields.length === ZK_LINK.fields && fields.every(f => /^0x[0-9a-f]{1,64}$/i.test(f)));
}
