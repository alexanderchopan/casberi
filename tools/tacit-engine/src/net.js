// The web view's ONE door to the network. Imported first, so it is in place
// before Tacit's wallet looks for `fetch`.
//
// The page's Content-Security-Policy allows `connect-src casberi-tacit:`
// only, so a request to any https host fails in WebKit before it leaves.
// Everything the wallet asks for goes here instead: to the app, which checks
// the host against the engine's entry in NetworkReach (the list the app
// discloses), sends it through its one funnel (`IngestSupport.sendRequest`:
// Tor, the receipts ledger), and hands the answer back.

const pageFetch = globalThis.fetch.bind(globalThis);

function headersObject(headers) {
  const out = {};
  if (!headers) return out;
  new Headers(headers).forEach((value, key) => { out[key] = value; });
  return out;
}

async function bodyText(body) {
  if (body == null) return null;
  if (typeof body === 'string') return body;
  if (body instanceof Uint8Array || body instanceof ArrayBuffer) return new TextDecoder().decode(body);
  if (body instanceof Blob) return await body.text();
  return String(body);
}

async function engineFetch(input, init = {}) {
  const request = input instanceof Request ? input : null;
  const url = request ? request.url : String(input);
  if (url.startsWith('casberi-tacit:')) return pageFetch(input, init);
  const method = (init.method ?? request?.method ?? 'GET').toUpperCase();
  const headers = headersObject(init.headers ?? request?.headers);
  const body = await bodyText(init.body ?? (request && method !== 'GET' ? await request.text() : null));
  if (init.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
  let reply;
  try {
    reply = await globalThis.webkit.messageHandlers.engineNet.postMessage({ url, method, headers, body });
  } catch (refusal) {
    // The app refused the host, or the request never got an answer: the
    // browser's own wording for a network failure.
    throw new TypeError(`Failed to fetch (${String(refusal?.message ?? refusal)})`);
  }
  const nullBody = [101, 204, 205, 304].includes(reply.status);
  const bytes = nullBody ? null : Uint8Array.from(atob(reply.body64 ?? ''), (c) => c.charCodeAt(0));
  return new Response(bytes, { status: reply.status, headers: reply.headers ?? {} });
}

globalThis.fetch = engineFetch;
