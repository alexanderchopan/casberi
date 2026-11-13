// Private gas (prd §1700aa): how a send chooses to pay, when it may be tried
// again from the account's own gas, and that the pinned contract address is
// the one the shipped bytecode derives.
//
//   node test/private-fees.test.mjs             the checks
//   FEES=<path> node test/...                   a mutated private-fees.js
//   SKIP_ADDRESS=1 node test/...                the logic alone (no hashing)
//
// Exit 0 when every check holds, 1 otherwise.
const { PRIVATE_FEES, choose, sendPaying, inTurn, appFee, payingOptions, NO_GAS } = await import(process.env.FEES ?? '../src/private-fees.js');

let failures = 0;
const check = (ok, what) => { if (!ok) { failures++; console.log('✗ ' + what); } };

// --- choose ---------------------------------------------------------------------
const settings = { measured: true };
const short = () => { throw new Error('Estimated max gas cost 9 exceeds maxAcceptableGasCost 4.'); };
const blind = () => { throw new Error('Gas usage metadata was not returned by simulation.'); };
const asked = [];
const measure = (...a) => { asked.push(a); return settings; };
const ready = { nonce: '7', amount: 30n, leafIndex: 3n, ready: true };
const waiting = { nonce: '8', amount: 30n, leafIndex: 4n, ready: false };

let r = await choose({ balance: 12n, ceiling: 8n, pending: [ready], estimate: measure });
check(r.how === 'private' && r.settings === settings, 'a balance that covers the send pays privately, measured');
check(asked.length === 1 && asked[0][0] === 'private' && asked[0][1] === 12n, 'the measure is capped at the balance');

r = await choose({ balance: 4n, ceiling: 8n, pending: [waiting, ready], estimate: (how, ...rest) => (how === 'private' ? short() : measure(how, ...rest)) });
check(r.how === 'mint' && r.item === ready, 'a short balance moves on to a deposit Aztec has carried');
check(asked.at(-1)[0] === 'mint' && asked.at(-1)[1] === 30n && asked.at(-1)[2] === ready, 'the mint is measured against the deposit, capped at its amount');

r = await choose({ balance: 0n, ceiling: 8n, pending: [waiting], estimate: measure });
check(r.how === 'own', 'a deposit Aztec has not carried yet is not minted: the account pays');

r = await choose({ balance: 0n, ceiling: 8n, pending: [], estimate: measure });
check(r.how === 'own', 'nothing private: the account pays');

r = await choose({ balance: 4n, ceiling: 8n, pending: [{ ...ready, amount: 5n }], estimate: short });
check(r.how === 'own', 'a balance and a deposit both too small: the account pays');

r = await choose({ balance: 9n, ceiling: 8n, pending: [], estimate: blind });
check(r.how === 'private' && r.settings === null, 'a wallet that cannot measure pays privately at the fixed limits when the balance covers them');

r = await choose({ balance: 5n, ceiling: 8n, pending: [], estimate: blind });
check(r.how === 'own', 'unmeasured and under the fixed limits: never a private payment that would fail');

r = await choose({ balance: 0n, ceiling: 8n, pending: [{ ...ready, amount: 9n }], estimate: blind });
check(r.how === 'mint' && r.settings === null, 'an unmeasured mint stands at the fixed limits when the deposit covers them');

r = await choose({ balance: 0n, ceiling: 8n, pending: [{ ...ready, amount: 7n }], estimate: blind });
check(r.how === 'own', 'an unmeasured mint under the fixed limits is not tried');

// A deposit a send already spent fails its measure: passed over, never sent blind.
const spent = () => { throw new Error('Assertion failed: nullifier already exists'); };
r = await choose({ balance: 0n, ceiling: 8n, pending: [{ ...ready, amount: 99n }], estimate: spent });
check(r.how === 'own', 'a mint that fails its measure is passed over, however much it holds');
r = await choose({ balance: 99n, ceiling: 8n, pending: [ready], estimate: (how, ...rest) => (how === 'private' ? spent() : measure(how, ...rest)) });
check(r.how === 'mint', 'a private payment that fails its measure moves on to a deposit');

// --- sendPaying -----------------------------------------------------------------
const run = async ({ paid, sends, reach = () => 0 }) => {
  const calls = [];
  let n = 0;
  try {
    const out = await sendPaying({
      pay: paid, reached: reach,
      send: async options => {
        calls.push(options);
        let s = sends[n++];
        if (typeof s === 'function') s = s();
        if (s instanceof Error) throw s;
        return s;
      },
    });
    return { out, calls };
  } catch (error) {
    return { error, calls };
  }
};
const privately = async () => ({ how: 'private', options: { fee: 'fpc' } });
const minting = async () => ({ how: 'mint', item: { nonce: '7' }, options: { fee: 'mint' } });

let s = await run({ paid: privately, sends: ['R'] });
check(s.out?.paid === 'private' && s.out.receipt === 'R' && s.calls.length === 1 && s.calls[0].fee === 'fpc', 'a private payment sends once, with its options');

s = await run({ paid: minting, sends: ['R'] });
check(s.out?.paid === 'mint' && s.out.gasNonce === '7', 'a mint names the deposit it spent');

s = await run({ paid: async () => ({ how: 'own' }), sends: ['R'] });
check(s.out?.paid === 'own' && s.out.gasNonce === null && s.calls[0] === undefined, 'the account pays with no fee options');

s = await run({ paid: async () => { throw new Error('node down'); }, sends: ['R'] });
check(s.out?.paid === 'own', 'a payment that could not be planned falls to the account');

s = await run({ paid: privately, sends: [new Error('proof failed'), 'R2'] });
check(s.out?.paid === 'own' && s.out.receipt === 'R2' && s.calls.length === 2 && s.calls[1] === undefined,
  'a private send that failed before Aztec is tried once more from the account');

let reached = 0;
s = await run({ paid: privately, reach: () => reached, sends: [() => { reached = 1; return new Error('timed out'); }, 'R2'] });
check(s.error?.message === 'timed out' && s.calls.length === 1, 'a send that reached Aztec is never sent a second time');

s = await run({ paid: privately, sends: [new Error('first'), new Error('second')] });
check(s.error?.message === 'first' && s.calls.length === 2, 'when the account cannot pay either, the first failure is the one read');

// --- one send at a time -----------------------------------------------------------
// A claim and a send started together: the send chooses how to pay only after
// the claim has landed (the first real run paid in the open for want of this).
{
  const turn = inTurn();
  const seen = [];
  let landClaim;
  const claim = turn(async () => { seen.push('claim starts'); await new Promise(r => (landClaim = r)); seen.push('claim lands'); return 'C'; });
  const send = turn(async () => { seen.push('send chooses'); return 'S'; });
  await new Promise(r => setTimeout(r, 20));
  check(seen.join(',') === 'claim starts', `a send does not choose while a claim is still in flight (got ${seen.join(',')})`);
  landClaim();
  check((await claim) === 'C' && (await send) === 'S', 'each send answers with its own result');
  check(seen.join(',') === 'claim starts,claim lands,send chooses', `the send chooses after the claim lands (got ${seen.join(',')})`);
  const failed = turn(async () => { throw new Error('boom'); });
  const after = turn(async () => 'ok');
  check((await failed.catch(e => e.message)) === 'boom' && (await after) === 'ok', 'a failed send does not hold the next one');
}

// --- an app's transaction (prd §1759) -------------------------------------------
const ME = '0x0AbC', FPC = '0x0516';
check(appFee({ payer: undefined, me: ME, privateBalance: 5n, ownBalance: 0n }) === 'private', "an app's transaction with no payer is paid from the private balance");
check(appFee({ payer: undefined, me: ME, privateBalance: 5n, ownBalance: 9n }) === 'private', '…before the account\'s own gas, which would name the account');
check(appFee({ payer: undefined, me: ME, privateBalance: 0n, ownBalance: 9n }) === 'own', 'nothing private: the account pays, and the sheet says in the open');
check(appFee({ payer: undefined, me: ME, privateBalance: 0n, ownBalance: 0n }) === 'none', 'nothing anywhere: the sheet says there is no gas');
check(appFee({ payer: '0x0999', me: ME, privateBalance: 5n, ownBalance: 9n }) === 'app', 'a transaction that names another payer is the app\'s to pay');
check(appFee({ payer: '0x0abc', me: ME, privateBalance: 5n, ownBalance: 9n }) === 'own', 'one that names the account itself (its own claim) is the account\'s');
const gasSettings = { measured: true };
let opts = payingOptions({ from: ME, additionalScopes: ['app-scope'], fee: { gasSettings: { theirs: true }, congestionEstimate: 3 }, wait: { timeout: 9 } },
                         { additionalScopes: [FPC], fee: { paymentMethod: {}, gasSettings } });
check(opts.additionalScopes.join() === ['app-scope', FPC].join(), "the app's scopes are kept and the contract's added");
check(opts.fee.gasSettings === gasSettings && opts.fee.congestionEstimate === 3, "the measured gas settings replace the app's; the rest of its fee options stay");
check(opts.from === ME && opts.wait.timeout === 9 && !('paymentMethod' in opts.fee), "nothing else of the app's is touched, and no payment method crosses to the wallet");
opts = payingOptions(undefined, { additionalScopes: [FPC], fee: { gasSettings } });
check(opts.additionalScopes.join() === FPC && opts.fee.gasSettings === gasSettings, 'an app that sent no options still gets the payment');

// --- an account with no gas is told before anything is sent (prd §1761) -----------
{
  let sends = 0;
  const send = async () => { sends++; return 'r'; };
  let said = '';
  try { await sendPaying({ pay: async () => ({ how: 'own' }), send, reached: () => 0, ownHolds: async () => false }); } catch (e) { said = e.message; }
  check(said === NO_GAS && sends === 0, 'nothing private and nothing of its own: it says so, and nothing is sent');
  const ok = await sendPaying({ pay: async () => ({ how: 'own' }), send, reached: () => 0, ownHolds: async () => true });
  check(ok.paid === 'own' && sends === 1, 'an account with gas of its own still pays from it');
  sends = 0; said = '';
  const failing = async options => { sends++; if (options) throw new Error('the contract refused'); return 'r'; };
  try { await sendPaying({ pay: async () => ({ how: 'private', options: {} }), send: failing, reached: () => 0, ownHolds: async () => false }); } catch (e) { said = e.message; }
  check(said === 'the contract refused' && sends === 1, 'a private payment that fails is not tried again from gas the account does not hold, and the first failure is read');
  const own = await sendPaying({ pay: async () => ({ how: 'own' }), send, reached: () => 0 });
  check(own.paid === 'own', "Casberi's own sends, which pass no such check, are sent as before");
}

// --- the pinned address ---------------------------------------------------------
check(PRIVATE_FEES.salt === 1n, 'the shared salt is 1: every wallet derives one address');
check(PRIVATE_FEES.rollupVersion === 2070860440n, "the contract is pinned to Aztec v6's mainnet rollup");
check(PRIVATE_FEES.bridgeSeparator === 3952304070, "the secret's separator is the contract's own");
if (!process.env.SKIP_ADDRESS) {
  const { readFileSync } = await import('node:fs');
  const { fileURLToPath } = await import('node:url');
  const at = p => fileURLToPath(new URL('../node_modules/' + p, import.meta.url));
  const canonical = JSON.parse(readFileSync(at('@alejoamiras/private-fee-juice/canonical-deployment.json'), 'utf8'));
  check(canonical.expectedAddress === PRIVATE_FEES.address, `the package's canonical address is the pinned one (got ${canonical.expectedAddress})`);
  check(BigInt(canonical.salt) === PRIVATE_FEES.salt, 'the package and the pin agree on the salt');
  const { PrivateFPCContractArtifact } = await import('@alejoamiras/private-fee-juice/artifacts/private');
  const { getContractInstanceFromInstantiationParams } = await import('@aztec-labs/stdlib/contract');
  const { AztecAddress } = await import('@aztec-labs/stdlib/aztec-address');
  const { Fr } = await import('@aztec-labs/foundation/curves/bn254');
  const instance = await getContractInstanceFromInstantiationParams(PrivateFPCContractArtifact, {
    salt: new Fr(PRIVATE_FEES.salt), deployer: AztecAddress.ZERO,
  });
  check(instance.address.toString() === PRIVATE_FEES.address, `the shipped bytecode derives the pinned address (got ${instance.address.toString()})`);
}

console.log(failures ? `private-fees: ${failures} failed` : 'private-fees: ok');
process.exit(failures ? 1 : 0);
