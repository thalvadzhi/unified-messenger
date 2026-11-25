import Foundation

enum LoadRules {
    private static let retryableCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
    ]

    /// True for failures caused by the network being down or flaky (worth retrying later).
    static func isRetryableNetworkError(domain: String, code: Int) -> Bool {
        domain == NSURLErrorDomain && retryableCodes.contains(code)
    }

    /// Delay before the next retry after `failures` consecutive retries: 5 s, 15 s, 60 s, then 60 s.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        let delays: [TimeInterval] = [5, 15, 60]
        return failures < delays.count ? delays[max(failures, 0)] : 60
    }

    /// True when a `Content-Disposition` header asks for the response to be saved, not shown.
    static func isAttachment(contentDisposition: String?) -> Bool {
        guard let value = contentDisposition?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        let type = value.split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
        return type == "attachment"
    }
}
