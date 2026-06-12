// Minimal zero-dependency test harness: XCTest is unavailable on
// CommandLineTools-only machines, so tests run as a plain executable.
import Foundation

var failureCount = 0
var assertionCount = 0

func expect(
    _ condition: @autoclosure () -> Bool, _ name: String,
    file: String = #file, line: Int = #line
) {
    assertionCount += 1
    if !condition() {
        failureCount += 1
        print("FAIL \(name)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ name: String,
    file: String = #file, line: Int = #line
) {
    assertionCount += 1
    if actual != expected {
        failureCount += 1
        print("FAIL \(name): got \(actual), expected \(expected)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func expectEqual(
    _ actual: Double, _ expected: Double, accuracy: Double, _ name: String,
    file: String = #file, line: Int = #line
) {
    assertionCount += 1
    if abs(actual - expected) > accuracy {
        failureCount += 1
        print("FAIL \(name): got \(actual), expected \(expected) ± \(accuracy)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func finish() -> Never {
    if assertionCount == 0 {
        print("WARNING — no assertions ran (test suite not registered in main.swift?)")
    }
    print(failureCount == 0
        ? "OK — \(assertionCount) assertions passed"
        : "FAILED — \(failureCount) of \(assertionCount) assertions failed")
    exit(failureCount == 0 ? 0 : 1)
}
