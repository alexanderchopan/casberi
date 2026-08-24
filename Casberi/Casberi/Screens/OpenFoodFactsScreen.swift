import SwiftUI
import SwiftData
import VisionKit

/// The Open Food Facts things already in the corpus — newest first.
private let offRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Open Food Facts" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Open Food Facts, connected — scan or enter a grocery barcode and the product
/// lands in your feed from the open food database. Keyless: no account, nothing
/// leaves the device but the barcode. Read-only.
struct OpenFoodFactsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var scanning = false
    @State private var code = ""
    @State private var looking = false
    @State private var lastResult: String?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen`.
    @State private var lastResultIsError = false
    @FocusState private var fieldFocused: Bool

    @Query(offRecentDescriptor) private var recent: [Thing]

    /// Whether the catalog seat exists at all — the honest gate for Disconnect.
    private var seated: Bool { store.bridges.contains { $0.id == "off" } }

    /// The live scanner only runs where the camera can (a real device); the sim,
    /// older hardware, and Mac Catalyst (DataScannerViewController is unavailable
    /// there entirely) fall back to entering the number.
    private var canScan: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Open Food Facts",
                mode: .noAccount,
                intro: "No account and no key — scan a barcode and what's in it lands in your feed. Nothing about you leaves this \(DS.device) but the barcode itself.")
            if !recent.isEmpty {
                RoomDoor(name: "Open Food Facts", source: "Open Food Facts")
                    .listRowSeparator(.hidden)
            }
            scanSection.listRowSeparator(.hidden)
            // Gated on the SEAT, not on what landed (audit, 2026-07-31).
            // Someone who connected and whose every lookup then failed had a
            // registered bridge and no way to remove it from its own screen.
            if seated {
                BridgeDisconnectSection(bridgeID: "off", name: "Open Food Facts", teardown: {})
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Open Food Facts")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Open Food Facts")
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $scanning) {
            BarcodeScannerSheet { scanned in
                scanning = false
                Task { await lookUp(scanned) }
            }
        }
        #endif
    }

    /// Slabbed, and its result moved out of the section header (§218 + audit,
    /// 2026-07-31). Three things were wrong here at once: the scan button was a
    /// hand-painted tint capsule where every other screen's primary act is a
    /// `DSSlabButton`; the field was the last `BridgeFieldRow` holdout beside
    /// it; and `lastResult` rendered as `label12`/tertiary text in the section
    /// header, so "Not found in Open Food Facts." looked exactly like
    /// "Added Nutella" — no red, no shake, no failure haptic, the only screen
    /// in the family where success and failure were indistinguishable.
    private var scanSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if canScan {
                    DSSlabButton(title: String(localized: "Scan a barcode"),
                                 systemImage: "barcode.viewfinder") {
                        DSHaptic.tap()
                        scanning = true
                    }
                }
                DSSlabField(placeholder: String(localized: "Barcode number"),
                            text: $code, actionLabel: String(localized: "Look up"),
                            keyboard: .numberPad, focus: $fieldFocused,
                            action: { Task { await lookUp(code) } })
                BridgeSyncStatusRows(syncing: looking,
                                     syncingLine: String(localized: "Looking it up…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                DSSlabNote(text: "The product lands in your feed with its name, picture, and Nutri-Score.")
            }
        }
        .dsSlabSection()
    }


    private func lookUp(_ raw: String) async {
        // A lookup already in flight is NOT a bad barcode. One `else` covering
        // both guard clauses meant tapping Look up during a live lookup
        // reported "That isn't a barcode number." about a perfectly good one
        // (audit, 2026-07-31) — so the in-flight case returns silently, the way
        // every other screen's `!syncing` guard does.
        guard !looking else { return }
        let barcode = raw.filter(\.isNumber)
        guard barcode.count >= 8 else {
            if !barcode.isEmpty { fail(String(localized: "That isn't a barcode number — they're at least 8 digits.")) }
            return
        }
        looking = true
        defer { looking = false }
        fieldFocused = false
        guard let food = await OpenFoodFacts.lookup(barcode) else {
            fail(String(localized: "Not found in Open Food Facts."))
            return
        }
        if OpenFoodFacts.land(food, context: modelContext) != nil {
            code = ""
            lastResult = String(localized: "Added \(food.name)")
            lastResultIsError = false
            DSHaptic.success()
            store.registerConnected(id: "off", name: "Open Food Facts",
                                    proof: "Scanned in",
                                    can: ["Looks up a barcode in the open food database.",
                                          "Read-only — nothing leaves \(DS.device) but the code."])
        } else {
            // Already here isn't a failure — it's the thing you wanted, already
            // done. No red, no shake.
            lastResult = String(localized: "Already in your feed.")
            lastResultIsError = false
        }
    }

    private func fail(_ message: String) {
        lastResult = message
        lastResultIsError = true
    }
}

/// The live barcode scanner (VisionKit), shown full-screen with a Cancel bar.
/// Reports the first barcode it reads, once. Unavailable on Mac Catalyst
/// (DataScannerViewController below), so this whole sheet is too — canScan
/// is forced false there and the fullScreenCover site is guarded to match.
#if !targetEnvironment(macCatalyst)
private struct BarcodeScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            BarcodeScanner(onScan: onScan)
                .ignoresSafeArea()
            HStack {
                Button("Cancel") { dismiss() }
                    .dsText(.body17).foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                    .background(.black.opacity(0.5), in: Capsule())
                Spacer()
            }
            .padding()
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var fired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !fired else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    fired = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
#endif
