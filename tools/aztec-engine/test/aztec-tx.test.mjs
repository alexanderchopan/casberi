// What the engine says about an Aztec transaction (prd §1711), checked against
// Aztec's own types: an address anyone can receive at, the transfer a token's
// interface offers, who pays an app's fee and what it costs, and the hash and
// fee read off a receipt or an app's send.
//
//   node test/aztec-tx.test.mjs                 the checks
//   TX=<path> node test/aztec-tx.test.mjs       a mutated copy of aztec-tx.js
//
// Exit 0 when every check holds, 1 otherwise.
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { Gas, GasFees } from '@aztec-labs/stdlib/gas';

const tx = await import(process.env.TX ?? '../src/aztec-tx.js');

let ran = 0;
let bad = 0;
const check = (ok, what) => {
  ran += 1;
  if (!ok) {
    bad += 1;
    console.log('✗ ' + what);
  }
};

// ── An address anyone can receive at ──────────────────────────────────
const good = await AztecAddress.random();
check(await tx.addressValid(AztecAddress, good.toString()), 'a valid Aztec address was refused');
check(await tx.addressValid(AztecAddress, ' ' + good.toString().toUpperCase().replace('0X', '0x') + ' '),
  'a valid address in capitals with spaces was refused');
let off = null;
for (let i = 1n; i < 64n && !off; i++) {
  const a = AztecAddress.fromBigIntUnsafe(i);
  if (!(await a.isValid())) off = a.toString();
}
check(off && !(await tx.addressValid(AztecAddress, off)), 'an address off the curve passed: a note to it can never be read');
check(!(await tx.addressValid(AztecAddress, '0x' + 'f'.repeat(64))), 'a value above the field passed');
check(!(await tx.addressValid(AztecAddress, '0x' + '0'.repeat(64))), 'the zero address passed');
check(!(await tx.addressValid(AztecAddress, '0x' + 'a'.repeat(40))), 'an Ethereum address passed as an Aztec one');
check(!(await tx.addressValid(AztecAddress, 'hello')), 'words passed as an address');

// ── The transfer a token offers ───────────────────────────────────────
const fn = (name, count, functionType = 'private') => ({ name, functionType, parameters: Array.from({ length: count }, (_, i) => ({ name: `p${i}` })) });
const me = good;
const them = await AztecAddress.random();
const standard = tx.transferCall({ functions: [fn('transfer', 2), fn('transfer_private_to_private', 4)] });
check(standard?.name === 'transfer_private_to_private', 'the standard private transfer did not win');
const args = standard?.args(me, them, 5n) ?? [];
check(args.length === 4 && args[0] === me && args[1] === them && args[2] === 5n && args[3] === 0n,
  'the standard transfer is not (from, to, amount, nonce 0)');
const older = tx.transferCall({ functions: [fn('transfer', 2)] });
check(older?.name === 'transfer' && older.args(me, them, 7n).length === 2 && older.args(me, them, 7n)[0] === them,
  "the older Token contract's private transfer(to, amount) was not offered");
check(tx.transferCall({ functions: [fn('transfer', 2, 'public')] }) === null, 'a public transfer was taken for a private one');
check(tx.transferCall({ functions: [fn('transfer', 3)] }) === null, 'a transfer of another shape was guessed at');
check(tx.transferCall({ functions: [fn('transfer_in_public', 4, 'public')] }) === null, 'a public-only token was offered');
check(tx.transferCall(null) === null, 'no interface offered a transfer');

// ── Who pays an app's fee, and what it costs ──────────────────────────
check(tx.feePayer({}, me) === 'you', 'a payload with no payer is not paid from your Fee Juice');
check(tx.feePayer({ feePayer: AztecAddress.ZERO }, me) === 'you', 'the zero payer read as someone else');
check(tx.feePayer({ feePayer: me }, me) === 'claim', 'paying from Fee Juice it claims read as someone else');
check(tx.feePayer({ feePayer: them }, me) === 'app', 'a sponsor read as you');
const used = { totalGas: new Gas(1000, 200000) };
const fees = new GasFees(3, 1_000_000_000n);
check(tx.feeUnits(used, fees) === (1000n * 3n + 200000n * 1_000_000_000n).toString(), 'the fee is not gas used times today’s fees');
check(tx.feeUnits(null, fees) === null && tx.feeUnits(used, null) === null, 'a fee was made up from nothing');

// ── The hash and fee, off a receipt or an app's send ──────────────────
const hash = Fr.random();
const receipt = { txHash: hash, status: 'proposed', transactionFee: 420000000000000000n };
const out = tx.receiptOut(receipt);
check(out.tx === hash.toString() && out.status === 'proposed' && out.fee === '420000000000000000', 'a receipt was misread');
check(tx.receiptOut({ txHash: hash, status: 'pending' }).fee === null, 'a receipt with no fee read as one');
check(tx.sentOut({ receipt }).fee === '420000000000000000', "an app's waited send lost its fee");
check(tx.sentOut({ txHash: hash }).tx === hash.toString() && tx.sentOut({ txHash: hash }).fee === null,
  "an app's unwaited send lost its hash");
check(tx.sentOut(undefined).tx === null, 'nothing read as a send');

// ── The calls a sheet lists ───────────────────────────────────────────
const calls = tx.describeCalls({ calls: [{ name: 'swap', to: them, type: 'private' }] });
check(calls.length === 1 && calls[0].to === '...' + them.toString().slice(-4) && calls[0].type === 'private',
  'a call is not named by its tail and kind');

console.log(bad === 0 ? `aztec-tx test: ${ran} checks ok` : `aztec-tx test: ${bad} of ${ran} failed`);
process.exit(bad === 0 ? 0 : 1);
