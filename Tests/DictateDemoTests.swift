import XCTest
@testable import DictateDemo

final class DictateDemoTests: XCTestCase {
    @MainActor
    func testStripWakeWordMatches() {
        let cases: [(String, Bool, String)] = [
            ("Hey Claude, remind me to buy milk", true, "remind me to buy milk"),
            ("Hey claude take a note", true, "take a note"),
            ("hey Claude, hello", true, "hello"),
            ("Hey Cloud, test", true, "test"),
            ("Hey Claud, test", true, "test"),
            ("Hey Claude", true, ""),
            ("Hello world", false, "Hello world"),
            ("", false, ""),
        ]
        for (input, expectedMatch, expectedRemainder) in cases {
            let (matched, remainder) = DictateViewModel.stripWakeWord(input)
            XCTAssertEqual(matched, expectedMatch, "Input: \"\(input)\"")
            XCTAssertEqual(remainder, expectedRemainder, "Input: \"\(input)\"")
        }
    }
}
