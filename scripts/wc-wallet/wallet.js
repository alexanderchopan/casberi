// A wallet-side WalletConnect client, so the app's dapp-side handshake can be
// verified end-to-end with no wallet app and no device.
//
// Why this exists: `-wcConnectProbe` alone STUBS the open step (there is no
// wallet on the simulator), so headless it can only ever prove the mint. The
// half that carries the promise — settle → read → teardown — needs something
// on the other end that actually approves. This is that something.
//
// It pairs with the URI the probe minted, approves with chosen accounts, and
// then asserts the thing the Wallet screen claims in words: that nothing
// survives the handshake. `session_delete` received + zero live sessions on the
// WALLET side is that claim as a test, checked from the side that would have
// been asked to sign.
//
// Driven by ../wc-handshake.sh — see that file for usage. Exit codes:
//   0  the handshake completed and nothing survived
//   1  a session survived, or the wallet never saw session_delete
//   2  no proposal arrived before the timeout
//
// The package is CJS behind an ESM shim: the client is the NAMED export, not
// the default (the default is the whole module object).
import { SignClient } from '@walletconnect/sign-client'

const [uri, projectId] = process.argv.slice(2)
if (!uri || !projectId) {
  console.error('usage: node wallet.js "<wc: uri>" "<projectId>"')
  process.exit(2)
}

// Which namespaces this wallet is willing to approve. The point of APPROVE_NS
// is simulating a wallet that does NOT know Solana: it approves eip155 only
// while the proposal also asks for solana, which is the case proving the
// Solana arm can't regress wallets that predate it.
const APPROVE_NS = (process.env.APPROVE_NS || 'eip155,solana').split(',')
const EVM_ACCOUNTS = (process.env.EVM_ACCOUNTS ||
  '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045').split(',')
const SOL_ACCOUNTS = (process.env.SOL_ACCOUNTS ||
  '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM').split(',')
// Restrict which solana chain ids this wallet recognises, to simulate one keyed
// only to the legacy mainnet id (or only to the current one). Casberi proposes
// both on purpose — see WalletConnectBridge.solanaMainnetChains.
const SOL_CHAIN_FILTER = process.env.SOL_CHAIN_FILTER || ''
// How long to wait for the app to disconnect before reporting. Not politeness:
// too short and a slow teardown reads as a survived session (a false alarm on
// the one assertion that matters).
const DELETE_WAIT_MS = Number(process.env.DELETE_WAIT_MS || 8000)

const log = (...a) => console.log('[wallet]', ...a)

const client = await SignClient.init({
  projectId,
  metadata: {
    name: 'Casberi handshake probe',
    description: 'Wallet-side client for verifying the read-only handshake',
    url: 'https://casberi.app',
    icons: [],
  },
})

let deleted = false
client.on('session_delete', () => {
  deleted = true
  log('SESSION_DELETE received — the app tore the session down')
})

client.on('session_proposal', async (proposal) => {
  const { id, params } = proposal
  const req = params.requiredNamespaces || {}
  const opt = params.optionalNamespaces || {}
  const all = { ...req, ...opt }
  log('proposal received')
  log('  requiredNamespaces:', JSON.stringify(req))
  log('  optionalNamespaces:', JSON.stringify(opt))

  // The claim under test. A non-zero here means the Wallet screen's "watching
  // can never trade or move funds" is false — this is the machine-checkable
  // form of that sentence, read off the wire rather than off our own source.
  const methods = Object.values(all).flatMap((n) => n.methods ?? [])
  const events = Object.values(all).flatMap((n) => n.events ?? [])
  const asksNothing = methods.length === 0 && events.length === 0
  log(`  ASKED FOR: methods=${methods.length} events=${events.length}`,
      asksNothing ? '✅ nothing' : `❌ ${methods}/${events}`)
  if (!asksNothing) {
    log('❌ the proposal asks for capabilities — the read-only promise is BROKEN')
    process.exit(1)
  }
  // Anything required would be a capability we could be refused for; Casberi
  // routes everything to optional on purpose.
  if (Object.keys(req).length) {
    log('❌ requiredNamespaces is non-empty — a wallet could be forced to refuse')
    process.exit(1)
  }
  log('  namespaces proposed:', Object.keys(all).join(',') || '(none)')

  const namespaces = {}
  for (const ns of Object.keys(all)) {
    if (!APPROVE_NS.includes(ns)) {
      log(`  ✋ refusing namespace "${ns}" (this wallet doesn't know it)`)
      continue
    }
    let chains = all[ns].chains ?? []
    if (ns === 'solana' && SOL_CHAIN_FILTER) {
      chains = chains.filter((c) => c === SOL_CHAIN_FILTER)
      if (!chains.length) { log('  ✋ no recognised solana chain id'); continue }
      log(`  solana: recognising only ${SOL_CHAIN_FILTER}`)
    }
    const accts = ns === 'solana' ? SOL_ACCOUNTS : EVM_ACCOUNTS
    // Every account on every chain — what a real multi-chain approval looks
    // like, and the shape that produced the duplicate-address bug.
    namespaces[ns] = {
      chains,
      accounts: chains.flatMap((c) => accts.map((a) => `${c}:${a}`)),
      methods: [],
      events: [],
    }
  }
  log('  approving namespaces:', Object.keys(namespaces).join(',') || '(none)')

  const { topic, acknowledged } = await client.approve({ id, namespaces })
  log('approved, topic:', topic)
  await acknowledged()
  log('acknowledged by the app')

  setTimeout(() => {
    const live = client.session.keys.length
    log(`RESULT: session_delete=${deleted} liveSessionsOnWalletSide=${live}`)
    log(deleted && live === 0
      ? '✅ nothing survived the handshake'
      : '❌ a session SURVIVED — the read-only promise is false')
    process.exit(deleted && live === 0 ? 0 : 1)
  }, DELETE_WAIT_MS)
})

await client.core.pairing.pair({ uri })
log('paired, waiting for proposal…')
setTimeout(() => { log('timed out waiting for a proposal'); process.exit(2) }, 60000)
