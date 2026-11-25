import Foundation

runUnreadCountTests()

if testFailures > 0 {
    print("\(testFailures) failures")
    exit(1)
}
print("All tests passed")
