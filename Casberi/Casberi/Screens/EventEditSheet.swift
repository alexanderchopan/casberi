import SwiftUI
import EventKit
import EventKitUI

/// The system's native new-event editor, as a sheet. Apple offers no URL that
/// opens a blank event composer, so the Calendar source feed's "New event"
/// presents this — the person fills it in and saves, all in Apple's own UI,
/// with its own Cancel/Add buttons. The caller grants write access first.
struct EventEditSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let event = EKEvent(eventStore: store)
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(3600)
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
            onDismiss()
        }
    }
}
