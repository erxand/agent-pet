import AgentPetCore
import AppKit

/// The menu bar icon and its two toggles. It only reports what was flipped, and the
/// controller decides what that means.
final class PetMenuBar: NSObject {
    static let hidePetsTitle = "Hide pets"
    static let opensAtLoginTitle = "Re-open after computer restarts"

    /// A pet coming up out of the ground: the top of the claude sprite above a line, eyes
    /// cut out so it reads on either menu bar.
    static let iconRows = [
        "................",
        "................",
        "................",
        ".....######.....",
        "...##########...",
        "..#####..#..##..",
        "..#####..#..##..",
        "..############..",
        "..############..",
        "...##########...",
        ".#############..",
        "##############..",
        "..############..",
        "################",
        "................",
        "................"
    ]

    private let statusItem: NSStatusItem
    private let hidePetsRow: PetMenuBarToggleRow
    private let opensAtLoginRow: PetMenuBarToggleRow

    init(
        settings: PetMenuBarSettings,
        hidePetsChanged: @escaping (Bool) -> Void,
        opensAtLoginChanged: @escaping (Bool) -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        hidePetsRow = PetMenuBarToggleRow(title: PetMenuBar.hidePetsTitle, isOn: settings.hidesPets, changed: hidePetsChanged)
        opensAtLoginRow = PetMenuBarToggleRow(title: PetMenuBar.opensAtLoginTitle, isOn: settings.opensAtLogin, changed: opensAtLoginChanged)
        super.init()
        statusItem.button?.image = PetMenuBar.iconImage()
        statusItem.button?.toolTip = "Agent Pet"
        let menu = NSMenu()
        for row in [hidePetsRow, opensAtLoginRow] {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        statusItem.menu = menu
        show(hidesPets: settings.hidesPets)
    }

    func show(hidesPets: Bool) {
        hidePetsRow.isOn = hidesPets
        statusItem.button?.appearsDisabled = hidesPets
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    static func iconImage() -> NSImage {
        let rows = iconRows
        let side = CGFloat(rows.count)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setFill()
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, character) in row.enumerated() where character == "#" {
                    NSRect(x: CGFloat(columnIndex), y: side - 1 - CGFloat(rowIndex), width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class PetMenuBarToggleRow: NSView {
    private static let size = NSSize(width: 300, height: 30)
    private static let sidePadding: CGFloat = 14

    private let toggle = NSSwitch()
    private let changed: (Bool) -> Void

    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }

    init(title: String, isOn: Bool, changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init(frame: NSRect(origin: .zero, size: PetMenuBarToggleRow.size))
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 0)
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(title)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PetMenuBarToggleRow.size.width),
            heightAnchor.constraint(equalToConstant: PetMenuBarToggleRow.size.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PetMenuBarToggleRow.sidePadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PetMenuBarToggleRow.sidePadding),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    @objc private func toggled() {
        changed(isOn)
    }
}
