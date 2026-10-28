import SwiftUI

/// Signing in to Telegram as yourself (prd §1575): your number, the code
/// Telegram sends, then your two-step password if you set one — Telegram's
/// own steps, one field at a time, through `TelegramClient`, with the login
/// email Telegram sometimes asks an existing account to set. Nothing
/// typed here is kept: the number and the code go to Telegram and the
/// password is checked by TDLib, which never stores it.
struct TelegramSignInSheet: View {
    var onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step: TelegramClient.Step = .starting
    @State private var entry = ""
    @State private var busy = false
    @State private var refusal: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    field
                        .plainAccountRow()
                } footer: {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        if let refusal {
                            Text(refusal).dsText(.body17).foregroundStyle(DS.destructiveInk)
                        }
                        DSFootnote(footnote, scale: .page)
                    }
                }
                Section {
                    DSSlabButton(title: verb, busy: busy || step == .starting,
                                 enabled: canSubmit) { Task { await submit() } }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .dsScreenTitle(String(localized: "Sign in to Telegram"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
        .task {
            TelegramClient.shared.onStep = { next in arrive(next) }
            let now = await TelegramClient.shared.settled()
            // Already signed in fires no change; nor does a client that never
            // answered, which says so rather than spinning.
            arrive(now == .starting
                   ? .unavailable(String(localized: "Telegram didn't answer. Close and try again."))
                   : now)
            focused = true
        }
        .onDisappear { TelegramClient.shared.onStep = nil }
    }

    private func arrive(_ next: TelegramClient.Step) {
        if next != step { entry = ""; refusal = nil }
        step = next
        if next == .ready { onSignedIn(); dismiss() }
    }

    @ViewBuilder private var field: some View {
        switch step {
        case .password:
            SecureField(String(localized: "Password"), text: $entry)
                .textContentType(.password)
                .focused($focused)
                .dsText(.body17)
                .onSubmit { Task { await submit() } }
        case .email:
            TextField(String(localized: "Email"), text: $entry)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .focused($focused)
                .dsText(.body17)
                .onSubmit { Task { await submit() } }
        default:
            TextField(placeholder, text: $entry)
                .keyboardType(step == .phone ? .phonePad : .numberPad)
                .textContentType(step == .phone ? .telephoneNumber : .oneTimeCode)
                .focused($focused)
                .dsText(.body17)
                .disabled(!(step == .phone || isCode))
        }
    }

    private var isCode: Bool {
        switch step {
        case .code, .emailCode: true
        default: false
        }
    }

    private var placeholder: String {
        isCode ? String(localized: "Code") : String(localized: "Phone number, with country code")
    }

    private var verb: String {
        step == .phone ? String(localized: "Send code") : String(localized: "Continue")
    }

    private var footnote: LocalizedStringResource {
        switch step {
        case .phone:
            "Casberi reads your chats on this device and never sends a message."
        case .code(let sentTo):
            if let sentTo { "Enter the code Telegram sent to \(sentTo)." } else { "Enter the code Telegram sent you." }
        case .password(let hint):
            if let hint { "Your two-step password. Your hint: \(hint)" } else { "Your two-step password, set in Telegram." }
        case .email:
            "Telegram asks for a login email for this account."
        case .emailCode(let sentTo):
            if let sentTo { "Enter the code Telegram sent to \(sentTo)." } else { "Enter the code Telegram emailed you." }
        case .noAccount:
            "This number has no Telegram account. Make one in Telegram first."
        case .closed, .idle:
            "Telegram ended this sign-in. Close and try again."
        case .unavailable(let why):
            "\(why)"
        case .starting, .ready:
            "Connecting to Telegram…"
        }
    }

    private var canSubmit: Bool {
        guard !busy else { return false }
        switch step {
        case .phone, .code, .password, .email, .emailCode:
            return !entry.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        defer { busy = false }
        let client = TelegramClient.shared
        let failure: String? = switch step {
        case .phone: await client.submit(phone: entry)
        case .code: await client.submit(code: entry)
        case .password: await client.submit(password: entry)
        case .email: await client.submit(email: entry)
        case .emailCode: await client.submit(emailCode: entry)
        default: nil
        }
        refusal = failure.map(Self.words)
    }

    /// Telegram's refusals, in words. Anything unnamed keeps Telegram's own.
    static func words(_ error: String) -> String {
        switch error {
        case "PHONE_NUMBER_INVALID": String(localized: "That number isn't valid. Start with + and the country code.")
        case "PHONE_CODE_INVALID": String(localized: "That code isn't right.")
        case "PHONE_CODE_EXPIRED": String(localized: "That code expired. Close and sign in again.")
        case "PASSWORD_HASH_INVALID": String(localized: "That password isn't right.")
        case "EMAIL_INVALID": String(localized: "That email isn't valid.")
        case "EMAIL_CODE_INVALID", "CODE_INVALID": String(localized: "That code isn't right.")
        case let e where e.hasPrefix("Too Many Requests") || e.hasPrefix("FLOOD_WAIT"):
            String(localized: "Telegram wants a pause. Try again later.")
        default: error
        }
    }
}
