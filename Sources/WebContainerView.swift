import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer

/// WKWebView-Huelle: laedt die Discover-Web-App und reicht die Audio-Wiedergabe
/// an die native AudioEngine (AVPlayer) durch -> echter Lock-Screen, auch bei
/// Pause. Eine fruehe JS-Injektion markiert die native App + meldet, dass der
/// native Audio-Pfad verfuegbar ist.
struct WebContainerView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()

        // Frueh (vor app.js): native markieren + nativen Audio-Pfad ankuendigen.
        let early = """
        window.__nativeAudioAvailable = true;
        try { document.documentElement.classList.add('native-ios'); } catch(e) {}
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: early, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // Audio-Kommandos von der Web-App
        cfg.userContentController.add(context.coordinator, name: "audioctl")

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        // AudioEngine an diese WebView binden + Audio-Session aktivieren.
        context.coordinator.engine.webView = webView
        context.coordinator.engine.activateSession()
        context.coordinator.webView = webView

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedHost != url.host {
            context.coordinator.loadedHost = url.host
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var loadedHost: String?
        let engine = AudioEngine()

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "audioctl", let body = message.body as? [String: Any] else { return }
            engine.handle(body)
        }
    }
}
