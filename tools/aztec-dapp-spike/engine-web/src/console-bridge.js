// Imported FIRST, so Aztec's loggers bind to these wrappers: everything the
// engine's libraries print, and every uncaught failure, reaches the shell's log.
const native = (name, value) => window.webkit?.messageHandlers?.[name]?.postMessage(JSON.stringify(value));
// Everything the engine's libraries print, and every uncaught failure, goes to the shell's log.
for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
  const original = console[level].bind(console);
  console[level] = (...a) => {
    original(...a);
    const text = a.map(x => (typeof x === 'string' ? x : (() => { try { return JSON.stringify(x); } catch { return String(x); } })())).join(' ');
    if (!text.startsWith('[engine]')) native('engineLog', { event: 'console', level, text: text.slice(0, 500) });
  };
}
addEventListener('error', e => native('engineLog', { event: 'pageError', text: String(e.message) + ' ' + (e.filename ?? '') }));
addEventListener('unhandledrejection', e => native('engineLog', { event: 'unhandled', text: String(e.reason?.stack ?? e.reason).slice(0, 900) }));
