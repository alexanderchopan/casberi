# Tools

JavaScript and contract code that sits beside the app. Nothing here runs on a server.

## Shipped: built into the app

| Folder | What it builds |
| --- | --- |
| `aztec-engine/` | The Aztec account engine the app runs in a hidden web view. Built by `scripts/aztec-engine.sh`. |
| `privacy-pools-engine/` | 0xBow's Privacy Pools SDK, bundled as `Resources/privacy-engine.js`. `pins.mjs` pins what it may load. |
| `railgun-engine/` | Railgun's wallet SDK, bundled as `Resources/railgun-engine.js`. |
| `aztec-account/` | The Aztec account contract (`contract/src/main.nr`) and its deployment tooling. |
| `aztec-signer/` | The computer half of the testnet signer whose key is the phone's Secure Enclave key. |

## Spikes: measurements, not app code

| Folder | The question it answered |
| --- | --- |
| `safe-account-spike/` | The Safe account on Base Sepolia, before it was built into the app. |
