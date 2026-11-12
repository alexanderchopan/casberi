# Vendored dependencies

What the app links that is not fetched by Swift Package Manager, where each comes from, and how to check it.

| Folder | What it is | Source | In git |
| --- | --- | --- | --- |
| `swift-secp256k1/` | The `P256K` Swift module and the `libsecp256k1` C library. | `21-DOT-DEV/swift-secp256k1` 0.21.1, revision `8c62aba8`, cut down to the two targets the app links. One patched line, marked `§738` in `Sources/P256K/UInt256.swift`. MIT. | Yes, as source. |
| `TorKit/` | Tor, embedded: tor 0.4.9.14, libevent 2.1.13, OpenSSL 3.6.5. iOS only; there is no Mac Catalyst slice. | `iCepa/Tor.framework` release `v409.14.1`, repackaged as a static library. | Yes, as `tor.xcframework.zip`. |
| `TDLib/` | Telegram's client library. | Built from Telegram's source at commit `4c6377aa` by `scripts/tdlib.sh`. | No. Built into a local cache and linked here. |

The Aztec prover is also fetched rather than committed: `scripts/aztec-engine.sh` downloads Aztec's official v6.0.0 static libraries from the `AztecProtocol/aztec-packages` release into `Casberi/vendor/aztec/`.

## Checking the Tor binary

`TorKit/tor.xcframework.zip` is the one binary committed here. `scripts/tor-repackage.sh` rebuilds it from the upstream release:

1. Downloads `tor-nolzma.xcframework.zip` for the pinned tag.
2. Refuses it unless its SHA-256 is `3582f1ebaeeff3e0b7178de6ff536c54b61ca1b598332affd6631e34ecbdf531`.
3. Lifts the static archives out of the device and arm64 simulator slices, strips debug and local symbols, and wraps them as a library xcframework.

```sh
scripts/tor-repackage.sh
```

The committed zip's SHA-256 is `7a683917b0645106a9b9b6bc6b00b7a25e8d206fb1295f4ee43e6ffe4cf00935`. A rebuild is not guaranteed to match it byte for byte, because zip records file times; compare the two `libtor.a` archives inside instead.

Only tor's C embedding API is used (`feature/api/tor_api.h`), restated in `TorKit/Sources/TorShim/`.
