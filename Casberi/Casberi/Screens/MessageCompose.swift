import SwiftUI
import MessageUI

/// The system composers, as sheets (docs/social-spec.md section 0). The
/// person taps Send, the app never does — a composer is the one sanctioned
/// write for Messages and Mail, and it ends on its own Cancel or Send, which
/// is all the app reads.
enum MessageCompose {
    /// Whether this device can raise the Messages composer at all — false on
    /// the simulator and on a Mac with no Messages account, in which case no row
    /// draws rather than a dead one (§83).
    static var canText: Bool { MFMessageComposeViewController.canSendText() }
    static var canMail: Bool { MFMailComposeViewController.canSendMail() }
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
