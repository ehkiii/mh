import Foundation

/// Turns whatever was pasted into a clean link, or nil if there isn't one.
/// Handles share-sheet text ("Cool video https://youtu.be/abc"), quotes,
/// and addresses without a scheme ("youtu.be/abc").
enum LinkParser {
    static func normalize(_ raw: String) -> String? {
        let quotes = CharacterSet(charactersIn: "\"'“”‘’<>")
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: quotes)

        // 1. a full link somewhere in the text
        if let range = text.range(of: #"https?://[^\s<>"'“”‘’]+"#, options: .regularExpression) {
            let link = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            return isValid(link) ? link : nil
        }
        // 2. a bare address like youtu.be/abc or www.example.com/watch?v=1
        if text.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(/\S*)?$"#, options: .regularExpression) != nil {
            let link = "https://" + text
            return isValid(link) ? link : nil
        }
        return nil
    }

    private static func isValid(_ link: String) -> Bool {
        guard let url = URL(string: link), let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
