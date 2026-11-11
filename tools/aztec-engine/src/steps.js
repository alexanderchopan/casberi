// THE STEPS A SEND SHOWS (prd §1700w). A private transaction on Aztec takes
// about 20 seconds: checked on this phone, proved on this phone (7 to 11 s on
// the native prover), handed to Aztec's node, then proposed in a block. The
// app draws each step where the send was started (Move's three rows, the
// browser's capsule), so the wait names what it is doing.
//
// Two signals, read where they happen, never guessed:
//   - proving: the first command to the async prover. Only proofs use it;
//     hashing runs on the sync WebAssembly backend (native-backend.js).
//   - sent: the `node_sendTx` request leaving through the app (net-shim.js).
// One send is watched at a time; a claim proving beside it is not one.
const post = value => globalThis.webkit?.messageHandlers?.engineStep?.postMessage(JSON.stringify(value));

let watching = null;

export function watchSend(kind) {
  watching = { kind, proving: false, sent: false };
  post({ step: 'checking', kind });
}

export function sawProof() {
  if (!watching || watching.proving) return;
  watching.proving = true;
  post({ step: 'proving', kind: watching.kind });
}

// Every transaction handed to Aztec's node, watched or not: a send that
// failed is tried again another way only when this has not moved (prd §1700aa).
let reached = 0;
export const sendsReached = () => reached;

export function sawSendTx() {
  reached++;
  if (!watching || watching.sent) return;
  watching.sent = true;
  post({ step: 'sent', kind: watching.kind });
}

export function endSend(ok, reason) {
  if (!watching) return;
  const end = { step: ok ? 'done' : 'failed', kind: watching.kind, sent: watching.sent };
  // A failure's own words ride along (prd §1700x): the row it failed at says them.
  if (!ok && reason) end.reason = String(reason).slice(0, 200);
  post(end);
  watching = null;
}

// Runs one watched send: its steps, then done or failed.
export async function watched(kind, run) {
  watchSend(kind);
  try {
    const result = await run();
    endSend(true);
    return result;
  } catch (e) {
    endSend(false, e?.message ?? e);
    throw e;
  }
}

// Whether a request body names `node_sendTx`. A transaction is large; its
// method sits in the first bytes of the JSON-RPC body (or of a batch).
export function isSendTx(body) {
  if (body == null) return false;
  let head;
  if (typeof body === 'string') head = body.slice(0, 512);
  else if (body instanceof ArrayBuffer) head = new TextDecoder().decode(new Uint8Array(body, 0, Math.min(512, body.byteLength)));
  else if (ArrayBuffer.isView(body)) head = new TextDecoder().decode(new Uint8Array(body.buffer, body.byteOffset, Math.min(512, body.byteLength)));
  else return false;
  return head.includes('"node_sendTx"');
}
