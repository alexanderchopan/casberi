// The Railgun page's ONE door to the network (prd §1713): Swift (`railgunNet`).
// Imported FIRST by engine.js, so it is in place before the SDK, its GraphQL
// client or ethers look for `fetch`. An ES module's imports all run before its
// own body, and a library that keeps the `fetch` it found at load keeps the
// page's own, which the Content-Security-Policy blocks: the UTXO quick sync
// failed silently that way and the engine fell back to walking the chain
// (measured 2026-11-07, hundreds of calls a minute, hours to finish).
//
// The page's CSP allows `connect-src casberi-railgun:` only, so an https
// request from here fails in WebKit before it leaves; the SDK's fetch goes to
// the app instead, which checks the host against the engine's `NetworkReach`
// entry and sends it through its one funnel. Bodies come back base64, because
// the proving files are binary.
const pageFetch = globalThis.fetch.bind(globalThis);

async function railgunFetch(input, init = {}) {
  const request = input instanceof Request ? input : null;
  const url = request ? request.url : String(input);
  if (!/^https?:/.test(url)) return pageFetch(input, init);
  const method = (init.method ?? request?.method ?? 'GET').toUpperCase();
  const headers = {};
  new Headers(init.headers ?? request?.headers ?? {}).forEach((v, k) => { headers[k] = v; });
  let body = init.body ?? (request && method !== 'GET' ? await request.arrayBuffer() : null);
  if (body instanceof Uint8Array || body instanceof ArrayBuffer) body = new TextDecoder().decode(body);
  if (body != null && typeof body !== 'string') body = String(body);
  if (init.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
  let reply;
  try {
    reply = await globalThis.webkit.messageHandlers.railgunNet.postMessage({ url, method, headers, body });
  } catch (refusal) {
    // The app refused the host, or the request never got an answer: the
    // browser's own wording for a network failure, so the SDK retries as usual.
    throw new TypeError(`Failed to fetch (${String(refusal?.message ?? refusal)})`);
  }
  const bytes = Uint8Array.from(atob(reply.body64 ?? ''), (c) => c.charCodeAt(0));
  const nullBody = [101, 204, 205, 304].includes(reply.status);
  return new Response(nullBody ? null : bytes, { status: reply.status, headers: { 'content-type': reply.type ?? 'application/octet-stream' } });
}

globalThis.fetch = railgunFetch;

// The page's log: one line at a time to Swift (`railgunLog`).
export const say = (line) => { try { globalThis.webkit.messageHandlers.railgunLog.postMessage(String(line).slice(0, 400)); } catch {} };
globalThis.addEventListener('error', (e) => say(`pageError ${e.message}`));
globalThis.addEventListener('unhandledrejection', (e) => say(`pageRejection ${String(e.reason?.message ?? e.reason).slice(0, 300)}`));
