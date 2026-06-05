import XCTest
@testable import QwenDictateCore

final class QwenDictateTests: XCTestCase {
    @MainActor
    func testStripWakeWordMatches() {
        let cases: [(String, Bool, String)] = [
            ("Hey Qwen, remind me to buy milk", true, "remind me to buy milk"),
            ("Hey qwen take a note", true, "take a note"),
            ("hey Qwen, hello", true, "hello"),
            ("Hey Quen, test", true, "test"),
            ("Hey Queen, test", true, "test"),
            ("Hey Qwen", true, ""),
            ("Hey Assistant, remind me to buy milk", false, "Hey Assistant, remind me to buy milk"),
            ("Hello world", false, "Hello world"),
            ("", false, ""),
        ]
        for (input, expectedMatch, expectedRemainder) in cases {
            let (matched, remainder) = WakeWord.strip(from: input)
            XCTAssertEqual(matched, expectedMatch, "Input: \"\(input)\"")
            XCTAssertEqual(remainder, expectedRemainder, "Input: \"\(input)\"")
        }
    }
}
