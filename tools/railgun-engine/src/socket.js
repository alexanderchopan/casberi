// The Railgun page's WebSocket (prd §1721 item 3): Railgun's broadcasters are
// reached over Waku, which speaks only WebSocket to three relays. The page's
// Content-Security-Policy allows no host, so `WebSocket` here is Swift's
// (`railgunSocket`): Swift opens the socket only to a relay the broadcasters'
// `NetworkReach` entry declares, records it, and hands every frame back
// through `globalThis.__railgunSocket`. Imported by net.js, so it is in place
// before libp2p looks for `WebSocket`.
//
// Frames travel base64 both ways; Waku's are small (a fee message, a
// transaction), so the copy costs nothing worth measuring.
const sockets = new Map();
let next = 0;

const post = (message) => globalThis.webkit.messageHandlers.railgunSocket.postMessage(message);

function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
const fromBase64 = (b64) => Uint8Array.from(atob(b64 ?? ''), (c) => c.charCodeAt(0));

class RailgunSocket extends EventTarget {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;

  constructor(url, protocols) {
    super();
    this.url = String(url);
    this.protocol = '';
    this.extensions = '';
    this.readyState = RailgunSocket.CONNECTING;
    this.binaryType = 'blob';
    this.bufferedAmount = 0;
    this.onopen = null;
    this.onmessage = null;
    this.onclose = null;
    this.onerror = null;
    this.id = ++next;
    sockets.set(this.id, this);
    const list = protocols == null ? [] : Array.isArray(protocols) ? protocols : [protocols];
    try {
      post({ op: 'open', id: this.id, url: this.url, protocols: list.map(String) });
    } catch (e) {
      queueMicrotask(() => this._closed(1006, String(e?.message ?? e), true));
    }
  }

  get CONNECTING() { return 0; }
  get OPEN() { return 1; }
  get CLOSING() { return 2; }
  get CLOSED() { return 3; }

  send(data) {
    if (this.readyState !== RailgunSocket.OPEN) throw new DOMException('WebSocket is not open', 'InvalidStateError');
    if (typeof data === 'string') { post({ op: 'send', id: this.id, text: data }); return; }
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data)
      : ArrayBuffer.isView(data) ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength) : null;
    if (!bytes) throw new TypeError('unsupported WebSocket payload');
    post({ op: 'send', id: this.id, data64: toBase64(bytes) });
  }

  close(code = 1000, reason = '') {
    if (this.readyState === RailgunSocket.CLOSING || this.readyState === RailgunSocket.CLOSED) return;
    this.readyState = RailgunSocket.CLOSING;
    try { post({ op: 'close', id: this.id, code, reason: String(reason) }); } catch {}
  }

  _fire(type, event) {
    const handler = this[`on${type}`];
    if (typeof handler === 'function') { try { handler.call(this, event); } catch (e) { queueMicrotask(() => { throw e; }); } }
    this.dispatchEvent(event);
  }

  _closed(code, reason, failed) {
    if (this.readyState === RailgunSocket.CLOSED) return;
    this.readyState = RailgunSocket.CLOSED;
    sockets.delete(this.id);
    if (failed) this._fire('error', new Event('error'));
    this._fire('close', new CloseEvent('close', { code, reason, wasClean: !failed }));
  }
}

// Swift's side: `kind` is open, message, close or error.
globalThis.__railgunSocket = (id, kind, payload, binary) => {
  const s = sockets.get(id);
  if (!s) return;
  if (kind === 'open') {
    s.readyState = RailgunSocket.OPEN;
    s.protocol = payload ?? '';
    s._fire('open', new Event('open'));
  } else if (kind === 'message') {
    let data;
    if (!binary) data = payload;
    else {
      const bytes = fromBase64(payload);
      data = s.binaryType === 'arraybuffer' ? bytes.buffer : new Blob([bytes]);
    }
    s._fire('message', new MessageEvent('message', { data }));
  } else if (kind === 'close') {
    s._closed(Number(payload ?? 1000), '', false);
  } else if (kind === 'error') {
    s._closed(1006, String(payload ?? ''), true);
  }
};

globalThis.WebSocket = RailgunSocket;
