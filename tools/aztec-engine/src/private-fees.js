// PRIVATE GAS (prd §1700aa). A send paid from the account's own Fee Juice
// names the account in public as its fee payer, and a gas deposit to the
// account names it on Ethereum. So gas goes through the ecosystem's shared
// PrivateFPC instead (the `private-fee-juice` package, the one Aztec's own
// guide and Shield use): gas is bridged to the contract's address, kept as a
// private balance inside it, and the contract is the fee payer everyone sees.
//
// The contract is the community's, not Aztec's, and has had no audit. It holds
// gas only — it has no say over a token — and the app keeps one top-up in it.
//
// Its address comes from its bytecode, so it belongs to one Aztec version: the
// rollup pinned here. On any other rollup nothing is sent to it.
export const PRIVATE_FEES = {
  address: '0x0516ebb4f9c7988eb3cf6dd9459a47556f7a92db06b17cfa47ffb37fd35c6915',
  salt: 1n,
  rollupVersion: 2070860440n, // Aztec v6 on Ethereum mainnet
  // poseidon2_hash_bytes("az_dom_sep__fpc_bridge_secret") as u32, the contract's own.
  bridgeSeparator: 3952304070,
  // The limits a send declares when it could not be measured first (Shield's
  // own). The contract charges the whole declared limit and refunds nothing.
  limits: { l2Gas: 2_000_000, daGas: 50_000 },
};

// The one failure that says nothing about the payment: the send ran, and the
// wallet handed back no gas figures to size it by.
const UNMEASURED = /Gas usage metadata/;
const words = e => String(e?.message ?? e);

// How one send pays, tried in order:
//   private  from the balance already inside the contract;
//   mint     from a gas deposit Aztec has carried and nobody has minted yet
//            (it is claimed, minted and spent from in this same transaction);
//   own      from the account's own Fee Juice, as before.
// `estimate(how, cap, item)` runs the send with that payment and answers its
// gas settings, never above `cap`. A way that fails there — too little in it,
// a deposit already spent, anything — is passed over for the next. Only a
// send that ran but came back unmeasured keeps its way, at the fixed limits
// (`settings: null`), and only when what is there covers their `ceiling`.
export async function choose({ balance, ceiling, pending, estimate }) {
  if (balance > 0n) {
    try {
      return { how: 'private', settings: await estimate('private', balance) };
    } catch (e) {
      if (UNMEASURED.test(words(e)) && balance >= ceiling) return { how: 'private', settings: null };
    }
  }
  for (const item of pending) {
    if (!item.ready) continue;
    try {
      return { how: 'mint', item, settings: await estimate('mint', item.amount, item) };
    } catch (e) {
      if (UNMEASURED.test(words(e)) && item.amount >= ceiling) return { how: 'mint', item, settings: null };
    }
  }
  return { how: 'own' };
}

// Sends one transaction, privately paid when it can be. `pay` answers how
// (`choose`'s answer with its send options), `send(options)` sends, and
// `reached()` counts what has been handed to Aztec's node. A privately paid
// send that fails BEFORE anything reached the node is tried once more from
// the account's own gas; after that, or when that fails too, the first
// failure is the one the person reads.
export async function sendPaying({ pay, send, reached, log = () => {} }) {
  let paid = { how: 'own' };
  try {
    paid = (await pay()) ?? paid;
  } catch (e) {
    log('privateFeesSkipped', { error: words(e).slice(0, 160) });
  }
  if (paid.how === 'own') return { receipt: await send(undefined), paid: 'own', gasNonce: null };
  const before = reached();
  try {
    return { receipt: await send(paid.options), paid: paid.how, gasNonce: paid.item?.nonce ?? null };
  } catch (first) {
    if (reached() !== before) throw first; // it may be in a block: never send it twice
    log('privateFeesFellBack', { how: paid.how, error: words(first).slice(0, 160) });
    try {
      return { receipt: await send(undefined), paid: 'own', gasNonce: null };
    } catch {
      throw first;
    }
  }
}
