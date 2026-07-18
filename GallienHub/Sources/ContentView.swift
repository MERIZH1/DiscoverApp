import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gallienHub.endpoint") private var endpointValue = HubEndpoint.tailscale.rawValue
    @StateObject private var web = HubWebViewModel()
    @StateObject private var authentication = AuthenticationCoordinator()
    @StateObject private var updater = HubAppUpdater()
    @ObservedObject private var notifications = HubNotificationCoordinator.shared
    @State private var authenticationError: String?

    private var endpoint: HubEndpoint {
        HubEndpoint(rawValue: endpointValue) ?? .tailscale
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.075)
                .ignoresSafeArea()

            HubWebView(model: web)
                .ignoresSafeArea(.container, edges: .bottom)

            if let message = web.errorMessage {
                ConnectionErrorView(message: message) {
                    web.reload()
                } useTailscale: {
                    select(.tailscale)
                } useLAN: {
                    select(.lan)
                }
                .transition(.opacity)
            }

            if authentication.isAuthenticating {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                ProgressView("Sichere Anmeldung …")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if web.isOutsideHub {
                ExternalNavigationBar {
                    web.goBack()
                } home: {
                    web.goHome()
                }
            } else if web.isLoading {
                ProgressView()
                    .tint(Color(red: 0.34, green: 0.89, blue: 0.98))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
        }
        .overlay(alignment: .top) {
            if let authenticationError {
                ErrorToast(message: authenticationError) {
                    self.authenticationError = nil
                }
                .padding(.top, 10)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            web.authenticationHandler = startAuthentication
            let webModel = web
            notifications.openControlHandler = { [weak webModel] in
                webModel?.openControlCenter()
            }
            notifications.requestAuthorizationIfNeeded()
            notifications.scheduleBackgroundRefresh()
            web.loadIfNeeded(endpoint)
            Task { await updater.checkForUpdate() }
        }
        .onDisappear {
            notifications.openControlHandler = nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await notifications.refreshFromServer() }
                Task { await updater.checkForUpdate() }
            case .background:
                notifications.scheduleBackgroundRefresh()
                Task { await notifications.refreshFromServer() }
            default:
                break
            }
        }
    }

    private func select(_ endpoint: HubEndpoint) {
        endpointValue = endpoint.rawValue
        web.load(endpoint)
    }

    private func startAuthentication() {
        authenticationError = nil
        authentication.start { result in
            switch result {
            case .success(let code):
                guard let exchangeURL = HubEndpoint.exchangeURL(for: code) else {
                    authenticationError = "Das Anmeldeticket konnte nicht übernommen werden."
                    return
                }
                endpointValue = HubEndpoint.tailscale.rawValue
                web.loadAuthenticated(url: exchangeURL)
            case .failure(let error):
                if let sessionError = error as? ASWebAuthenticationSessionError,
                   sessionError.code == .canceledLogin {
                    return
                }
                authenticationError = error.localizedDescription
            }
        }
    }
}

private struct ExternalNavigationBar: View {
    let back: () -> Void
    let home: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Label("Zurück", systemImage: "chevron.left")
            }
            Spacer()
            Text("Server-App")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: home) {
                Image(systemName: "square.grid.2x2.fill")
                    .accessibilityLabel("Zurück zum Hub")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(.ultraThinMaterial)
    }
}

private struct ConnectionErrorView: View {
    let message: String
    let retry: () -> Void
    let useTailscale: () -> Void
    let useLAN: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.075),
                    Color(red: 0.075, green: 0.04, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28))

                VStack(spacing: 8) {
                    Text("Server nicht erreichbar")
                        .font(.title2.bold())
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Button("Erneut versuchen", action: retry)
                        .buttonStyle(PrimaryHubButtonStyle())
                    Button("Über Tailscale öffnen", action: useTailscale)
                        .buttonStyle(SecondaryHubButtonStyle())
                    Button("Im Heimnetz öffnen", action: useLAN)
                        .buttonStyle(SecondaryHubButtonStyle())
                }
                .frame(maxWidth: 360)
            }
            .padding(30)
        }
    }
}

private struct ErrorToast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.weight(.medium))
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}

private struct PrimaryHubButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.black)
            .background(
                LinearGradient(colors: [.cyan, Color(red: 0.45, green: 0.95, blue: 0.78)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SecondaryHubButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

