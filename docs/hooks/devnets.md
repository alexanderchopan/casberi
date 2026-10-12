# The devnets

**Hegotá Frames is deleted (prd §1206, 2026-10-08), model and all** (§723). Its probes
(`-framesProbe`, `-framesTxProbe`, `-framesKeyProbe`, `-framesPendingProbe`,
`-framesPasskeyProbe`, `-framesStitchProbe`), its `casberi://frames/sponsor` deep link, its
encoder self-test and its nightly drift rows went with it; the retired seats' sweep
(`SourceRename.sweepRetiredSeats`) drops its seat record, its `frames` address-book tag, its
`frames.` defaults and its two Keychain services. The entries that lived here are in git
history. The one remaining testnet, **Logos**, is documented in `docs/hooks/bridges.md`
(`-logosWatch`, `-logosProbe`, `-logosRewind`, `-logosNode`).

## Kept, because the lesson is not Frames'

- **Two surfaces on one card reading DIFFERENT STORES is a contradiction no render can show (prd §837).** The Privacy devnet's Home (deleted with its seat, prd §1038) said "Nothing on this chain from the 4 addresses you watch, yet." over 1.0000 ETH and a line falling 983,579 ETH (-100.0%): the sentence read the live walk, the crown read `RoomValueHistory`, and a relaunch had emptied one and not the other. A DERIVED line (Frames) needs no fence, because a relaunch takes the moves with it; a SAMPLED line must answer to the same store as the sentence over it. And a ratio may not claim a wipeout the number above denies (`TokenChartStyle.readsAsWipeout`, `isFlat`'s mirror at -99.95%) → prd §837 · §610 · §83

## Aztec (prd §1270, 2026-10-11)

`-aztecWatch "network|<attester or account>[,…]|clear"` — follow the Aztec testnet (v6), sequencers by L1 attester address (20 bytes) and accounts (32 bytes), read once, and NSLog `aztecWatch:` lines: each add's result (`added`, `addedAccount`, `alreadyFollowing`, `invalid`), then `+N | proposed= | proven= | lag= | fee=`, then each sequencer's `duty | stake | schedule | epochs=` (or `UNSEEN`), then each account's `feeJuice=` (prd §1271). Run twice to see a transition: a first reading lands nothing by design. **The hook does not register the seat** (no page sync), so the Testnets room appears only after the Aztec page has synced once: `-deeplink casberi://account -connectTap Aztec` opens it, and its connect lands in the room. Then `-openRoom Testnets -openSection node` for the Node tile.
