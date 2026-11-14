# Redesign list, 2026-11-13

Gathered by walking a new account screen by screen on the simulator with the
user (the create walk, Wallet › Account and its doors, then every Move verb).
Nothing here is ruled as a design yet: each item is what is wrong and what the
user asked for. Rulings land in `docs/prd.md` as each is designed.

## To redesign

### Making an account
1. **"Your wallet, privately."** Look better; the Aztec line says Aztec to Aztec.
2. **Round-ups**, in the walk and under Account › Spending. No pill buttons;
   amounts as the large rows Move uses for sums; on/off before the amount; far
   less text.
3. **The walk's last screen** ("Ready ...218a on Base, Ethereum, and
   Robinhood."). What "Ready" means; a clearer line about which networks the
   address works on.

### Account
4. **The top box.** Make it plain this is the public account and address.
8. **Keys.** One "Backup" row replaces "Recovery keys" and "Private balance",
   with three states: Add (no recovery key yet), "iCloud Keychain" (all
   saved), "Not backed up" with "Turn on iCloud Keychain" (iCloud is off).
   "Private keys · Export" gets a name that says it is the way out to another
   wallet.
9. **Savings goal.** Say what it is (a target for your private balance, filled
   by round-ups and what you send there) and what "By a date" gives (how much
   a week gets you there); Save at the foot; decide where it is tracked. With
   item 2, consider a "Saving" section in place of "Spending".
10. **Nodes.** A sheet like Round-ups, its row under Connection.

### "Which address do I give out?" (one design)
5. **Receive to your private balance** (the sheet from Account). Total redesign.
6. **Add money from Ethereum**, the Human Passport state.
7. **Send from Aztec to Aztec**, and its "needs gas first" state.
14. **Receive** in Move: the three doors carry the weight of the Network row;
    each address named for what it is; no half-finished sentence.

### Move
13. **One template for every verb**: amount as a list of sums with the keys
    behind "Another amount", typed in the row and never in the sentence; the
    act button grey until the sentence is whole; nothing picked for you; menus
    open below their rows; one capitalised line under the rows; what shows
    while it reads; what shows when you have nothing to use the verb with.
11. **Buy.** The address and the hand-off to Stripe.
15. **Swap.** Token A on network A to token B on network B: two matching
    pairs, every combination one swap, nothing pre-picked. "When" drawn as a
    choice. Moving to another network is a swap like any other.
16. **Sweep.** Match the template; say what it does; a row for the $1 or $5
    line; dollars shown consistently, before ETH.
- Notes under the template. **Lend:** "on Aave on Base" repeats "on"; two
  lines say the same thing. **Spend:** "Spend $0 gift card" is missing a word;
  four lines of placeholders; the name does not say it buys a gift card;
  token units where Send shows dollars. **Send:** Amount stands before Token
  in the rows though the token is asked first.

### Everywhere
12. **A network always shows its icon** wherever it is named: rows, menus, a
    badge on a token's icon, the Account page. Not inside Move's sentence.

## To consider
- The grey word in a title is the way back and does not look like a button.
- Networks' names are shown small to fit one line.

## To fix
- "Your account ...218a on ." (the found-account screen) is missing its network.
- The walk's counter changes from "of 4" to "of 3" midway.
- "New account" ended on the already-found address.
- Private balance sheet: the copy row is cut off by the foot; its back button
  goes to Move's menu, not back to Account.
- Whether "Recovery keys: iCloud Keychain" is true with iCloud off.
- Move's button covers the bottom right corner when a page is scrolled.
- "2 of 3" for your own account is no longer said anywhere.
