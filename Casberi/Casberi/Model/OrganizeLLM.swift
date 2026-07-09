import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The strict parser catches "tag my lisbon links as Trip"; this catches the
/// near-misses ("put everything about lisbon under Trip") by asking the
/// on-device model to extract the SAME two commands. The output feeds the
/// SAME proposal card — the model never writes, it only fills the form the
/// person then approves. Gated on organize-ish wording so questions never
/// pay the extraction latency.
///
/// File-scope @Generable (nesting one breaks its keypaths — CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct OrganizeExtraction {
    @Guide(description: "tag = add a tag to matching things; rename = rename an existing tag; none = not an organize command")
    var action: String
    @Guide(description: "for tag: the words describing which things (e.g. 'lisbon links'). for rename: the current tag name.")
    var subject: String
    @Guide(description: "for tag: the tag to add. for rename: the new name.")
    var name: String
}

enum OrganizeLLM {

    /// Words that suggest the person is FILING, not asking. The gate keeps
    /// questions off the extraction path (answers stay instant).
    static func looksOrganizeish(_ raw: String) -> Bool {
        let q = raw.lowercased()
        guard !q.hasSuffix("?") else { return false }
        let verbs = ["tag", "label", "rename", "retag", "file", "move", "put",
                     "group", "organize", "organise", "call", "mark"]
        let first = q.split(separator: " ").first.map(String.init) ?? ""
        if verbs.contains(first) { return true }
        // "put everything about X under/into/as Y" shapes.
        return verbs.contains(where: { q.hasPrefix($0 + " ") })
            || ((q.contains(" under ") || q.contains(" into ") || q.contains(" as "))
                && verbs.contains(where: { q.contains($0 + " ") }))
    }

    /// Extracts an OrganizeCommand from loose wording, or nil when the model
    /// is unavailable, declines, or says it isn't an organize command.
    static func extract(_ raw: String) async -> OrganizeCommand? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), OnDeviceModel.isAvailable else { return nil }
        let instructions = """
        You extract organize commands for a personal library. Two commands exist:
        - tag: add a tag to things matching a description
        - rename: rename an existing tag
        If the text is anything else (a question, a note, chatter), action is "none".
        Extract only what is written — never invent subjects or names.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let result = try await session.respond(
                to: "Text: \(raw)",
                generating: OrganizeExtraction.self
            ).content
            let subject = result.subject.trimmingCharacters(in: .whitespaces)
            let name = result.name.trimmingCharacters(in: .whitespaces)
            guard !subject.isEmpty, !name.isEmpty else { return nil }
            switch result.action.lowercased() {
            case "tag":    return .tag(query: subject, tag: name)
            case "rename": return .rename(from: subject, to: name)
            default:       return nil
            }
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
