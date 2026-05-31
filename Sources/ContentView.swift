import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()

    var body: some View {
        Group {
            if !app.connected {
                ServerSetupView()
            } else if app.profile == nil {
                ProfilePickerView()
            } else {
                MainView()
            }
        }
        .environmentObject(app)
        .environmentObject(app.player)
        .task { await app.restore() }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Server-Adresse
struct ServerSetupView: View {
    @EnvironmentObject var app: AppState
    @State private var input = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("Discover").font(.largeTitle.bold())
            Text("Server-Adresse eingeben (LAN oder Tailscale)")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("z.B. 192.168.2.14:5555", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding().background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button {
                Task {
                    busy = true; error = nil
                    error = await app.connect(server: input)
                    busy = false
                }
            } label: {
                Text(busy ? "Verbinde…" : "Verbinden")
                    .frame(maxWidth: .infinity).padding()
                    .background(.green).foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(input.isEmpty || busy)
            .padding(.horizontal)
            Spacer()
        }
        .onAppear { if input.isEmpty { input = app.serverURL } }
    }
}

// MARK: - Profil-Auswahl
struct ProfilePickerView: View {
    @EnvironmentObject var app: AppState
    @State private var profiles: [Profile] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Profil waehlen").font(.title2.bold()).padding(.top, 40)
            if let error { Text(error).foregroundStyle(.red) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 20) {
                    ForEach(profiles) { p in
                        Button { app.selectProfile(p) } label: {
                            VStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: p.color) ?? .gray)
                                    .frame(width: 84, height: 84)
                                    .overlay(Text(String(p.name.prefix(1)))
                                        .font(.largeTitle.bold()).foregroundStyle(.white))
                                Text(p.name).font(.headline)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }
            Button("Anderer Server") { app.connected = false }
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .task {
            do { profiles = try await app.api.profiles() }
            catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Helpers
extension Color {
    init?(hex: String?) {
        guard var h = hex else { return nil }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xff)/255,
                     green: Double((v >> 8) & 0xff)/255,
                     blue: Double(v & 0xff)/255)
    }
}
