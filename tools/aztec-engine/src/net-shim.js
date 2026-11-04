// Imported FIRST. The engine page reaches no host itself: its
// Content-Security-Policy allows only its own origin, and every request for
// another host is rewritten here to the app's loopback server (`/net`), where
// Swift sends it only to a host Casberi declares for the engine (NetworkReach),
// through the app's one funnel — Tor where the policy says, a receipt for each
// (prd §1700, the Privacy Pools engine's rule, §1540).
const nativeFetch = globalThis.fetch.bind(globalThis);

globalThis.fetch = async (input, init = {}) => {
  const request = input instanceof Request ? input : null;
  const url = new URL(request ? request.url : String(input), location.href);
  // The page's own files, and the inline data bb.js loads its WebAssembly
  // from (a 5 MB `data:` URL), never leave the page.
  if (url.origin === location.origin || url.protocol === 'data:' || url.protocol === 'blob:') return nativeFetch(input, init);
  const method = init.method ?? request?.method ?? 'GET';
  const headers = new Headers(init.headers ?? request?.headers ?? {});
  headers.set('x-casberi-target', url.href);
  const body = method === 'GET' || method === 'HEAD' ? undefined : (init.body ?? (request ? await request.arrayBuffer() : undefined));
  return nativeFetch('/net', { method: 'POST', headers: { ...Object.fromEntries(headers), 'x-casberi-method': method }, body, signal: init.signal });
};
