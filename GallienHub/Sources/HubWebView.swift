import Combine
import SwiftUI
import UIKit
import WebKit

final class HubWebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var isOutsideHub = false
    @Published var errorMessage: String?

    let webView: WKWebView
    var authenticationHandler: (() -> Void)?
    private(set) var baseURL = HubEndpoint.tailscale.baseURL
    private var hasLoaded = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "GallienHub-iOS/1.0"
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.34, green: 0.89, blue: 0.98, alpha: 1)
        refresh.addTarget(self, action: #selector(refreshPage(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func load(_ endpoint: HubEndpoint) {
        baseURL = endpoint.baseURL
        load(url: endpoint.baseURL)
    }

    func loadAuthenticated(url: URL) {
        baseURL = HubEndpoint.tailscale.baseURL
        load(url: url)
    }

    func loadIfNeeded(_ endpoint: HubEndpoint) {
        guard !hasLoaded else { return }
        load(endpoint)
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil {
            load(url: baseURL)
        } else {
            webView.reload()
        }
    }

    func goHome() {
        load(url: baseURL)
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            goHome()
        }
    }

    private func load(url: URL) {
        hasLoaded = true
        errorMessage = nil
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
    }

    @objc private func refreshPage(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }

    private func updateNavigationState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        guard let current = webView.url else {
            isOutsideHub = false
            return
        }
        isOutsideHub = current.host != baseURL.host || current.port != baseURL.port
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "Keine Netzwerkverbindung. Prüfe WLAN oder Mobilfunk."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                return "Der Gallienserver ist gerade nicht erreichbar."
            default:
                break
            }
        }
        return "Die Seite konnte nicht geladen werden."
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        webView.scrollView.refreshControl?.endRefreshing()
        updateNavigationState(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        webView.scrollView.refreshControl?.endRefreshing()
        errorMessage = friendlyMessage(for: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        webView.scrollView.refreshControl?.endRefreshing()
        errorMessage = friendlyMessage(for: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.path == "/auth/login" || url.path == "/auth/mobile/start" {
            decisionHandler(.cancel)
            authenticationHandler?()
            return
        }

        if !["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
            return
        }

        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }
}

struct HubWebView: UIViewRepresentable {
    @ObservedObject var model: HubWebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

