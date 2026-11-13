// An app's public authorization (prd §1760): what a `grantPublicAuthwit`
// request must be before anything is built from it, and what the sheet draws
// of its arguments.
//
//   node test/app-grant.test.mjs             the checks
//   GRANT=<path> node test/...               a mutated app-grant.js
//
// Exit 0 when every check holds, 1 otherwise.
const { grantRequest, grantWords } = await import(process.env.GRANT ?? '../src/app-grant.js');

let failures = 0;
const check = (ok, what) => { if (!ok) { failures++; console.log('✗ ' + what); } };
const refused = (args, what) => { try { grantRequest(args, ME); check(false, what); } catch { /* refused */ } };

const ME = '0x' + '0a'.repeat(32), APP = '0x' + '1b'.repeat(32), TOKEN = '0x' + '2c'.repeat(32);
const good = { caller: APP, contract: TOKEN, method: 'transfer_public_to_public', args: [ME, APP, '5', 7] };

let r = grantRequest([ME, good], ME);
check(r.caller === APP && r.contract === TOKEN && r.method === good.method && r.args === good.args, 'a whole request is taken as written');
check(grantRequest([ME.toUpperCase().replace('0X', '0x'), good], ME).method === good.method, "the account is compared as a number: its letters' case does not matter");
refused([APP, good], 'an app cannot name another account to grant from');
refused([ME, { ...good, caller: ME }], 'the account authorizing itself is refused');
refused([ME, { ...good, caller: 'the app' }], 'a caller that is not an address is refused');
refused([ME, { ...good, contract: '0x' }], 'a contract that is not an address is refused');
refused([ME, { ...good, method: 'transfer(); drop' }], 'a function name with anything but letters, digits and _ is refused');
refused([ME, { ...good, args: 'none' }], 'arguments that are not a list are refused');
refused([ME, { ...good, args: Array(33).fill(1) }], 'more arguments than any function takes are refused');
refused([ME], 'a request with nothing to authorize is refused');
refused('x', 'a request that is not a list is refused');

const w = grantWords([ME, '5', 7, true, 123456789012345678901234567890n, { a: 1 }]);
check(w[0] === '...0a0a' && w[1] === '5' && w[2] === '7' && w[3] === 'true' && w[4] === '...7890', 'an address or a long number is drawn by its tail, a short value whole');
check(grantWords([1, 2, 3, 4, 5, 6, 7, 8]).join() === '1,2,3,4,5,6,+2', 'six arguments at most, and how many more');

console.log(failures ? `app-grant: ${failures} failed` : 'app-grant: ok');
process.exit(failures ? 1 : 0);
