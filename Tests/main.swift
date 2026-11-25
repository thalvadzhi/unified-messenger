import Foundation

runUnreadCountTests()
runLinkRouterTests()
runNotificationRulesTests()
runBridgeScriptTests()
runServiceTests()
runLoadRulesTests()

if testFailures > 0 {
    print("\(testFailures) failures")
    exit(1)
}
print("All tests passed")
