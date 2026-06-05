import Foundation

public enum WakeWord {
    public static func strip(from text: String) -> (matched: Bool, remainder: String) {
        let pattern = #"^[Hh]ey[,.\s]+[Qq](wen|uen|ueen)[,.\s]*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return (false, text)
        }

        let remainder = text[range.upperBound...]
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return (true, remainder)
    }
}
