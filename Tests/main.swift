import Foundation

runUnreadCountTests()
runLinkRouterTests()
runNotificationRulesTests()
runBridgeScriptTests()
runLoadRulesTests()

if testFailures > 0 {
    print("\(testFailures) failures")
    exit(1)
}
print("All tests passed")
