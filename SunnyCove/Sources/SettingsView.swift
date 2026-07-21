import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false
    @StateObject private var updates = ContentUpdateService()
    @StateObject private var appUpdates = AppUpdateService()
    @AppStorage("sunnycove.musicEnabled") private var musicEnabled = true
    @AppStorage("sunnycove.soundEnabled") private var soundEnabled = true
    @AppStorage("sunnycove.hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Spiel") {
                    Toggle("Musik", isOn: $musicEnabled)
                    Toggle("Soundeffekte", isOn: $soundEnabled)
                    Toggle("Haptisches Feedback", isOn: $hapticsEnabled)
                }

                Section("App-Update") {
                    LabeledContent("App", value: appVersion)
                    LabeledContent("Beta-Kanal", value: appUpdates.channelDisplayName)
                    Button("Nach neuer Beta suchen") {
                        Task { await appUpdates.checkForUpdates() }
                    }
                    if case .available = appUpdates.status, let installURL = appUpdates.installURL {
                        Button("Neue Beta installieren") { openURL(installURL) }
                            .foregroundStyle(.green)
                    }
                    Button("Beta-Seite öffnen") {
                        if let url = URL(string: "https://gallien.tail24f6af.ts.net:8443/Sunny_Cove") {
                            openURL(url)
                        }
                    }
                    Text(appUpdates.status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Inhalte") {
                    LabeledContent("Version", value: contentVersion)
                    Button("Nach neuen Inhalten suchen") {
                        Task { await updates.checkForUpdates() }
                    }
                    if case .available = updates.status {
                        Button("Neue Inhalte laden") {
                            Task { await updates.applyLatestIfAvailable() }
                        }
                    }
                    Text(updates.status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Spielstand zurücksetzen", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar { Button("Fertig") { dismiss() } }
            .confirmationDialog("Wirklich neu beginnen?", isPresented: $confirmReset) {
                Button("Zurücksetzen", role: .destructive) {
                    game.reset()
                    dismiss()
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(version) (\(build))"
    }

    private var contentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "ContentVersion") as? String ?? "2026.07.1"
    }
}
