// The steps a send shows (prd §1700w): checked, proving, handed to Aztec,
// then done or failed — each posted once, in order, only for a watched send.
//
//   node test/steps.test.mjs            the checks
//   STEPS=<path> node test/...          a mutated steps.js
//
// Exit 0 when every check holds, 1 otherwise.
const posted = [];
globalThis.webkit = { messageHandlers: { engineStep: { postMessage: s => posted.push(JSON.parse(s)) } } };
const { watched, sawProof, sawSendTx, isSendTx } = await import(process.env.STEPS ?? '../src/steps.js');

let failures = 0;
const check = (ok, what) => { if (!ok) { failures++; console.log('✗ ' + what); } };
const steps = () => posted.map(p => p.step).join(',');

// A send: proving and sent once each however often they are seen, then done.
await watched('move', async () => { sawProof(); sawProof(); sawSendTx(); sawSendTx(); });
check(steps() === 'checking,proving,sent,done', `a send posts checking, proving, sent, done once each (got ${steps()})`);
check(posted.every(p => p.kind === 'move'), 'every step names the send it belongs to');
check(posted.at(-1).sent === true, 'done says the transaction reached Aztec');

// Nothing watched: a claim's proof or send posts nothing.
posted.length = 0;
sawProof(); sawSendTx();
check(posted.length === 0, `a proof or send with no send watched posts nothing (got ${steps()})`);

// A failure says so, and a send that never proved is not drawn as sent.
posted.length = 0;
await watched('app', async () => { throw new Error('declined'); }).catch(() => {});
check(steps() === 'checking,failed', `a failed send posts checking, failed (got ${steps()})`);
check(posted.at(-1).sent === false, 'a failure before Aztec says nothing was sent');
check(posted.at(-1).reason === 'declined', `a failure carries its reason (got ${posted.at(-1).reason})`);

// The next send starts clean.
posted.length = 0;
await watched('app', async () => { sawSendTx(); });
check(steps() === 'checking,sent,done', `a second send starts from checking (got ${steps()})`);

// node_sendTx is read from the body's first bytes, in every shape fetch sends.
const tx = JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'node_sendTx', params: ['0x' + 'ab'.repeat(50000)] });
const enc = new TextEncoder().encode(tx);
check(isSendTx(tx), 'a JSON-RPC string body is a send');
check(isSendTx(enc), 'a Uint8Array body is a send');
check(isSendTx(enc.buffer), 'an ArrayBuffer body is a send');
check(isSendTx(JSON.stringify([{ jsonrpc: '2.0', id: 1, method: 'node_sendTx', params: [] }])), 'a batch holding node_sendTx is a send');
check(!isSendTx(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'node_getBlock', params: [1] })), 'a read is not a send');
check(!isSendTx(undefined), 'no body is not a send');

if (failures) { console.log(`✗ ${failures} step check(s) failed`); process.exit(1); }
console.log('✓ steps: checking, proving, sent, done in order, once each; nothing unwatched; node_sendTx read in every body shape');
