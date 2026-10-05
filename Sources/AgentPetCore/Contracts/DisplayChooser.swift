import Foundation

package enum DisplayChoice: Equatable {
    case focused
    case primary
    case named(String)

    package static let focusedValue = "focused"
    package static let primaryValue = "primary"
    package static let namePrefix = "name:"

    package init?(configValue: String) {
        switch configValue {
        case DisplayChoice.focusedValue:
            self = .focused
        case DisplayChoice.primaryValue:
            self = .primary
        default:
            guard configValue.hasPrefix(DisplayChoice.namePrefix) else { return nil }
            let displayName = String(configValue.dropFirst(DisplayChoice.namePrefix.count))
            guard !displayName.isEmpty else { return nil }
            self = .named(displayName)
        }
    }
}

package struct AttachedDisplays: Equatable {
    package let names: [String]
    package let focusedIndex: Int?

    package init(names: [String], focusedIndex: Int?) {
        self.names = names
        self.focusedIndex = focusedIndex
    }
}

package protocol DisplayChooser {
    func chosenIndex(among displays: AttachedDisplays) -> Int?
}

private let primaryDisplayIndex = 0

private func primaryIndex(of displays: AttachedDisplays) -> Int? {
    displays.names.isEmpty ? nil : primaryDisplayIndex
}

package struct FocusedDisplayChooser: DisplayChooser {
    package init() {}

    package func chosenIndex(among displays: AttachedDisplays) -> Int? {
        if let focusedIndex = displays.focusedIndex, displays.names.indices.contains(focusedIndex) {
            return focusedIndex
        }
        return primaryIndex(of: displays)
    }
}

package struct PrimaryDisplayChooser: DisplayChooser {
    package init() {}

    package func chosenIndex(among displays: AttachedDisplays) -> Int? {
        primaryIndex(of: displays)
    }
}

package struct NamedDisplayChooser: DisplayChooser {
    package let displayName: String

    package init(displayName: String) {
        self.displayName = displayName
    }

    package func chosenIndex(among displays: AttachedDisplays) -> Int? {
        displays.names.firstIndex(of: displayName) ?? primaryIndex(of: displays)
    }
}
