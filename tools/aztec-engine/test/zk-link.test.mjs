// zk.money's short links (prd §1748): the tag a link's record stands under,
// the locator's pinned address, and what counts as a record in a node's reply.
//
//   node test/zk-link.test.mjs            the checks
//   ZKLINK=<path> node test/...           a mutated zk-link.js
//
// Exit 0 when every check holds, 1 otherwise.
const { ZK_LINK, siloedTag, payloads } = await import(process.env.ZKLINK ?? '../src/zk-link.js');

let failures = 0;
const check = (ok, what) => { if (!ok) { failures++; console.log('✗ ' + what); } };
const SEED = '00112233445566778899aabbccddeeff';

// The locator's address is its class id's, as zk.money's wallet derives it.
{
  const { computeContractAddressFromInstance } = await import('@aztec-labs/stdlib/contract');
  const { AztecAddress } = await import('@aztec-labs/stdlib/aztec-address');
  const { PublicKeys } = await import('@aztec-labs/stdlib/keys');
  const { Fr } = await import('@aztec-labs/foundation/curves/bn254');
  const classId = Fr.fromString(ZK_LINK.classId);
  const address = await computeContractAddressFromInstance({ version: 2, salt: Fr.ZERO, deployer: AztecAddress.ZERO,
    originalContractClassId: classId, currentContractClassId: classId, initializationHash: Fr.ZERO, immutablesHash: Fr.ZERO,
    publicKeys: PublicKeys.default() });
  check(address.toString() === ZK_LINK.locator, `the pinned locator is its class's address (got ${address.toString()})`);
}

const request = await siloedTag(2, SEED);
const payment = await siloedTag(1, SEED);
// Recorded 2026-11-11 from this code, after the same three hashes resolved a
// real request on mainnet (its seed is not kept here: it is the request's key).
check(request === '0x0e1de0f34fde5b1d87de50928214b68ced5708d983e24d39adf8acc7d8d64611', `a request's tag (got ${request})`);
check(payment === '0x121dba8cfdc7a4d08d34d1f1f391ea5a73e9b0534ebff36d3415cfe8d7d9ae31', `a payment link's tag (got ${payment})`);
check(request !== payment, 'the kind is part of the tag');
check((await siloedTag(2, 'ff112233445566778899aabbccddeeff')) !== request, 'the seed is part of the tag');
for (const [kind, seed] of [[3, SEED], [0, SEED], [2, SEED.slice(2)], [2, SEED + '00'], [2, SEED.toUpperCase()], ['2', SEED]]) {
  const refused = await siloedTag(kind, seed).then(() => false, () => true);
  check(refused, `not a zk.money link: kind ${kind}, seed ${seed.length} chars`);
}

const f = i => '0x' + i.toString(16).padStart(64, '0');
const log = n => ({ logData: Array.from({ length: n }, (_, i) => f(i)) });
check(payloads([[log(18)]]).length === 1 && payloads([[log(18)]])[0].length === 15 && payloads([[log(18)]])[0][0] === f(1),
  "a record is the fifteen fields after the log's own tag");
check(payloads([[log(10)], [log(16), log(18)]]).length === 2, 'a log with fewer fields is not a record');
check(payloads(null).length === 0 && payloads([[{}]]).length === 0 && payloads([[{ logData: ['x'.repeat(4)] }]]).length === 0, 'anything else reads as nothing');

console.log(failures ? `zk-link: ${failures} failed` : 'zk-link: ok');
process.exit(failures ? 1 : 0);
