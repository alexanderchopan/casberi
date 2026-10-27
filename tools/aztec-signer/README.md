# Casberi's Aztec testnet signer (computer half)

Runs an Aztec **testnet** account whose only key is your phone's Secure Enclave key. The phone shows every request it is asked to sign, rebuilt from the calls themselves, and refuses anything that is not an Aztec testnet (prd §1276).

```sh
cd tools/aztec-signer && npm install
node signer.mjs account <public key from Casberi › Aztec › Copy signing key>
node signer.mjs once     # one signed tx: deploy a token from the account
node signer.mjs demo     # deploy a token, mint, move some into the private balance
```

It reaches Aztec's **v6 testnet** (node 6.0.0, rollup version 679261766, Sepolia) through `aztec-testnet.drpc.org`, with the `@aztec-labs/*` 6.0.0 packages; the `@aztec/*` scope stops at 5.2.1 and v5. That endpoint refuses JSON-RPC batches of more than three, so the node client asks three at a time (`AZTEC_MAX_BATCH` overrides; `AZTEC_NODE_URL` picks another node). Fees are paid by the testnet's canonical Sponsored FPC (salt 0, `0x2d8fff82…69d3` on v6).

Each request opens as a QR code: scan it with the iPhone camera, or paste the link from Universal Clipboard on the Aztec page, then tap Sign. The signature comes back on the clipboard. The phone also accepts whatever testnet rollup Aztec's node reports, so a testnet reset does not stop it (prd §1419). Each call carries its full signature when the tool knows the contract (the Token and the sponsored fee payer), and the phone checks it against the selector the signature covers before it shows the name (prd §1446). `--sim <udid>` drives a simulator instead (a DEBUG build: it relaunches the app with `-aztecAutoSign YES`).

State lives in `~/.casberi-aztec-signer/v6/` (`AZTEC_SIGNER_HOME` overrides): a v5 PXE cannot open on v6, and an account made on v5 does not exist on v6, so each testnet gets its own account. Test money only; the stock account has no key recovery.
