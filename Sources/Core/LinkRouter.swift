import Foundation

enum LinkDecision: Equatable {
    case inApp
    case external(URL)
}

enum LinkRouter {
    private static let shimHosts: Set<String> = ["l.facebook.com", "l.messenger.com", "l.instagram.com"]

    /// Called only for main-frame navigations and new-window requests.
    static func decide(_ url: URL, for service: Service) -> LinkDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data"].contains(scheme) { return .inApp }

        let isWeb = scheme == "http" || scheme == "https"
        let host = url.host?.lowercased() ?? ""

        if isWeb, shimHosts.contains(host),
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name == "u" })?.value,
           let target = URL(string: value),
           let targetScheme = target.scheme?.lowercased(),
           targetScheme == "http" || targetScheme == "https" {
            return .external(target)
        }

        if isWeb, service.allowedHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .inApp
        }
        return .external(url)
    }
}
