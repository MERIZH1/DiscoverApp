import SwiftUI

struct ContentView: View {
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var draft: String = ""
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url = Self.normalized(serverURL) {
                WebContainerView(url: url)
                    .ignoresSafeArea()
                // Kleiner Zahnrad-Button oben rechts zum Aendern der Adresse.
                Button {
                    draft = serverURL
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 50)
                .padding(.trailing, 12)
                .tint(.white)
            } else {
                setupScreen
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    private var setupScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 54))
                .foregroundStyle(.purple)
            Text("Discover")
                .font(.largeTitle.bold())
            Text("Server-Adresse eingeben\n(z.B. deine Tailscale-IP vom Server)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("http://100.x.x.x:5555", text: $draft)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 28)
            Button("Verbinden") {
                serverURL = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .buttonStyle(.borderedProminent)
            .disabled(Self.normalized(draft) == nil)
            Spacer()
        }
        .padding()
    }

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("Server-Adresse") {
                    TextField("http://100.x.x.x:5555", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section {
                    Button("Speichern & neu laden") {
                        serverURL = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        showSettings = false
                    }
                    .disabled(Self.normalized(draft) == nil)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showSettings = false }
                }
            }
        }
    }

    /// Akzeptiert "100.x.x.x:5555", "http://...", "https://..." und macht eine
    /// gueltige URL draus (Default-Schema http, Default-Port bleibt wie getippt).
    static func normalized(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}
