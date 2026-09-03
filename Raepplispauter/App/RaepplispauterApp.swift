import CloudKit
import SwiftUI
import UIKit

/// Einstiegspunkt der App (SwiftUI-App-Lifecycle).
@main
struct RaepplispauterApp: App {

    /// Der AppDelegate wird ausschliesslich gebraucht, um eingehende
    /// **iCloud-Freigabe-Einladungen** entgegenzunehmen – dafür gibt es in
    /// SwiftUI (noch) keinen eigenen Modifier.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let persistence = PersistenceController.shared
    @StateObject private var appState = AppState()
    @StateObject private var sharingController = SharingController.shared
    @StateObject private var auditor = ConflictAuditor.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(appState)
                .environmentObject(sharingController)
                .environmentObject(auditor)
                // Dark Mode ist das primäre (und einzige) Erscheinungsbild.
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    await appState.performStartupTasks(context: persistence.viewContext)
                }
        }
    }
}

/// Nimmt CloudKit-Share-Einladungen entgegen.
///
/// Tippt der Partner auf den Einladungslink (Nachricht/Mail), startet iOS die App
/// und ruft genau diese Methode auf. `SharingController.accept(_:)` legt die Reise
/// danach im **shared Store** ab – ab dann arbeiten beide Geräte auf demselben
/// Datensatz.
///
/// Voraussetzung: `CKSharingSupported = YES` in der Info.plist.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharingController.shared.accept(cloudKitShareMetadata)
        }
    }
}
