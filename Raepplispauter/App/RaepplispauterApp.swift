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
/// ## Warum es hier zwei Wege gibt
///
/// Tippt die eingeladene Person auf den Link, übergibt iOS die Einladung an die
/// App. **An wen genau, hängt davon ab, ob die App Szenen benutzt:**
///
/// * ohne Szenen → `UIApplicationDelegate.application(_:userDidAcceptCloudKitShareWith:)`
/// * mit Szenen  → `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`
///
/// Jede SwiftUI-App mit `WindowGroup` ist szenenbasiert (das Build-Setting
/// `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` erzeugt das Manifest).
/// Die App-Delegate-Methode allein wird deshalb **nie** aufgerufen – die
/// Einladung kam an, wurde aber nirgends entgegengenommen, und die geteilte
/// Kassä tauchte auf dem zweiten Gerät nie auf.
///
/// Darum ist beides implementiert: der Szenen-Weg, der tatsächlich greift, und
/// der App-Weg als Rückfalloption.
///
/// Voraussetzung in beiden Fällen: `CKSharingSupported = YES` in der Info.plist.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Hängt den `SceneDelegate` an die Szene, die iOS gleich aufbaut.
    ///
    /// Übernommen wird die Konfiguration, die iOS aus dem Szenen-Manifest
    /// bereits ermittelt hat – geändert wird nur die Delegate-Klasse. Würde man
    /// hier eine frische `UISceneConfiguration` bauen, ginge die Szenen-Klasse
    /// verloren, die SwiftUI für seine Fenster braucht.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = connectingSceneSession.configuration
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Rückfall für den Fall, dass die App ohne Szenen läuft.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharingController.shared.accept(cloudKitShareMetadata)
        }
    }
}

/// Nimmt die Einladung auf dem Weg entgegen, den szenenbasierte Apps benutzen.
///
/// Bewusst **ohne** `scene(_:willConnectTo:options:)`: Diese Methode würde den
/// Fensteraufbau übernehmen, den SwiftUI selbst erledigt – die App bliebe leer.
/// Hier steht nur die eine Methode, die gebraucht wird.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharingController.shared.accept(cloudKitShareMetadata)
        }
    }
}
