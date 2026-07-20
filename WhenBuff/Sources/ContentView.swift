import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WhenBuffStore
    @ObservedObject private var notifications = WhenBuffNotificationCoordinator.shared
    @State private var selectedDate = Date()

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
                    CalendarHeader(selectedDate: $selectedDate, lastUpdated: store.lastUpdated)
                } header: {
                    Text("Kalender")
                        .foregroundStyle(WhenBuffPalette.calendar)
                }

                Section {
                    Picker("Server", selection: Binding(
                        get: { store.selectedServer },
                        set: { store.selectServer($0) }
                    )) {
                        ForEach(store.servers) { server in
                            Text("\(server.name) (\(server.region))")
                                .tag(server.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WhenBuffPalette.server)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(store.statusText.hasPrefix("Live") ? WhenBuffPalette.live : WhenBuffPalette.warning)
                            .frame(width: 9, height: 9)
                        Text(store.statusText)
                            .font(.subheadline)
                            .foregroundStyle(store.statusText.hasPrefix("Live") ? WhenBuffPalette.live : WhenBuffPalette.warning)
                        Spacer()
                        if store.isRefreshing {
                            ProgressView()
                                .tint(WhenBuffPalette.calendar)
                                .controlSize(.small)
                        }
                    }

                    if let lastUpdated = store.lastUpdated {
                        Text("Stand: \(Self.dateFormatter.string(from: lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(WhenBuffPalette.muted)
                    }
                } header: {
                    Text("Live-Server")
                        .foregroundStyle(WhenBuffPalette.server)
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
                        .foregroundStyle(WhenBuffPalette.buff)
                }

                Section {
                    Label(notificationText, systemImage: notificationIcon)
                        .foregroundStyle(notificationColor)
                    Text("Der Server prüft whenbuff.com alle 5 Sekunden. Im Hintergrund bestimmt iOS, wann die App kurz aktualisieren darf.")
                        .font(.caption)
                        .foregroundStyle(WhenBuffPalette.muted)
                } header: {
                    Text("Benachrichtigungen")
                        .foregroundStyle(WhenBuffPalette.notification)
                }
            }
            .navigationTitle("WhenBuff")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(WhenBuffPalette.background)
            .tint(WhenBuffPalette.calendar)
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
        notifications.authorizationStatus == .denied ? WhenBuffPalette.warning : WhenBuffPalette.notification
    }
}

private struct CalendarHeader: View {
    @Binding var selectedDate: Date
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WhenBuffPalette.calendar)
                    .frame(width: 34, height: 34)
                    .background(WhenBuffPalette.calendar.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buff-Kalender")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Neue Einträge werden automatisch übernommen")
                        .font(.caption)
                        .foregroundStyle(WhenBuffPalette.muted)
                }
                Spacer()
            }

            DatePicker(
                "Datum auswählen",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(WhenBuffPalette.calendar)
            .accessibilityLabel("Buff-Datum auswählen")

            HStack {
                Label(Self.dateFormatter.string(from: selectedDate), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhenBuffPalette.date)
                Spacer()
                if let lastUpdated {
                    Text("Stand \(ContentView.dateFormatter.string(from: lastUpdated))")
                        .font(.caption2)
                        .foregroundStyle(WhenBuffPalette.muted)
                }
            }
        }
        .padding(12)
        .background(WhenBuffPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WhenBuffPalette.calendar.opacity(0.32), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, dd.MM.yyyy"
        return formatter
    }()
}

private struct BuffRow: View {
    let buff: WhenBuffRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(WhenBuffPalette.buff)
                Text(buff.type.whenBuffDisplayName)
                    .font(.headline)
                    .foregroundStyle(WhenBuffPalette.buff)
                Spacer()
                Text(factionText)
                    .font(.caption.bold())
                    .foregroundStyle(factionColor)
            }
            Label(
                ContentView.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(buff.scheduledAt))),
                systemImage: "clock.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WhenBuffPalette.date)
            if !buff.guild.isEmpty {
                Label(buff.guild, systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(WhenBuffPalette.guild)
            }
            if !buff.notes.isEmpty {
                Text(buff.notes)
                    .font(.caption)
                    .foregroundStyle(WhenBuffPalette.notes)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(WhenBuffPalette.card)
    }

    private var factionText: String {
        switch buff.faction.lowercased() {
        case "alliance": return "Allianz"
        case "horde": return "Horde"
        default: return "Beide"
        }
    }

    private var factionColor: Color {
        switch buff.faction.lowercased() {
        case "alliance": return WhenBuffPalette.alliance
        case "horde": return WhenBuffPalette.horde
        default: return WhenBuffPalette.both
        }
    }
}

private enum WhenBuffPalette {
    static let background = Color(hex6: 0x0B1220)
    static let card = Color(hex6: 0x17253A)
    static let muted = Color(hex6: 0xA8B6CC)
    static let calendar = Color(hex6: 0x5EEAD4)
    static let server = Color(hex6: 0x60A5FA)
    static let live = Color(hex6: 0x86EFAC)
    static let warning = Color(hex6: 0xFDBA74)
    static let buff = Color(hex6: 0xFDE047)
    static let date = Color(hex6: 0x67E8F9)
    static let guild = Color(hex6: 0xF0ABFC)
    static let notes = Color(hex6: 0xA7F3D0)
    static let notification = Color(hex6: 0xC4B5FD)
    static let alliance = Color(hex6: 0x60A5FA)
    static let horde = Color(hex6: 0xFB7185)
    static let both = Color(hex6: 0xC084FC)
}

extension Color {
    init(hex6 value: UInt) {
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
