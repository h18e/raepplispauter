import SwiftUI

/// Sync-Protokoll: zeigt alle Änderungen, die vom **anderen Gerät** hereingekommen sind.
///
/// Damit ist die Anforderung "keine stille Datenüberschreibung ohne
/// Nachvollziehbarkeit" erfüllt: Die automatische Konfliktlösung bleibt bequem,
/// aber jede Fremdänderung ist hier mit Zeitpunkt, Urheber und betroffenen
/// Feldern nachlesbar.
struct SyncLogView: View {

    @EnvironmentObject private var auditor: ConflictAuditor

    var body: some View {
        Group {
            if auditor.entries.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath",
                               title: L.syncLogEmpty,
                               message: L.syncLogHint)
            } else {
                List {
                    Section {
                        ForEach(auditor.entries) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.symbolName)
                                    .foregroundStyle(color(for: entry.kind))
                                    .font(.footnote)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(Formatters.dateTime.string(from: entry.date)) · \(entry.author)")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } footer: {
                        Text(L.syncLogHint)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .screenBackground()
        .navigationTitle(L.syncLogTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L.syncLogClear) {
                    auditor.clear()
                }
                .disabled(auditor.entries.isEmpty)
            }
        }
    }

    private func color(for kind: SyncLogEntry.Kind) -> Color {
        switch kind {
        case .created: return Theme.positive
        case .updated: return Theme.accent
        case .deleted: return Theme.negative
        case .info: return Theme.textSecondary
        case .error: return Theme.warning
        }
    }
}

#Preview {
    NavigationStack {
        SyncLogView()
    }
    .environmentObject(ConflictAuditor.shared)
    .preferredColorScheme(.dark)
}
