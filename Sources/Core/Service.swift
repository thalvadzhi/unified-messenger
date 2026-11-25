import Foundation

enum ServiceID: String, CaseIterable, Sendable {
    case messenger, instagram
}

struct Service: Identifiable, Hashable, Sendable {
    let id: ServiceID
    let name: String
    let symbolName: String
    let startURL: URL
    let allowedHostSuffixes: [String]
    let dataStoreID: UUID
}

extension Service {
    static let messenger = Service(
        id: .messenger,
        name: "Messenger",
        symbolName: "message.fill",
        startURL: URL(string: "https://www.messenger.com/")!,
        allowedHostSuffixes: ["messenger.com", "facebook.com", "fbcdn.net", "fbsbx.com", "meta.com"],
        dataStoreID: UUID(uuidString: "8E1C6A62-3B0F-4C2D-9C55-0A7E5B1D2F01")!
    )

    static let instagram = Service(
        id: .instagram,
        name: "Instagram",
        symbolName: "camera.fill",
        startURL: URL(string: "https://www.instagram.com/direct/inbox/")!,
        allowedHostSuffixes: ["instagram.com", "cdninstagram.com", "fbcdn.net", "facebook.com", "meta.com"],
        dataStoreID: UUID(uuidString: "8E1C6A62-3B0F-4C2D-9C55-0A7E5B1D2F02")!
    )

    static let all: [Service] = [messenger, instagram]

    static func with(_ id: ServiceID) -> Service {
        switch id {
        case .messenger: return messenger
        case .instagram: return instagram
        }
    }
}

extension Service {
    /// True when `url` is on the service's own app (where "Go to Inbox" leads): Messenger is
    /// messenger.com or facebook.com/messages, Instagram is instagram.com/direct.
    func isHome(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        func under(_ prefix: String) -> Bool {
            let path = url.path.lowercased()
            return path == prefix || path.hasPrefix(prefix + "/")
        }
        switch id {
        case .messenger: return on("messenger.com") || (on("facebook.com") && under("/messages"))
        case .instagram: return on("instagram.com") && under("/direct")
        }
    }
}
