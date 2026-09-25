import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The one place a model belongs in Addresses (prd §916, section 3): a
/// language judgement over two identities' PUBLIC words — display names,
/// bios, an organisation, a handle — when the person opens a "Same person?"
/// suggestion. It yields a sentence under the row, never a merge.
///
/// On the phone through `AskModel.session(forceDevice:)`; when Apple grants
/// the managed entitlement (§833) the same call rides Private Cloud Compute
/// and nothing here changes. Never a phone number, never an email address.
/// File-scope `@Generable`, gated to iOS 26 (CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct ContactLinkVerdict {
    @Guide(description: "true only when the two descriptions plainly name the same person or organization; false when unsure")
    var samePerson: Bool
    @Guide(description: "One short sentence saying why, naming what matched or what did not")
    var because: String
}

enum ContactVerdictModel {
    /// nil when no model is available, or it could not answer.
    static func judge(_ a: String, _ b: String) async -> (samePerson: Bool, because: String)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard OnDeviceModel.isAvailable else { return nil }
            let instructions = """
            You decide whether two short public descriptions refer to the same \
            person or organization. Answer only from what is written; a shared \
            first name alone is not enough. When unsure, answer false.
            """
            do {
                let session = await AskModel.session(instructions: instructions, forceDevice: true).session
                let verdict = try await session.respond(
                    to: "A: \(a)\nB: \(b)",
                    generating: ContactLinkVerdict.self
                ).content
                return (verdict.samePerson, verdict.because)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
