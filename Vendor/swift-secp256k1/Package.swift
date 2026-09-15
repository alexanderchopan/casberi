// swift-tools-version: 6.0

// A vendored copy of 21-DOT-DEV/swift-secp256k1 0.21.1 (revision 8c62aba8), cut
// down to the two targets Casberi links: the `P256K` Swift module and the
// `libsecp256k1` C library under it. Symlinks resolved; the ZKP targets, the
// swift-crypto submodule and the upstream dev-only plugins are gone.
//
// Why it is vendored rather than fetched (prd §738): Xcode 27's standard library
// makes `for word in words` in `UInt256.trailingZeroBitCount` ambiguous, so the
// release no longer compiles, and every newer release (0.22.0+) builds its module
// through a plug-in §425 refused. The one patched line is marked `§738` in
// Sources/P256K/UInt256.swift. MIT licence, see LICENSE.

import PackageDescription

let package = Package(
    name: "swift-secp256k1",
    products: [
        .library(name: "P256K", targets: ["P256K"])
    ],
    targets: [
        .target(name: "P256K", dependencies: ["libsecp256k1"]),
        .target(
            name: "libsecp256k1",
            cSettings: [
                .define("ECMULT_GEN_PREC_BITS", to: "4"),
                .define("ECMULT_WINDOW_SIZE", to: "15"),
                .define("ENABLE_MODULE_ECDH"),
                .define("ENABLE_MODULE_ELLSWIFT"),
                .define("ENABLE_MODULE_EXTRAKEYS"),
                .define("ENABLE_MODULE_MUSIG"),
                .define("ENABLE_MODULE_RECOVERY"),
                .define("ENABLE_MODULE_SCHNORRSIG")
            ]
        )
    ],
    swiftLanguageModes: [.v5],
    cLanguageStandard: .c89
)
