import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WhenBuffStore
    @ObservedObject private var notifications = WhenBuffNotificationCoordinator.shared

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, dd.MM.yyyy · HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Server", selection: Binding(
                        get: { store.selectedServer },
                        set: { store.selectServer($0) }
                    )) {
                        ForEach(store.servers) { server in
                            Text("\(server.name) (\(server.region))").tag(server.name)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(store.statusText.hasPrefix("Live") ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                        Text(store.statusText)
                            .font(.subheadline)
                        Spacer()
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let lastUpdated = store.lastUpdated {
                        Text("Stand: \(Self.dateFormatter.string(from: lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Live-Server")
                }

                Section {
                    if store.buffs.isEmpty {
                        ContentUnavailableView(
                            "Keine kommenden Buffs",
                            systemImage: "bell.slash",
                            description: Text("Neue Einträge erscheinen automatisch.")
                        )
                    } else {
                        ForEach(store.buffs) { buff in
                            BuffRow(buff: buff)
                        }
                    }
                } header: {
                    Text("Kommende Buffs")
                }

                Section {
                    Label(notificationText, systemImage: notificationIcon)
                        .foregroundStyle(notificationColor)
                    Text("Der Server prüft whenbuff.com alle 5 Sekunden. Im Hintergrund bestimmt iOS, wann die App kurz aktualisieren darf.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Benachrichtigungen")
                }
            }
            .navigationTitle("WhenBuff")
            .refreshable { await store.refresh() }
        }
    }

    private var notificationText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return "Benachrichtigungen sind aktiv"
        case .denied: return "Benachrichtigungen sind in iOS deaktiviert"
        default: return "Benachrichtigungen werden eingerichtet"
        }
    }

    private var notificationIcon: String {
        notifications.authorizationStatus == .denied ? "bell.slash.fill" : "bell.badge.fill"
    }

    private var notificationColor: Color {
        notifications.authorizationStatus == .denied ? .orange : .green
    }
}

private struct BuffRow: View {
    let buff: WhenBuffRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(buff.type.whenBuffDisplayName)
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text(factionText)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text(ContentView.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(buff.scheduledAt))))
                .font(.subheadline.weight(.semibold))
            if !buff.guild.isEmpty {
                Label(buff.guild, systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !buff.notes.isEmpty {
                Text(buff.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var factionText: String {
        switch buff.faction.lowercased() {
        case "alliance": return "Allianz"
        case "horde": return "Horde"
        default: return "Beide"
        }
    }
}
