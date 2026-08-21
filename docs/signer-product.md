# The Casberi co-signer — product description and user flow

**Ruling: prd §425. Mechanics: `docs/signer-spec.md`. Amendments: §426 (the build), §427 (the
N-of-N hazard and the quiet key death).**

**Grade: BUILT, UNSIGNED.** Every flow below exists in the app and compiles; none of it has been
run against a real Safe on a real device. Nothing here is marketing copy yet — it is what the
product *is*, written so the website copy, the App Store text and the catalog summary can be cut
from one source instead of three.

---

## 1. The product in one sentence

**Your computer can't spend without your phone's yes.**

## 2. The paragraph

Casberi generates a signing key that lives and dies on your phone, behind Face ID. You add that
key as one owner of a Safe — a multisig — and set it to need two signatures. From then on your
desktop wallet can *propose* a transaction and cannot *send* one. The second yes has to come from
your phone, where the transaction is rendered a second time, by different software, from the
chain's own data.

The key holds no money, never needs gas, has no recovery phrase, and is never exported.

## 3. Why the promise is unusually strong

Most "secure wallet" claims are policies: we promise not to do the bad thing. This one isn't.

A Safe with a threshold of 2 **will not execute on one signature** — that is arithmetic in a
contract nobody involved controls. Casberi cannot spend your money because the chain won't let it,
not because we decided not to.

The catalog's existing honesty ladder runs MINTED (the service issued a read-only token) → SCOPED
(you ticked a box) → CONDUCT (we simply never call the write). This sits above all three.

## 4. What it defends, stated exactly

**It defends against a compromised computer.** Your browser wallet is the one exposed to every
dapp, every signature request and every phishing page. Under this setup, a drained desktop key
produces an unsigned request sitting on your lock screen instead of a transfer. That is how a bank
already works, which is why it needs no explaining.

**It does not defend against someone holding your unlocked phone.** Two keys on one phone would be
two witnesses, not two locks. The copy must never imply otherwise.

**It protects money in the Safe, at a new address.** An existing wallet is not upgraded in place —
it becomes the proposer. That cost is real and belongs in the pitch, not underneath it.

## 5. What Casberi deliberately cannot do

| | |
|---|---|
| Execute a transaction | Another owner sends it. Casberi would need gas and would stop being a pure co-signer. |
| Sign anything but a Safe transaction | No `personal_sign` of arbitrary text, no free-form typed data, no `eth_sendTransaction`. Enforced by a build-failing grep, not a promise. |
| Export the key | One function reads the private bytes. A second reader fails the build. |
| Sign on a 1-of-N Safe | That would be a custodial wallet wearing a multisig's clothes. |
| Sign a hash it worked out alone | It asks the Safe contract for the same hash first and refuses on any disagreement. |
| Summarise calldata it couldn't read | It shows the selector and the hash and says so. |
| Send anything else, anywhere | One outbound write exists in the whole app: 65 bytes of signature to Safe's own service. |

---

## 6. Setup — one tap and an address

**Where:** Apps → Safe.

1. **"Make this phone a signer."** One tap. No form, no toggle, no account.
2. Casberi generates a secp256k1 key, stores it behind Face ID, and shows you the address with a
   copy button. The address joins your address book as **"This phone."**
3. One instruction: *"Add this address as an owner from your other wallet and set the threshold
   to 2. Casberi will notice when you have."*
4. One warning, spent on the cost rather than the pitch: *"The key stays on this phone behind Face
   ID. There is no recovery phrase, and re-enrolling Face ID erases it — so give the Safe a third
   owner you keep somewhere else."*

**If you don't have a Safe yet**, the instruction changes and a **Set up a Safe** door appears,
opening Safe's own create flow in your browser. It shows only when the lookup answered AND found
nothing — never from a read that failed, because offering that to somebody who already runs three
Safes is a suggestion that costs gas.

**Casberi signs nothing during its own onboarding.** Registration happens entirely in your other
wallet; the app just watches the chain until it sees itself listed. There is no "connected" flag —
ownership is read from the chain every time it matters.

### The one thing setup must get across

Once Casberi can see your Safe, the screen states its shape. If the Safe needs **every owner it
has** — 2-of-2, 3-of-3 — it says so about *your* Safe, in red:

> `0x1234…7890` needs 2 of its 2 owners, so every one of them is load-bearing. If this phone is
> lost or its Face ID is re-enrolled, that Safe can never be signed for again — and its owners
> can't be changed either, because that takes a signature too. Add one more owner.

That last clause is the part nobody expects: **an N-of-N Safe cannot be repaired.** Changing owners
or the threshold is itself a Safe transaction and needs the threshold met. There is no admin path.

Otherwise it says the quiet version: *"Signing for 1 Safe. Losing this phone would still leave
enough owners to change that (1 to spare)."*

---

## 7. The ask — the flow that is the product

1. **A transaction is proposed** from your desktop wallet.
2. **Your phone buzzes.** An alarm-class notification, break-through if you've allowed it:
   *"Your signature is needed."*
3. **The row is in your feed** like everything else Casberi holds — and it stays there afterwards,
   so the corpus ends up with the whole arc: proposed → signed → executed.
4. **Tapping it opens the transaction as a money receipt with a torn-off bottom edge missing** —
   flat, because in this app a flat edge means the paper is still in the machine.
5. **Under it, who is waiting.** Each owner's face, lit if they've signed. *"Yours is the last
   signature needed."*
6. **Under that, what it actually does** — read from the raw calldata, not from anybody's summary:
   *"Transfers 1000000 base units of `0xa0b8…eb48` to `0xABcd…abCD`."*
7. **Sign.** Face ID. The signature is posted to Safe's service and the block reads *"Signed from
   this phone."*
8. **Another owner executes it.** The edge tears when it does.

### Between steps 4 and 7, four things are checked against the chain

Not against a cache, because a cache is what an attacker with your desktop key would beat:

- the threshold is 2 or more;
- this phone is currently an owner;
- Safe's own `getTransactionHash` agrees with the hash Casberi computed;
- and the transaction hasn't already executed or already been signed by you.

Any disagreement, or any failure to read, and there is no Sign button — only a sentence saying
which.

---

## 8. Every state, and what it says

| State | What you see |
|---|---|
| No key yet | *Make this phone a signer* |
| Key made, not yet an owner | *This phone isn't an owner of this Safe yet. Add its address from your other wallet.* |
| Threshold is 1 | *This Safe executes on 1 signature, so signing here would let one key spend on its own. Raise the threshold to 2 first.* |
| Chain unreachable | *Couldn't reach the chain to re-check this transaction, so Casberi won't sign it.* |
| **Hashes disagree** | *The Safe's own hash for this transaction doesn't match what Casberi worked out. Don't sign this anywhere until you know why.* |
| Unsupported chain | *Casberi can't sign on this chain — it can't re-check the hash against the Safe there.* |
| Calldata unreadable | *Casberi can't read what this does. It calls `0xdeadbeef` on `0xa0b8…eb48`. Hash `0x7be6…cc8d`.* |
| A batch | *Casberi won't summarise a batch — read it in your Safe app before signing.* |
| Safe has no spare owner | *This Safe needs every owner it has…* — **and it signs anyway** |
| …and this tx is the fix | *This is the fix: it gives the Safe an owner to spare.* |
| Face ID cancelled | *Face ID didn't unlock the key.* |
| **Key destroyed** | *This phone's signing key is gone — Face ID was re-enrolled, which erases it by design.* |
| Signed, service down | *Signed, but Safe's service didn't take it — the signature is on your clipboard* |

Two of these are worth reading twice.

**The N-of-N warning is a warning and never a refusal.** In a 2-of-2 that names your phone,
refusing to sign *is* the lock — our signature is the one the Safe is waiting for. So Casberi says
the uncomfortable thing and signs.

**A signature is never thrown away.** If Safe's service is down, the 65 bytes go to your clipboard
so you can paste them into the Safe app yourself. A Face ID you already gave must not be lost to
somebody else's outage.

---

## 9. Losing the key

There are three ways this key ends, and they are not equally bad.

| | What happened | What to do |
|---|---|---|
| **You delete it** | Data tray → *Delete signing key*, or the Safe screen | Have another owner `swapOwner` the address out **first** |
| **Face ID re-enrolled** | Added an alternate appearance, reset Face ID, TrueDepth repair. The key is erased by design. | Make a new key; another owner swaps the old address out |
| **Phone lost or wiped** | Same result | Same fix |

In each case the Safe itself is fine **as long as it has an owner to spare**. In an N-of-N it is
not fine, it is finished — which is why §7's warning exists and why the setup copy steers toward
2-of-3 rather than 2-of-2.

**There is no recovery phrase, and that is the design.** A phrase in a drawer is a second copy of
the key, which is exactly what "this phone's yes" cannot survive. Recovery lives one level up: the
threshold *is* the recovery story. That also means Casberi skips the entire backup ceremony every
other wallet app is stuck with — setup is one tap and an address on screen.

---

## 10. Positioning

**Catalog tagline and summary — what actually ships** (`BridgeCatalog.offers`, guarded by
`scripts/safetx-selftest.sh`, which fails the build if the offer claims signing happens elsewhere
or names the pitch without its limits):
> **Your Safe's queue — and this phone as a signer**
>
> Watch a Safe — or just your own wallet, if it's one of the signers — and its pending signature
> queue lands in your feed.
>
> This phone can also be one of the Safe's owners. Make a key here, add it from your other wallet,
> set the threshold to 2, and your computer can't spend without your phone's yes.

**Setup intro (two sentences, the §315 budget):**
> No account here — it reads the wallets you already watch, so you're told when a transaction is
> waiting on your signature. This phone can also be one of the Safe's owners, so your computer
> can't spend without your phone's yes.

**Website hook:**
> Every other wallet asks you to trust it with your keys. This one asks the chain to make that
> unnecessary.

**What NOT to say**
- Anything implying protection from a stolen phone.
- "Hardware-wallet security" — it is a phone, and the comparison invites a claim we can't keep.
- "Your keys never leave your device" as the headline. True, and true of every wallet; the
  differentiated claim is that this key *can't spend*, not that it stays put.
- Anything about an existing wallet being protected. The Safe is a new address.

---

## 11. Before any of this ships

A device test against a real 2-of-3 Safe holding trivial funds (`docs/signer-spec.md` §10, step 9).
No simulator has a Secure Enclave gesture and no test here can make a Safe execute, so nothing
before that counts as evidence that any of the above works.
