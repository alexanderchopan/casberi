import SwiftUI
import MessageUI

/// The system composers, as sheets (docs/social-spec.md section 0, section 3). The card
/// rides as a PNG attachment and the thing's link as the body; the person
/// taps Send, the app never does — a composer is the one sanctioned write
/// for Messages and Mail, and it ends on its own Cancel or Send, which is
/// all the app reads.
///
/// Recipients are prefilled only from what the thing already carries
/// (`detectedTel` / `detectedMailto`); the unified address book's
/// `ContactIndex.contact(for:)` takes over that line when it lands (section 5).
enum MessageCompose {
    /// Whether this device can raise the Messages composer at all — false on
    /// the simulator and on a Mac with no Messages account, in which case the
    /// tray draws no row rather than a dead one (§83).
    static var canText: Bool { MFMessageComposeViewController.canSendText() }
    static var canMail: Bool { MFMailComposeViewController.canSendMail() }

    /// The digits of a stored `tel:` URL, for a recipient line.
    static func phone(fromTel tel: String?) -> String? {
        guard let tel, let url = URL(string: tel), url.scheme == "tel" else { return nil }
        let digits = url.absoluteString.dropFirst("tel:".count)
        return digits.isEmpty ? nil : String(digits)
    }

    /// The address of a stored `mailto:` URL (the part before its `?`).
    static func address(fromMailto mailto: String?) -> String? {
        guard let mailto, let url = URL(string: mailto), url.scheme == "mailto" else { return nil }
        let rest = url.absoluteString.dropFirst("mailto:".count)
        let addr = rest.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        return addr.contains("@") ? addr.removingPercentEncoding ?? addr : nil
    }
}

/// `MFMessageComposeViewController`, presented as a SwiftUI sheet.
struct TextComposer: UIViewControllerRepresentable {
    let body: String
    let attachment: Data?
    let attachmentName: String
    var recipients: [String] = []
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.body = body
        if !recipients.isEmpty { vc.recipients = recipients }
        if let attachment, MFMessageComposeViewController.canSendAttachments() {
            vc.addAttachmentData(attachment, typeIdentifier: "public.png", filename: attachmentName)
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}

/// `MFMailComposeViewController`, presented as a SwiftUI sheet.
struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachment: Data?
    let attachmentName: String
    var recipients: [String] = []
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if !recipients.isEmpty { vc.setToRecipients(recipients) }
        if let attachment {
            vc.addAttachmentData(attachment, mimeType: "image/png", fileName: attachmentName)
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
