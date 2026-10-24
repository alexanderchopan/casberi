// swift-tools-version: 6.0

// Tor, embedded (prd §1495). tor itself is iCepa/Tor.framework's release
// v409.14.1 (tor 0.4.9.14, libevent 2.1.13, OpenSSL 3.6.5), repackaged by
// `scripts/tor-repackage.sh` from that release's pinned checksum: its static
// archives, stripped, as a LIBRARY xcframework (`tor.xcframework.zip`, ~10 MB).
// The release wraps them as deep framework bundles, which Xcode embeds and then
// refuses on iOS; a library is linked and never embedded. Only tor's C
// embedding API is used (`feature/api/tor_api.h`), restated in `TorShim.h`.
//
// Device and arm64 simulator slices, and NO Mac Catalyst slice (the release
// has none), so the app links `TorShim` on iOS only (`platformFilter = ios`)
// and the Mac reads directly, saying so (`TorRoute.available`). BSD licence:
// tor, libevent; Apache 2.0: OpenSSL.

import PackageDescription

let package = Package(
    name: "TorKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "TorShim", targets: ["TorShim"])
    ],
    targets: [
        .binaryTarget(name: "tor", path: "tor.xcframework.zip"),
        .target(
            name: "TorShim",
            dependencies: ["tor"],
            linkerSettings: [.linkedLibrary("z")]),
    ]
)
