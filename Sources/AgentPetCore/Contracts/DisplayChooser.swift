import Foundation

package enum DisplayChoice: Equatable {
    case focused
    case primary
    case named(String)

    package static let focusedValue = "focused"
    package static let primaryValue = "primary"
    package static let namePrefix = "name:"

    /// `nil` for anything agent-pet does not understand, so the caller keeps the default.
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

/// The displays attached right now, in the order macOS lists them. The first is the primary
/// display, the one with the menu bar in System Settings.
package struct AttachedDisplays: Equatable {
    package let names: [String]
    package let focusedIndex: Int?

    package init(names: [String], focusedIndex: Int?) {
        self.names = names
        self.focusedIndex = focusedIndex
    }
}

package protocol DisplayChooser {
    /// The index into `displays.names` the pets live on, or `nil` when no display is attached.
    func chosenIndex(among displays: AttachedDisplays) -> Int?
}

private let primaryDisplayIndex = 0

private func primaryIndex(of displays: AttachedDisplays) -> Int? {
    displays.names.isEmpty ? nil : primaryDisplayIndex
}

/// Today's behavior: the display holding the window with keyboard focus, else the primary one.
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

/// One display by its macOS name, and the primary display while that one is not attached.
package struct NamedDisplayChooser: DisplayChooser {
    package let displayName: String

    package init(displayName: String) {
        self.displayName = displayName
    }

    package func chosenIndex(among displays: AttachedDisplays) -> Int? {
        displays.names.firstIndex(of: displayName) ?? primaryIndex(of: displays)
    }
}
