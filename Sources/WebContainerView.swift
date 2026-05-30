import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer

/// WKWebView-Huelle: laedt die Discover-Web-App, haelt die Audio-Session aktiv
/// und bruecke Lock-Screen-Befehle (MPRemoteCommandCenter) zur Web-App.
struct WebContainerView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []   // Autoplay erlauben
        cfg.websiteDataStore = .default()                   // Cookies/localStorage persistent

        // Bruecke: Web -> native (Now-Playing-Infos)
        cfg.userContentController.add(context.coordinator, name: "nowplaying")

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        context.coordinator.webView = webView

        webView.load(URLRequest(url: url))
        context.coordinator.setupRemoteCommands()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Wenn sich die URL aendert (Server gewechselt), neu laden.
        if webView.url?.absoluteString != url.absoluteString,
           context.coordinator.loadedHost != url.host {
            context.coordinator.loadedHost = url.host
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var loadedHost: String?

        // ── Lock-Screen / Kopfhoerer-Buttons -> Web-App ─────────────────
        func setupRemoteCommands() {
            let c = MPRemoteCommandCenter.shared()
            c.playCommand.isEnabled = true
            c.pauseCommand.isEnabled = true
            c.nextTrackCommand.isEnabled = true
            c.previousTrackCommand.isEnabled = true
            c.togglePlayPauseCommand.isEnabled = true

            c.playCommand.addTarget { [weak self] _ in self?.js("window.__nativePlay && __nativePlay()"); return .success }
            c.pauseCommand.addTarget { [weak self] _ in self?.js("window.__nativePause && __nativePause()"); return .success }
            c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.js("window.__nativeToggle && __nativeToggle()"); return .success }
            c.nextTrackCommand.addTarget { [weak self] _ in self?.js("window.__nativeNext && __nativeNext()"); return .success }
            c.previousTrackCommand.addTarget { [weak self] _ in self?.js("window.__nativePrev && __nativePrev()"); return .success }
        }

        private func js(_ code: String) {
            DispatchQueue.main.async { self.webView?.evaluateJavaScript(code, completionHandler: nil) }
        }

        // ── Web -> native: Now-Playing-Infos fuer den Lock-Screen ───────
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "nowplaying",
                  let d = message.body as? [String: Any] else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
            if let title = d["title"] as? String { info[MPMediaItemPropertyTitle] = title }
            if let artist = d["artist"] as? String { info[MPMediaItemPropertyArtist] = artist }
            if let dur = d["duration"] as? Double { info[MPMediaItemPropertyPlaybackDuration] = dur }
            if let pos = d["position"] as? Double { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos }
            if let playing = d["playing"] as? Bool {
                info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info

            // Artwork asynchron nachladen (optional)
            if let art = d["artwork"] as? String, let u = URL(string: art) {
                URLSession.shared.dataTask(with: u) { data, _, _ in
                    guard let data = data, let img = UIImage(data: data) else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    DispatchQueue.main.async {
                        var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
                        i[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
                    }
                }.resume()
            }
        }
    }
}
