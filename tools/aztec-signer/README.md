# Casberi's Aztec testnet signer (computer half)

Runs an Aztec **testnet** account whose only key is your phone's Secure Enclave key. The phone shows every request it is asked to sign, rebuilt from the calls themselves, and refuses anything that is not an Aztec testnet (prd §1276).

```sh
cd tools/aztec-signer && npm install
node signer.mjs account <public key from Casberi › Aztec › Copy signing key>
node signer.mjs demo
```

Requests reach the phone through the clipboard (Universal Clipboard: paste the link on the Aztec page, tap Sign; the signature comes back the same way). `--sim <udid>` drives a simulator instead. State lives in `~/.casberi-aztec-signer/`. Test money only; the stock account has no key recovery.
