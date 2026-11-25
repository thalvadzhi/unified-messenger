import Foundation
import Observation

/// UI state shared by the sidebar and the app delegate.
@MainActor @Observable
final class AppModel {
    var selected: ServiceID = .messenger
    var unread: [ServiceID: Int] = [:]

    var totalUnread: Int {
        unread.values.reduce(0) { $0 + max($1, 0) }
    }
}
