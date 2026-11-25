import Foundation

nonisolated(unsafe) var testFailures = 0

func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if !condition {
        testFailures += 1
        print("  FAIL \(file):\(line): \(message)")
    }
}

func test(_ name: String, _ body: () -> Void) {
    let before = testFailures
    body()
    print(testFailures == before ? "PASS \(name)" : "FAIL \(name)")
}
