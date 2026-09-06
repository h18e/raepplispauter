import CoreData
import SwiftUI

/// Einstellungen: Wechselkurse, iCloud-Status, Sync-Protokoll.
struct SettingsView: View {

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    @State private var markupText: String = Money.formatPlain(AppSettings.rateMarkupPercent)
    @State private var deviceOwner: Person = AppSettings.deviceOwner

    var body: some View {
        Form {
            // MARK: Wechselkurse
            Section {
                LabeledContent(L.settingsMarkup) {
                    TextField("0.00", text: $markupText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                        .onSubmit(applyMarkup)
                }

                Button {
                    Task { await appState.refreshRates(context: context) }
                } label: {
                    HStack {
                        Label(L.settingsRefreshRates, systemImage: "arrow.clockwise")
                        if appState.isRefreshingRates {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(appState.isRefreshingRates)

                Text(appState.lastRateRefresh
                        .map { L.settingsLastRefresh(Formatters.dateTime.string(from: $0)) }
                     ?? L.settingsNeverRefreshed)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Text(L.settingsCachedDays(RateStore.shared.cachedDayCount))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                if let error = appState.rateErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text(L.settingsRates)
            } footer: {
                Text(L.settingsMarkupHint)
            }

            // MARK: Sync
            Section {
                LabeledContent(L.settingsSyncMode) {
                    Text(appState.isLocalOnly ? L.syncModeLocal : L.syncModeCloud)
                        .foregroundStyle(appState.isLocalOnly ? Theme.warning : Theme.accent)
                }

                if !appState.isLocalOnly {
                    LabeledContent(L.settingsICloud) {
                        Text(appState.iCloudStatusText)
                            .foregroundStyle(appState.iCloudStatus == .available ? Theme.accent : Theme.warning)
                    }
                }

                if appState.didFallBackToLocal {
                    Label(L.syncModeFallbackNotice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }

                Picker(L.settingsDeviceOwner, selection: $deviceOwner) {
                    Text(Person.defaultNameA).tag(Person.a)
                    Text(Person.defaultNameB).tag(Person.b)
                }
                .onChange(of: deviceOwner) { _, newValue in
                    AppSettings.deviceOwner = newValue
                }

                NavigationLink {
                    SyncLogView()
                } label: {
                    Label(L.settingsSyncLog, systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text(L.settingsSyncMode)
            } footer: {
                if appState.isLocalOnly {
                    Text(L.syncModeLocalHint)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: applyMarkup)
    }

    private func applyMarkup() {
        guard let value = Money.parse(markupText) else { return }
        AppSettings.rateMarkupPercent = value
        markupText = Money.formatPlain(value)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
