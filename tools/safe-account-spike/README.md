# "Your account" on a testnet: the Safe harness

A throwaway iPhone app that runs the account `docs/safe-wallet-spec.md` describes,
on **Base Sepolia**, before any of it is built into Casberi:

- a **Safe 1.4.1** whose one owner is Safe's own **shared passkey signer**, set up
  with this iPhone's **Secure Enclave** key (Face ID on every signature);
- gas paid **from the account's own balance** through Safe's **4337 module** and a
  **public bundler** (Pimlico's, then Candide's: keyless, interchangeable);
- **a new key with a send**: the same transaction pays and moves the account to
  the next Enclave key, and the previous key is then refused.

Every contract is Safe's, at the addresses in Safe's own deployment records
(prd §1380: nothing of ours on chain). The SafeOp hash comes from the module
itself (`getOperationHash`); the WebAuthn bytes are Casberi's §913 encoder,
compiled in unmodified (`SafeWebAuthnSignature.swift` and its three neighbours).

## The no-funds check (Mac, software key)

```sh
M=Casberi/Casberi/Model; S=tools/safe-account-spike
xcrun swiftc -O -parse-as-library -o /tmp/safe-check $M/SafeTransaction.swift $M/Keccak256.swift \
  $M/ClearSign.swift $M/SafeWebAuthnSignature.swift $S/App/SafeSpike/Core/*.swift $S/check/main.swift
/tmp/safe-check
```

It asks the factory for the address, has the bundler simulate the creating send
(with a balance override, so no funds), reads the SafeOp hash, signs it, and has
the chain verify the signature. Passed 2026-10-19, plain and with the rotation.

## On the phone

Build `App/SafeSpike.xcodeproj` for the device (signing as in
`tools/aztec-phone-spike/scripts/run-on-phone.sh`). The app shows the account's
address: send it about **0.001 Base Sepolia ETH** from a faucet, then:

1. **Check (no funds needed)**: estimate, sign, the chain's verdict.
2. **Send 1 wei to yourself**: the first send creates the account.
3. **Send with a new key**: pays and rotates in one transaction; the header then
   reads "answers to this key ✓", read from the chain.
4. **Try the previous key**: must be refused by the bundler.

`-autocheck YES` runs step 1 at launch for a console-only run.
