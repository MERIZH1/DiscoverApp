import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var store: WhenBuffStore
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var copiedNtfySetup = false

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, dd.MM.yyyy · HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WebsiteCalendar(
                        selectedDate: $selectedDate,
                        selectedFaction: Binding(
                            get: { store.selectedFaction },
                            set: { store.selectFaction($0) }
                        ),
                        buffs: factionBuffs
                    )
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)

                Section {
                    Label("Push-Nachrichten werden ausschließlich von ntfy gesendet.", systemImage: "paperplane.fill")
                        .foregroundStyle(WhenBuffPalette.notification)

                    if let profile = store.notificationProfile {
                        LabeledContent("Profil", value: profile.displayName)
                        LabeledContent("Auswahl", value: "\(profile.server) · \(factionName(profile.faction))")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ntfy-Server")
                                .font(.caption)
                                .foregroundStyle(WhenBuffPalette.muted)
                            Text(profile.ntfyBaseURL)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("Persönliches Thema")
                                .font(.caption)
                                .foregroundStyle(WhenBuffPalette.muted)
                                .padding(.top, 4)
                            Text(profile.topic)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }

                        Button {
                            UIPasteboard.general.string = "Server: \(profile.ntfyBaseURL)\nThema: \(profile.topic)"
                            copiedNtfySetup = true
                        } label: {
                            Label(
                                copiedNtfySetup ? "ntfy-Daten kopiert" : "ntfy-Daten kopieren",
                                systemImage: copiedNtfySetup ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                        }
                    }

                    Text(store.notificationStatusText)
                        .font(.caption)
                        .foregroundStyle(
                            store.notificationStatusText.contains("nicht")
                                ? WhenBuffPalette.warning
                                : WhenBuffPalette.live
                        )
                    Text("Gemeldet werden nur neu eingetragene Buffs für die oben ausgewählte Kombination aus Server und Fraktion.")
                        .font(.caption)
                        .foregroundStyle(WhenBuffPalette.muted)
                } header: {
                    Text("ntfy-Benachrichtigungen")
                        .foregroundStyle(WhenBuffPalette.notification)
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
                        Text("Letzte Serverabfrage: \(Self.dateTimeFormatter.string(from: lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(WhenBuffPalette.muted)
                    }
                } header: {
                    Text("Live-Server")
                        .foregroundStyle(WhenBuffPalette.server)
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

    private var factionBuffs: [WhenBuffRecord] {
        store.buffs.filter { buff in
            let faction = buff.whenBuffFaction
            return faction == store.selectedFaction || faction == "all" || faction == "both" || faction.isEmpty
        }
    }

    private func factionName(_ faction: String) -> String {
        faction == "horde" ? "Horde" : "Allianz"
    }
}

private struct WebsiteCalendar: View {
    @Binding var selectedDate: Date
    @Binding var selectedFaction: String
    let buffs: [WhenBuffRecord]

    private var selectedBuffs: [WhenBuffRecord] {
        buffs.filter {
            Calendar.current.isDate(
                Date(timeIntervalSince1970: TimeInterval($0.scheduledAt)),
                inSameDayAs: selectedDate
            )
        }
        .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        VStack(spacing: 12) {
            NextBuffBanner(buffs: buffs)

            FactionSelector(selectedFaction: $selectedFaction)

            HStack(spacing: 12) {
                Button {
                    moveDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)

                VStack(spacing: 2) {
                    Text(Self.dateFormatter.string(from: selectedDate))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(Self.weekdayFormatter.string(from: selectedDate))
                        .font(.caption)
                        .foregroundStyle(WhenBuffPalette.muted)
                }
                .frame(maxWidth: .infinity)

                Button {
                    moveDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label("Kalender", systemImage: "calendar")
                    .font(.caption.bold())
                    .foregroundStyle(WhenBuffPalette.calendar)
                Spacer()
                Label("24 Stunden", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(WhenBuffPalette.muted)
            }

            VStack(spacing: 8) {
                if selectedBuffs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.minus")
                            .font(.title2)
                            .foregroundStyle(WhenBuffPalette.muted)
                        Text("Keine Buffs an diesem Tag")
                            .font(.subheadline)
                            .foregroundStyle(WhenBuffPalette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(WhenBuffPalette.emptyCard, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(selectedBuffs) { buff in
                        BuffCalendarCard(buff: buff)
                    }
                }
            }
        }
        .padding(12)
        .background(WhenBuffPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WhenBuffPalette.calendar.opacity(0.28), lineWidth: 1)
        )
    }

    private func moveDay(_ amount: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: amount, to: selectedDate) {
            selectedDate = date
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd. MMMM yyyy"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

private struct FactionSelector: View {
    @Binding var selectedFaction: String

    var body: some View {
        HStack(spacing: 8) {
            factionButton(
                value: "alliance",
                title: "Allianz",
                symbol: "shield.fill",
                color: WhenBuffPalette.alliance
            )
            factionButton(
                value: "horde",
                title: "Horde",
                symbol: "flame.fill",
                color: WhenBuffPalette.horde
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fraktion auswählen")
    }

    private func factionButton(
        value: String,
        title: String,
        symbol: String,
        color: Color
    ) -> some View {
        let isSelected = selectedFaction == value
        return Button {
            selectedFaction = value
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? Color.white : WhenBuffPalette.muted)
                .background(
                    isSelected ? color : WhenBuffPalette.emptyCard,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? color : WhenBuffPalette.muted.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NextBuffBanner: View {
    let buffs: [WhenBuffRecord]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let nextBuff = buffs
                .filter { $0.scheduledAt >= Int(context.date.timeIntervalSince1970) }
                .min { $0.scheduledAt < $1.scheduledAt }

            HStack(spacing: 12) {
                if let nextBuff {
                    BuffIcon(type: nextBuff.type, size: 36)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundStyle(WhenBuffPalette.muted)
                        .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let nextBuff {
                        Text("Nächster Buff: \(nextBuff.type.whenBuffDisplayName)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("in \(Self.countdown(to: nextBuff.scheduledAt, now: context.date))")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(WhenBuffPalette.buffColor(for: nextBuff.type))
                    } else {
                        Text("Kein kommender Buff bekannt")
                            .font(.subheadline.bold())
                            .foregroundStyle(WhenBuffPalette.muted)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(WhenBuffPalette.banner, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private static func countdown(to timestamp: Int, now: Date) -> String {
        let remaining = max(0, timestamp - Int(now.timeIntervalSince1970))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct BuffCalendarCard: View {
    let buff: WhenBuffRecord

    var body: some View {
        HStack(spacing: 12) {
            BuffIcon(type: buff.type, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(buff.scheduledAt))))
                        .font(.headline.monospacedDigit())
                    Text("–")
                    Text(buff.type.whenBuffDisplayName)
                        .font(.headline)
                }
                if !buff.guild.isEmpty {
                    Label(buff.guild, systemImage: "person.3.fill")
                        .font(.caption)
                        .lineLimit(1)
                }
                if !buff.notes.isEmpty {
                    Text(buff.notes)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhenBuffPalette.buffColor(for: buff.type), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: WhenBuffPalette.buffColor(for: buff.type).opacity(0.24), radius: 4, y: 2)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct BuffIcon: View {
    let type: String
    let size: CGFloat

    var body: some View {
        Image(type.whenBuffIconName)
            .resizable()
            .interpolation(.none)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(5, size * 0.16), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: max(5, size * 0.16), style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

private enum WhenBuffPalette {
    static let background = Color(hex6: 0x0B1220)
    static let card = Color(hex6: 0x17253A)
    static let banner = Color(hex6: 0x101C2E)
    static let emptyCard = Color(hex6: 0x101C2E)
    static let muted = Color(hex6: 0xA8B6CC)
    static let calendar = Color(hex6: 0x5EEAD4)
    static let server = Color(hex6: 0x60A5FA)
    static let live = Color(hex6: 0x86EFAC)
    static let warning = Color(hex6: 0xFDBA74)
    static let notification = Color(hex6: 0xC4B5FD)
    static let alliance = Color(hex6: 0x2563EB)
    static let horde = Color(hex6: 0xB91C1C)
    static let zg = Color(hex6: 0x32A866)
    static let onyxia = Color(hex6: 0xD94A4A)
    static let rend = Color(hex6: 0x9370DB)

    static func buffColor(for type: String) -> Color {
        let value = type.lowercased()
        if value.contains("ony") { return onyxia }
        if value.contains("zul") || value == "zg" { return zg }
        if value.contains("rend") { return rend }
        return calendar
    }
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
