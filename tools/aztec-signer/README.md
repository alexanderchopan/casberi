# Casberi's Aztec testnet signer (computer half)

Runs an Aztec **testnet** account whose only key is your phone's Secure Enclave key. The phone shows every request it is asked to sign, rebuilt from the calls themselves, and refuses anything that is not an Aztec testnet (prd §1276).

```sh
cd tools/aztec-signer && npm install
node signer.mjs account <public key from Casberi › Aztec › Copy signing key>
node signer.mjs demo
```

Each request opens as a QR code: scan it with the iPhone camera, or paste the link from Universal Clipboard on the Aztec page, then tap Sign. The signature comes back on the clipboard. The phone also accepts whatever testnet rollup Aztec's node reports, so a testnet reset does not stop it (prd §1419). `--sim <udid>` drives a simulator instead. State lives in `~/.casberi-aztec-signer/`. Test money only; the stock account has no key recovery.
