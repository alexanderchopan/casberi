// What a call says (prd §1763): an app's call laid over its contract's own
// interface. A wrong lay reads as a wrong recipient or amount on the sheet a
// person approves from, so a call that does not fit says nothing.
//
//   node test/call-words.test.mjs            the checks
//   WORDS=<path> node test/...               a mutated call-words.js
const { callWords, width, units } = await import(process.env.WORDS ?? '../src/call-words.js');

let failures = 0;
const check = (ok, what) => { if (!ok) { failures++; console.log('✗ ' + what); } };

const address = { kind: 'struct', path: 'aztec::protocol_types::address::aztec_address::AztecAddress', fields: [{ name: 'inner', type: { kind: 'field' } }] };
const u128 = { kind: 'integer', sign: 'unsigned', width: 128 };
const transfer = { name: 'transfer', parameters: [{ name: 'to', type: address }, { name: 'amount', type: u128 }] };
const TO = '0x' + '00'.repeat(30) + '4f2a';

let w = callWords(transfer, [TO, '0x4c4b40'], { symbol: 'USDC', decimals: 6 });
check(w?.join(' · ') === 'to ...4f2a · amount 5 USDC', `a known token's transfer reads its recipient's tail and its amount in the token (got ${w})`);
w = callWords(transfer, [TO, '0x4c4b40'], null);
check(w?.[1] === 'amount 5000000', 'a token Casberi does not know keeps its amount in the units the call carries');
check(callWords(transfer, [TO], null) === null, 'too few values for the interface: nothing is said');
check(callWords(transfer, [TO, '0x1', '0x2'], null) === null, 'too many values: nothing is said');
check(callWords({ name: 'x', parameters: [{ name: 'p', type: { kind: 'mystery' } }] }, ['0x1'], null) === null, 'a type it cannot size: nothing is said');
check(callWords(transfer, [TO, 'five'], null) === null, 'a value that is not a number: nothing is said');
check(callWords({ name: 'ping', parameters: [] }, [], null)?.length === 0, 'a call with no arguments says none');

const withNonce = { name: 'transfer_in_private', parameters: [{ name: 'to', type: address }, { name: 'amount', type: u128 }, { name: 'nonce', type: { kind: 'field' } }] };
w = callWords(withNonce, [TO, '0x4c4b40', '0x7'], { symbol: 'USDC', decimals: 6 });
check(w?.join(' · ') === 'to ...4f2a · amount 5 USDC · nonce 7', `only the amount is read in the token; a nonce stays a number (got ${w})`);

const mint = { name: 'mint_to_private', parameters: [{ name: 'to', type: address }, { name: 'token_id', type: { kind: 'field' } }, { name: 'is_public', type: { kind: 'boolean' } }] };
w = callWords(mint, [TO, '0x7', '0x0'], null);
check(w?.join(' · ') === 'to ...4f2a · token id 7 · is public no', `names lose their underscores, a boolean reads yes or no (got ${w})`);
const note = { name: 'store', parameters: [{ name: 'note', type: { kind: 'struct', path: 'x::Note', fields: [{ name: 'a', type: { kind: 'field' } }, { name: 'b', type: { kind: 'array', length: 2, type: { kind: 'field' } } }] } }, { name: 'amount', type: u128 }] };
w = callWords(note, ['0x1', '0x2', '0x3', '0x9'], null);
check(w?.join(' · ') === 'note 3 values · amount 9', `a value wider than one field is counted, and the next one still lands in its place (got ${w})`);
check(width(note.parameters[0].type) === 3, 'a struct is as wide as its fields');
const many = { name: 'm', parameters: Array.from({ length: 7 }, (_, i) => ({ name: 'p' + i, type: { kind: 'field' } })) };
check(callWords(many, Array(7).fill('0x1'), null)?.at(-1) === '+2', 'five arguments at most, and how many more');
check(callWords(transfer, [TO, '0x' + 'f'.repeat(40)], null)?.[1] === 'amount ...ffff', 'a number too long to read is drawn by its tail');
check(units(1500000n, 6) === '1.5' && units(5n * 10n ** 18n, 18) === '5' && units(1n, 18) === '<0.000001' && units(0n, 6) === '0', 'units drop trailing zeros, keep six places, and never round a dust amount to nothing');

console.log(failures ? `call-words: ${failures} failed` : 'call-words: ok');
process.exit(failures ? 1 : 0);
