import SwiftUI

/// Apple Intelligence, turned on (prd §833) — Apple's own model on Private
/// Cloud Compute answering the composer. No key, no account and no bill, so
/// the whole connect is one tap, and the tap ends in the conversation: the
/// sheet leaves (`finishesOnConnect`) and the composer rises, because the
/// first thing a person turning on an agent wants is to ask it something.
///
/// **The one sentence is the network fact.** The on-device answer never left
/// the phone; this one does, so the page says what goes and where before the
/// switch is thrown, and the answer's badge says it again after
/// (`Composer.provenanceBadge`). The seat changes WHICH model answers and
/// nothing else — the retriever, the candidates and the grounding rail are
/// the on-device path's, so every answer still stands on real things.
///
/// `lands: false`: an answer stores nothing, so there is no Activity count.
/// The seat exists only where Private Cloud Compute answers
/// (`Offer.needsPrivateCloud`), and the page still reads availability live,
/// because it can move after the catalogue was drawn.
struct AppleIntelligenceScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var on = AskModel.enabled
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Apple Intelligence", seatID: "appleintelligence", source: "Apple Intelligence",
            state: AccountPageState.of(name: "Apple Intelligence", seatID: "appleintelligence",
                                       connected: on, store: store),
            mode: .noAccount,
            lands: false,
            teardown: {
                AskModel.enabled = false
                on = false
            },
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
    }

    @ViewBuilder private var actBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // No "unavailable" branch: the catalogue already hides the seat
            // where the cloud cannot answer, and if that moves after the page
            // was drawn, an ask answers on the phone and its badge says so —
            // the switch is never a control that does nothing (§83).
            if on {
                DSSlabButton(title: "Ask Apple Intelligence",
                             detail: "About your things",
                             systemImage: "bubble.left.and.bubble.right") {
                    DSHaptic.tap()
                    chrome.composerRequest += 1
                }
            } else {
                DSSlabButton(title: "Turn on",
                             detail: "Free — no key, no account",
                             systemImage: "apple.intelligence",
                             action: turnOn)
            }
            DSFootnote("Your question and the saved things that answer it go to Apple's Private Cloud Compute, which Apple says keeps none of it. Everything else stays on \(DS.device).")
        }
    }

    private func turnOn() {
        AskModel.enabled = true
        on = true
        DSHaptic.success()
        store.registerConnected(id: "appleintelligence", name: "Apple Intelligence",
                                proof: String(localized: "Private Cloud Compute"))
        // The connect ends in the conversation: the sheet leaves on its own
        // (`finishesOnConnect`) and the composer rises under it.
        chrome.composerRequest += 1
    }
}
