import CloudKit
import SwiftUI
import UIKit

/// SwiftUI-Hülle um `UICloudSharingController` – das ist die von Apple
/// vorgegebene Oberfläche zum Einladen (Nachricht, Mail, Link kopieren) und zum
/// späteren Verwalten der Teilnehmer.
///
/// Verwendung: in einem `.sheet` präsentieren, sobald `SharingController.makeShare(for:)`
/// einen `CKShare` geliefert hat.
struct CloudSharingSheet: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    let title: String
    /// Wird aufgerufen, wenn der Share erfolgreich gespeichert bzw. beendet wurde.
    var onSaved: () -> Void = {}
    var onStopped: () -> Void = {}
    var onFailed: (Error) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        // Alle Mitreisenden dürfen erfassen und bearbeiten (`allowReadWrite`).
        //
        // Bei der Reichweite hat die Person die Wahl:
        // * `allowPrivate` – nur namentlich eingeladene Apple-Accounts
        // * `allowPublic`  – jede Person, die den Link hat, kann beitreten
        //
        // Letzteres ist im Ferienalltag meist das Praktischere: Link per
        // Nachricht in die Gruppe, fertig – ohne vorher jede Apple-ID zu kennen.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate, .allowPublic]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, onSaved: onSaved, onStopped: onStopped, onFailed: onFailed)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        private let onSaved: () -> Void
        private let onStopped: () -> Void
        private let onFailed: (Error) -> Void

        init(title: String,
             onSaved: @escaping () -> Void,
             onStopped: @escaping () -> Void,
             onFailed: @escaping (Error) -> Void) {
            self.title = title
            self.onSaved = onSaved
            self.onStopped = onStopped
            self.onFailed = onFailed
        }

        /// Titel der Einladung (erscheint in der Nachricht beim Partner).
        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func itemType(for csc: UICloudSharingController) -> String? { nil }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStopped()
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            onFailed(error)
        }
    }
}
