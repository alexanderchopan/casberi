import AVFoundation
import SwiftData
import SwiftUI

/// A followed article's own words, fetched when you open it and readable
/// aloud (2026-08-23, prd §455).
///
/// WHY THIS VIEW EXISTS. `FeedArticleText` has read the body of RSS and
/// Substack rows since 2026-08-06 and `ThingContentView` has drawn it since
/// 2026-08-21 — but only for the rows the BACKGROUND sweep happened to reach.
/// That pass takes six rows per foreground inside a thirty-day window and
/// gives up after two failures, which is right for work nobody asked for and
/// means that on a corpus of several feeds most stories still had no body when
/// you opened them. The sheet then fell back to a link preview card, and the
/// only way to read the piece was to leave for the browser — in the room whose
/// whole promise is that what you follow is here.
///
/// So the tap fetches. One request, made because somebody opened the story,
/// against a page whose headline they are already reading. See
/// `FeedArticleText.fetchOnOpen` for which of the sweep's bounds are
/// deliberately not applied to it and why.
///
/// **THE PLACEHOLDER IS NOT A SPINNER OVER NOTHING.** A fetch can take up to
/// eight seconds, and an article that is arriving, an article that failed and
/// a row that was never eligible all look identical if the view simply draws
/// nothing. It says it is reading; on a miss it says nothing at all and leaves
/// the preview card above to be the answer, because "we could not read this
/// page" is a sentence about our scraper that the reader can do nothing with
/// — the door out to the site is already there.
///
/// Mounted only from `ThingContentView`, which `ThingSheetView` alone mounts,
/// so the appear-fetch below can never fire from a feed row scrolling past.
struct ArticleBody: View {
    let thing: Thing
    @Environment(\.modelContext) private var modelContext
    @State private var tried = false
    @State private var fetching = false

    /// CLAUDE.md corollary 5: a `View` struct storing a `Thing` guards its own
    /// body, because SwiftUI re-evaluates a leaf on the model's own
    /// observation with no involvement from the parent that built it.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        let body = (thing.enrichedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ArticleListenButton(id: thing.id.uuidString, text: body)
                // Defaults, unlike the generic branch: on an article the body
                // IS the thing (§366's own test), so it is set at `reading20`
                // in primary ink rather than as a footnote under a fact.
                // `markdown: false` — this is scraped prose, and nobody wrote
                // it as markdown.
                NoteProse(text: body, markdown: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)
        } else if fetching {
            Text("Reading the article…")
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s3)
        }
        // `.task` rather than `.onAppear`: it is cancelled with the view, so
        // closing the sheet mid-fetch does not leave a request running against
        // a publisher for a story nobody is looking at any more.
        //
        // `tried` is the once-per-mount guard. `FeedArticleText.fetchOnOpen`
        // has its own cross-view in-flight set (two windows, one story), and
        // this is the local half: a body evaluation is not a new intent to
        // read.
        Color.clear
            .frame(height: 0)
            .task(id: thing.id) {
                guard !tried else { return }
                tried = true
                guard thing.isLive, !FeedArticleText.hasBody(thing),
                      FeedArticleText.readableURL(for: thing) != nil else { return }
                fetching = true
                await FeedArticleText.fetchOnOpen(thing, context: modelContext)
                fetching = false
            }
    }
}

// MARK: - Listen

/// Read the article aloud, on this device (2026-08-23, prd §455).
///
/// The one verb this corpus can offer that the publisher's own page cannot:
/// the words are already here, `AVSpeechSynthesizer` is on-device, and nothing
/// leaves the phone to do it — no request, no key, no service, nothing in
/// `NetworkReach` to declare. It is the natural thing to do with a body we
/// went and fetched, and it is what makes the fetch worth more than a reading
/// pane: a story you can start and then put the phone in your pocket.
///
/// NOT A `Verb`. `VerbDerivation` caps a thing at three discs — the kind's
/// primary verb, the source hand-off, one utility — and adding a fourth to
/// every article would push out a real one. It is also conditional on
/// something no verb in that file consults (whether a body actually landed),
/// so a disc there would be present-and-dead on every story the fetch missed,
/// which is exactly what §83 forbids. It sits on the body instead, where it
/// can only exist when there is something to read.
/// Takes an ID and a STRING, never the `Thing` — the type is the guard.
/// A `View` storing a model has to guard its own body against a tombstone
/// (CLAUDE.md corollary 5, and the liveness audit's check 5 flagged exactly
/// that here); a view holding two value types cannot have the question. The
/// parent already read both fields while the model was valid.
struct ArticleListenButton: View {
    let id: String
    let text: String
    @State private var speech = ArticleSpeech.shared

    private var isMine: Bool { speech.speakingID == id }

    var body: some View {
        Button {
            DSHaptic.selection()
            if isMine {
                speech.stop()
            } else {
                speech.speak(text, id: id)
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: isMine ? "stop.fill" : "speaker.wave.2")
                    .imageScale(.small)
                Text(isMine ? "Stop" : "Listen")
                    .dsText(.subhead13).fontWeight(.semibold)
            }
            .foregroundStyle(isMine ? .white : DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(Capsule().fill(isMine ? DS.tint : DS.fillFaint))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(isMine
                            ? Text("Stop reading aloud")
                            : Text("Read this article aloud"))
        // Leaving the sheet stops the voice. Without this the synthesizer
        // keeps reading an article that is no longer on screen, with the only
        // control to stop it gone with the view that owned it — a sound the
        // person cannot turn off.
        .onDisappear { if isMine { speech.stop() } }
    }
}

/// The on-device voice, shared (2026-08-23).
///
/// ONE reader for the whole app, deliberately: `AVSpeechSynthesizer` will
/// happily queue a second utterance over a first, so a per-view synthesizer
/// means two articles reading at once the moment somebody opens a second
/// window or walks a "That day" shelf. `speakingID` is what a button asks to
/// know whether the voice belongs to IT — without it every article's button
/// would show "Stop" while a different article was being read.
@MainActor
@Observable
final class ArticleSpeech {
    static let shared = ArticleSpeech()

    /// The `Thing.id` being read, or nil. The only state a view needs.
    private(set) var speakingID: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private lazy var coordinator: SpeechCoordinator = {
        let coordinator = SpeechCoordinator()
        coordinator.onEnd = { [weak self] in self?.speakingID = nil }
        synthesizer.delegate = coordinator
        return coordinator
    }()

    private init() {}

    func speak(_ text: String, id: String) {
        _ = coordinator
        // A previous utterance is cut, not queued — see the type doc.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        // `.playback`, matching what the app already does for a voice note
        // (`ThingContentView`'s player and `VoiceCapture`). Speech under the
        // default `.soloAmbient` is silenced by the ring switch, which for a
        // control labelled "Listen" reads as a dead button rather than as a
        // hardware setting.
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        // The device's own voice for the device's own language. Deliberately
        // not pinned to a locale of ours: the corpus is multilingual (see
        // `EmbeddingIndex`'s language census) and an English voice reading a
        // German article is worse than no button.
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// Bridges the synthesizer's delegate callbacks onto the main actor.
///
/// Separate from `ArticleSpeech` because that type is `@MainActor` and these
/// callbacks arrive on the synthesizer's own queue; conforming the observable
/// class directly would be an isolation the runtime does not honour.
private final class SpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    var onEnd: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        let end = onEnd
        Task { @MainActor in end?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        let end = onEnd
        Task { @MainActor in end?() }
    }
}
