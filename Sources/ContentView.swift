import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()
    @State private var booting = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if !app.connected {
                    ServerSetupView()
                } else if app.profile == nil {
                    ProfilePickerView()
                } else {
                    MainView()
                }
            }
            if booting { SplashView().transition(.opacity).zIndex(10) }
        }
        .environmentObject(app)
        .environmentObject(app.player)
        .task {
            DiscoverServices.app = app   // fuer Siri/Kurzbefehle
            await app.restore()
            try? await Task.sleep(nanoseconds: 500_000_000)   // kurze Mindestanzeige
            withAnimation(.easeOut(duration: 0.4)) { booting = false }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Ladescreen
struct SplashView: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Color(hex6: 0x121212).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .scaleEffect(pulse ? 1.06 : 0.92)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                Text("Lädt…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
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
            Text(AppInfo.version).font(.caption2).foregroundStyle(.secondary).padding(.bottom, 8)
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
            Text("Profil wählen").font(.title2.bold()).padding(.top, 40)
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
            Text("\(app.serverURL) · \(AppInfo.version)")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).padding(.horizontal).padding(.bottom, 8)
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
