// WHEN AN APP FINDS CASBERI, AND WHEN IT MAY USE YOUR ACCOUNT (prd §1700j).
//
// An Aztec app finds wallets by broadcasting Aztec's discovery and listing the
// wallets that answer within ITS OWN window: Dark Forest Aztec waits 5 s, the
// SDK's default is 60 s. A browser extension answers only once the person has
// approved, to stay hidden from sites that fingerprint extensions. In Casberi's
// browser the one wallet is always Casberi, so hiding hides nothing, and an
// answer that waits on a sheet arrives after a 5 s app has stopped listening:
// the app said it found no wallet.
//
// So discovery is answered at once, and the asks move to the moment the person
// picks Casberi in the app: when the secure channel opens, Connect and the
// emoji check are asked, and every call of the app's waits until both are yes.
// A no to either ends the session. No address, no read and no transaction
// reaches an app before then.
export function connectGate({ approveDiscovery, terminateSession, askConnect, askEmoji, log = () => {} }) {
  // sessionId → { connect, emoji, open, waiting }
  const sessions = new Map();

  function release(id) {
    const s = sessions.get(id);
    if (!s || !s.connect || !s.emoji || s.open) return;
    s.open = true;
    const waiting = s.waiting;
    s.waiting = [];
    log('connected', { waiting: waiting.length });
    for (const run of waiting) run();
  }

  function end(id) {
    sessions.delete(id);
    terminateSession(id);
  }

  return {
    // The app's discovery: answered now, asking nothing (no address goes with it).
    discovered(requestId) {
      approveDiscovery(requestId);
    },
    // The person picked Casberi in the app and the channel is open: ask.
    established(id, origin, emoji) {
      sessions.set(id, { connect: false, emoji: false, open: false, waiting: [] });
      askConnect(id, origin);
      askEmoji(id, origin, emoji);
    },
    // One call of the app's: run now if connected, held until then, refused
    // (false) when the session is not one this gate opened.
    message(id, run) {
      const s = sessions.get(id);
      if (!s) return false;
      if (s.open) run();
      else s.waiting.push(run);
      return true;
    },
    answerConnect(id, yes) {
      const s = sessions.get(id);
      if (!s || s.connect) return;
      if (!yes) return end(id);
      s.connect = true;
      release(id);
    },
    confirmEmoji(id, match) {
      const s = sessions.get(id);
      if (!s || s.emoji) return;
      log('emojiAnswer', { match });
      if (!match) return end(id);
      s.emoji = true;
      release(id);
    },
    terminated(id) {
      sessions.delete(id);
    },
  };
}
