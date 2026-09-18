import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The long press of a digest notification (prd §809): the day's things as
/// feed rows, under the digest's faces and app tiles. Everything it draws was
/// decided by the app when it scheduled the digest (`NotifyCard`), and every
/// picture arrives as one of the notification's own attachments, so this
/// reads no store, no shared folder and no network, and carries no
/// entitlement (§809a). A tap anywhere opens the digest's own door.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<DigestCardView>?

    func didReceive(_ notification: UNNotification) {
        guard let card = NotifyCard.decoded(from: notification.request.content.userInfo) else { return }
        let view = DigestCardView(card: card, images: Self.images(notification.request.content.attachments))
        if let host {
            host.rootView = view
        } else {
            let made = UIHostingController(rootView: view)
            made.sizingOptions = .preferredContentSize
            made.view.backgroundColor = .clear
            addChild(made)
            made.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(made.view)
            NSLayoutConstraint.activate([
                made.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                made.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                made.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                made.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            ])
            made.didMove(toParent: self)
            host = made
        }
        let width = self.view.bounds.width > 0 ? self.view.bounds.width : 360
        let height = host?.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height ?? 320
        preferredContentSize = CGSize(width: width, height: height)
    }

    /// The attachments, read once, by identifier. iOS hands an extension its
    /// notification's attachments as security-scoped files.
    private static func images(_ attachments: [UNNotificationAttachment]) -> [String: UIImage] {
        var out: [String: UIImage] = [:]
        for attachment in attachments where !attachment.identifier.isEmpty {
            let url = attachment.url
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                out[attachment.identifier] = image
            }
        }
        return out
    }
}

/// The card: the faces and the title, then one row per thing in the feed
/// row's anatomy (prd §744) — a 26pt lead, who (or the app) and the time,
/// then the line, whole: nothing here is cut with an ellipsis.
struct DigestCardView: View {
    let card: NotifyCard
    let images: [String: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                if let name = card.head, let image = images[name] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
                Text(verbatim: card.title)
                    .dsText(.heading24)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                    DigestRow(row: row, card: card, image: row.face.flatMap { images[$0] })
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DigestRow: View {
    let row: NotifyCard.Row
    let card: NotifyCard
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                lead
                // The person leads when there is one. The app is named only
                // when the card holds several, so one app is not repeated
                // down every row.
                Text(verbatim: label)
                    .dsText(.subhead12)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(verbatim: row.at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .dsText(.subhead12)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(verbatim: row.line)
                .dsText(.body17)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var label: String {
        let several = Set(card.rows.map(\.app)).count > 1
        guard let who = row.who else { return row.app }
        return several ? who + " · " + row.app : who
    }

    @ViewBuilder private var lead: some View {
        let shape = RoundedRectangle(cornerRadius: row.round ? 13 : 6, style: .continuous)
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(shape)
        } else {
            Text(verbatim: String((row.who ?? row.app).prefix(1)).uppercased())
                .dsText(.label12)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.18), in: shape)
        }
    }
}
