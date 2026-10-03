import Foundation

package struct TmuxTarget {
    private static let sessionSeparator: Character = ":"
    private static let paneSeparator: Character = "."

    package let sessionName: String
    package let windowIdentifier: String
    package let paneIdentifier: String

    package var windowTarget: String {
        "\(sessionName)\(TmuxTarget.sessionSeparator)\(windowIdentifier)"
    }

    package var rawValue: String {
        "\(windowTarget)\(TmuxTarget.paneSeparator)\(paneIdentifier)"
    }

    package init?(rawValue: String) {
        guard let sessionSeparatorIndex = rawValue.firstIndex(of: TmuxTarget.sessionSeparator) else { return nil }
        let sessionName = String(rawValue[rawValue.startIndex..<sessionSeparatorIndex])
        let remainder = String(rawValue[rawValue.index(after: sessionSeparatorIndex)...])
        guard let paneSeparatorIndex = remainder.firstIndex(of: TmuxTarget.paneSeparator) else { return nil }
        let windowIdentifier = String(remainder[remainder.startIndex..<paneSeparatorIndex])
        let paneIdentifier = String(remainder[remainder.index(after: paneSeparatorIndex)...])
        guard !sessionName.isEmpty, !windowIdentifier.isEmpty, !paneIdentifier.isEmpty else { return nil }
        self.sessionName = sessionName
        self.windowIdentifier = windowIdentifier
        self.paneIdentifier = paneIdentifier
    }
}
