# Dependencies

Every third-party piece the app ships, with its version, where it comes from and its licence. Versions are pinned: Swift packages in `Package.resolved`, npm packages exactly in each `package.json` and lockfile, and the rest by commit or checksum.

The full licence texts shown inside the app are in [`Casberi/Casberi/Resources/Licenses.md`](../Casberi/Casberi/Resources/Licenses.md).

## Swift packages

Fetched by Swift Package Manager. Pinned in `Casberi/Casberi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Package | Version | Source | Licence | Used for |
| --- | --- | --- | --- | --- |
| reown-swift | 2.3.0 | `reown-com/reown-swift` | WalletConnect Community License | WalletConnect: connecting to outside wallets and apps. |
| yttrium | 0.10.57 | `reown-com/yttrium` | Apache 2.0 | A dependency of reown-swift. |
| wallet-mobile-sdk | 1.1.2 | `MobileWalletProtocol/wallet-mobile-sdk` | Apache 2.0 | A dependency of reown-swift (Coinbase Wallet). |
| QRCode | 14.3.1 | `WalletConnect/QRCode` | MIT | A dependency of reown-swift. |
| swift-qrcode-generator | 1.0.3 | `dagronf/swift-qrcode-generator` | MIT | A dependency of QRCode. |
| SwiftImageReadWrite | 1.1.6 | `dagronf/SwiftImageReadWrite` | MIT | A dependency of QRCode. |

## Vendored in this repository

See [`Vendor/README.md`](../Vendor/README.md) for how to check each.

| Piece | Version | Source | Licence | Used for |
| --- | --- | --- | --- | --- |
| swift-secp256k1 | 0.21.1 (`8c62aba8`), one patched line | `21-DOT-DEV/swift-secp256k1` | MIT | secp256k1 signatures. |
| Tor | 0.4.9.14, with libevent 2.1.13 and OpenSSL 3.6.5 | `iCepa/Tor.framework` v409.14.1, pinned by SHA-256 | BSD (tor, libevent), Apache 2.0 (OpenSSL) | Routing wallet reads through Tor on iOS. |

## Fetched at build time, not committed

| Piece | Version | Source | Licence | Used for |
| --- | --- | --- | --- | --- |
| TDLib | commit `4c6377aa` | `tdlib/td`, built by `scripts/tdlib.sh` | Boost Software License 1.0 | Telegram messages. |
| Barretenberg | v6.0.0 static libraries | `AztecProtocol/aztec-packages` release, fetched by `scripts/aztec-engine.sh` | Apache 2.0 | Aztec's prover. |

## JavaScript engines

Each is bundled from the packages below, which are the direct dependencies; the lockfile in each folder pins everything under them. The first two bundles are committed and reproducible (`node build.mjs --check`).

| Engine | Direct dependencies | Licences |
| --- | --- | --- |
| Privacy Pools (`tools/privacy-pools-engine`) | `@0xbow/privacy-pools-v2-sdk` 1.0.2, `snarkjs` 0.7.5, `circomlibjs` 0.1.7, `viem` 2.45.3, `@zk-kit/lean-imt` 2.2.4 | MIT, except snarkjs and circomlibjs: GPL 3.0 |
| Railgun (`tools/railgun-engine`) | `@railgun-community/wallet` 11.3.0, `engine` 9.9.1, `shared-models` 8.2.1, `waku-broadcaster-client-web` 10.0.1, `ethers` 6.14.3, `snarkjs` 0.7.5, and browser shims (`buffer`, `crypto-browserify`, `stream-browserify`, `level-js`, `memdown`, `events`, `util`, `assert`, `path-browserify`, `process`) | MIT, except snarkjs: GPL 3.0; Waku's packages MIT or Apache 2.0 |
| Aztec (`tools/aztec-engine`) | `@aztec-labs/aztec.js`, `accounts`, `foundation`, `wallet-sdk`, `wallets` 6.0.0, `@alejoamiras/private-fee-juice` 6.0.0 | Apache 2.0 (Aztec), MIT (private-fee-juice) |

## Data bundled with the app

| Piece | Source | Licence |
| --- | --- | --- |
| ERC-7730 clear-signing registry | The Ethereum Foundation's registry, bundled as `Resources/ClearSignRegistry.json` by `scripts/clearsign-registry.py` | CC0 1.0 |

## Apple frameworks

Everything else is Apple's SDK: SwiftUI, SwiftData, CloudKit, CryptoKit, LocalAuthentication, WebKit and the rest. No analytics, advertising or crash-reporting SDK is linked.
