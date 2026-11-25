import Foundation

func runLoadRulesTests() {
    test("network errors retry") {
        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                     NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed] {
            check(LoadRules.isRetryableNetworkError(domain: NSURLErrorDomain, code: code), "\(code)")
        }
    }
    test("other errors do not retry") {
        check(!LoadRules.isRetryableNetworkError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), "cancelled")
        check(!LoadRules.isRetryableNetworkError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse), "bad response")
        check(!LoadRules.isRetryableNetworkError(domain: "WebKitErrorDomain", code: NSURLErrorTimedOut), "other domain")
    }
    test("retry backoff") {
        let delays = (0..<6).map { LoadRules.retryDelay(afterFailures: $0) }
        check(delays == [5, 15, 60, 60, 60, 60], "\(delays)")
    }
    test("attachment disposition") {
        check(LoadRules.isAttachment(contentDisposition: "attachment; filename=\"a.pdf\""), "attachment")
        check(LoadRules.isAttachment(contentDisposition: "  Attachment"), "case and space")
        check(!LoadRules.isAttachment(contentDisposition: "inline; filename=a.pdf"), "inline")
        check(!LoadRules.isAttachment(contentDisposition: nil), "nil")
        check(!LoadRules.isAttachment(contentDisposition: "attachmentfoo"), "lookalike")
    }
}
