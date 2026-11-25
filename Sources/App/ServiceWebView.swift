import AppKit
import Network
import WebKit

/// Owns one service's persistent `WKWebView`: its data store, the injected bridge,
/// link routing, downloads, file uploads and media permissions.
@MainActor
final class ServiceWebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    static let messengerFallbackURL = URL(string: "https://www.facebook.com/messages/")!

    let service: Service
    let webView: WKWebView
    /// Parsed bridge messages (`{type: "title" | "notify", ...}`) from the main frame.
    var onMessage: (([String: Any]) -> Void)?
    /// A new main-frame document was committed (its bridge state starts fresh).
    var onDocumentCommitted: (() -> Void)?
    /// A main-frame load finished.
    var onLoadFinished: (() -> Void)?

    private var pageVisible = false
    private var firstLoadDone = false
    private var fallbackUsed = false

    /// Pending retry after a network failure; cancelled when a load commits.
    private var retryTask: Task<Void, Never>?
    private var retryURL: URL?
    private var retryFailures = 0
    private let pathMonitor = NWPathMonitor()

    init(service: Service) {
        self.service = service

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.dataStoreID)
        config.preferences.isElementFullscreenEnabled = true
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(
            source: BridgeScript.source(for: service.id),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        config.userContentController = content

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = false

        super.init()

        // The content controller retains its handler; controllers live for the app's lifetime.
        content.add(self, name: BridgeScript.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: service.startURL))

        // Retries right away when the network comes back instead of waiting out the backoff.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.retryNow() }
        }
        pathMonitor.start(queue: .main)
    }

    // MARK: - Commands

    func reload() {
        if webView.url == nil {
            webView.load(URLRequest(url: service.startURL))
        } else {
            webView.reload()
        }
    }

    var canGoBack: Bool { webView.canGoBack }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    /// Loads the service's inbox (its start URL).
    func goHome() {
        webView.load(URLRequest(url: service.startURL))
    }

    /// True when the page is somewhere other than the service's own app (or nothing has loaded).
    var isAwayFromHome: Bool {
        guard let url = webView.url else { return false }
        return !service.isHome(url)
    }

    /// Tells the page whether it is on screen. The value is re-applied after every load,
    /// because each new document starts hidden.
    func setPageVisible(_ visible: Bool) {
        pageVisible = visible
        applyVisibility()
    }

    func notificationClicked(id: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.__umNotificationClicked && window.__umNotificationClicked(\(literal));",
            completionHandler: nil
        )
    }

    private func applyVisibility() {
        webView.evaluateJavaScript(
            "window.__umSetVisible && window.__umSetVisible(\(pageVisible ? "true" : "false"));",
            completionHandler: nil
        )
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              body["service"] as? String == service.id.rawValue else { return }
        onMessage?(body)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        if let frame = navigationAction.targetFrame, !frame.isMainFrame { return .allow }
        guard let url = navigationAction.request.url else { return .allow }
        switch LinkRouter.decide(url, for: service) {
        case .inApp:
            return .allow
        case .external(let target):
            NSWorkspace.shared.open(target)
            return .cancel
        case .blocked:
            NSLog("[um] blocked %@", url.scheme ?? "")
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType { return .download }
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           LoadRules.isAttachment(contentDisposition: http.value(forHTTPHeaderField: "Content-Disposition")) {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        cancelRetry() // the network works, and a stale retry mustn't replace this page
        onDocumentCommitted?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        cancelRetry()
        retryFailures = 0
        applyVisibility()
        onLoadFinished?()
        if !firstLoadDone {
            firstLoadDone = true
            if service.id == .messenger, !isServiceHost(webView.url) {
                loadMessengerFallback()
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    private func handleLoadFailure(_ error: Error) {
        let nsError = error as NSError
        // Cancellations (redirects, policy decisions, downloads) are not real failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return } // frame load interrupted by policy change
        // Offline (e.g. Wi-Fi not up yet at login): retry the same page later. This must not
        // count as the first load, or Messenger would spend its one-time fallback on it.
        if LoadRules.isRetryableNetworkError(domain: nsError.domain, code: nsError.code) {
            let failing = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            scheduleRetry(of: failing ?? webView.url ?? service.startURL)
            return
        }
        guard !firstLoadDone else { return }
        firstLoadDone = true
        if service.id == .messenger { loadMessengerFallback() }
    }

    // MARK: - Network retry

    private func scheduleRetry(of url: URL) {
        retryTask?.cancel()
        retryURL = url
        let delay = LoadRules.retryDelay(afterFailures: retryFailures)
        retryFailures += 1
        NSLog("[um] %@ load failed offline; retrying in %.0f s", service.id.rawValue, delay)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retryNow()
        }
    }

    /// Loads the pending retry URL now, if a retry is pending.
    private func retryNow() {
        guard let url = retryURL else { return }
        cancelRetry()
        webView.load(URLRequest(url: url))
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryURL = nil
    }

    /// True when `url` is on one of the service's own hosts (e.g. a meta.com login page counts).
    private func isServiceHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return service.allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func loadMessengerFallback() {
        guard !fallbackUsed else { return }
        fallbackUsed = true
        webView.load(URLRequest(url: Self.messengerFallbackURL))
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // A blank popup (window.open() with no URL) has nothing to route; loading
        // about:blank here would wipe the current page.
        guard let url = navigationAction.request.url, url.absoluteString != "about:blank",
              !url.absoluteString.isEmpty else { return nil }
        switch LinkRouter.decide(url, for: service) {
        case .inApp:
            webView.load(navigationAction.request)
        case .external(let target):
            NSWorkspace.shared.open(target)
        case .blocked:
            NSLog("[um] blocked %@", url.scheme ?? "")
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let response: NSApplication.ModalResponse
        if let window = webView.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        // Opaque origins have an empty protocol/host; setting an empty scheme would trap.
        guard !origin.protocol.isEmpty, !origin.host.isEmpty,
              ["http", "https"].contains(origin.protocol.lowercased()) else { return .deny }
        var components = URLComponents()
        components.scheme = origin.protocol.lowercased()
        components.host = origin.host
        guard let url = components.url else { return .deny }
        return LinkRouter.decide(url, for: service) == .inApp ? .grant : .deny
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let fm = FileManager.default
        let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return Self.uniqueURL(in: folder, for: suggestedFilename)
    }

    /// `name.ext`, then `name (1).ext`, `name (2).ext`, … until no file exists.
    static func uniqueURL(in folder: URL, for suggestedFilename: String) -> URL {
        let fm = FileManager.default
        var filename = (suggestedFilename as NSString).lastPathComponent
        if filename.isEmpty || filename == "." || filename == ".." { filename = "download" }
        var candidate = folder.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 1
        repeat {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
