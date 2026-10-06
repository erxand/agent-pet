import Foundation

package enum DemoSceneName: String, CaseIterable {
    case title
    case states
    case click
    case finale
    case space
}

package struct DemoActor: Equatable {
    package let sessionId: String
    package let nickname: String
    package let sprite: String
    package let accent: AccentColor

    package init(sessionId: String, nickname: String, sprite: String, accent: AccentColor) {
        self.sessionId = sessionId
        self.nickname = nickname
        self.sprite = sprite
        self.accent = accent
    }
}

package enum DemoKey: Equatable {
    case space
    case escape

    private static let spaceKeyCode: UInt16 = 49
    private static let escapeKeyCode: UInt16 = 53

    package init?(keyCode: UInt16) {
        switch keyCode {
        case DemoKey.spaceKeyCode: self = .space
        case DemoKey.escapeKeyCode: self = .escape
        default: return nil
        }
    }
}

package protocol DemoFocus: AnyObject {
    func takeFocus()
    func returnFocus()
}

package struct DemoStateSlot: Equatable {
    package let label: String
    package let actorId: String?

    package init(label: String, actorId: String?) {
        self.label = label
        self.actorId = actorId
    }
}

package struct DemoStateMark: Equatable {
    package let label: String
    package let sessionId: String?
    package let sprite: String?
    package let accent: AccentColor?

    package init(label: String, sessionId: String?, sprite: String?, accent: AccentColor?) {
        self.label = label
        self.sessionId = sessionId
        self.sprite = sprite
        self.accent = accent
    }
}

package struct DemoTitleCard: Equatable {
    package let title: String
    package let subtitle: String
    package let accent: AccentColor

    package init(title: String, subtitle: String, accent: AccentColor) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
    }
}

package struct DemoCursorCue: Equatable {
    package let targetSessionId: String
    package let pressed: Bool

    package init(targetSessionId: String, pressed: Bool) {
        self.targetSessionId = targetSessionId
        self.pressed = pressed
    }
}

package struct DemoTerminalCard: Equatable {
    package let title: String
    package let accent: AccentColor
    package let mascotSprite: String
    package let productName: String
    package let directory: String
    package let userMessage: String
    package let reply: String
    package let statusLine: String

    package init(
        title: String,
        accent: AccentColor,
        mascotSprite: String,
        productName: String,
        directory: String,
        userMessage: String,
        reply: String,
        statusLine: String
    ) {
        self.title = title
        self.accent = accent
        self.mascotSprite = mascotSprite
        self.productName = productName
        self.directory = directory
        self.userMessage = userMessage
        self.reply = reply
        self.statusLine = statusLine
    }

    package static let userPrompt = ">"
    package static let replyBullet = "\u{25CF}"
    package static let inputChevron = "\u{276F}"

    package var shownTexts: [String] {
        [
            title, productName, directory,
            "\(DemoTerminalCard.userPrompt) \(userMessage)",
            "\(DemoTerminalCard.replyBullet) \(reply)",
            DemoTerminalCard.inputChevron,
            statusLine
        ]
    }
}

package struct DemoCaption: Equatable {
    package let text: String
    package let sceneNumber: Int
    package let sceneCount: Int
    package let accent: AccentColor?

    package init(text: String, sceneNumber: Int, sceneCount: Int, accent: AccentColor?) {
        self.text = text
        self.sceneNumber = sceneNumber
        self.sceneCount = sceneCount
        self.accent = accent
    }
}

package enum DemoAction: Equatable {
    case showTitle(DemoTitleCard)
    case hideTitle
    case show(actorId: String, mood: PetMood, message: String?)
    case hide(actorIds: [String])
    case pointCursor(actorId: String)
    case click(actorId: String)
    case hideCursor
    case showTerminal(DemoTerminalCard)
    case hideTerminal
    case showScreensaver
    case hideScreensaver
}

package struct DemoStep: Equatable {
    package let offsetInSeconds: Double
    package let action: DemoAction
}

package struct DemoScene: Equatable {
    package let name: DemoSceneName
    package let caption: String?
    package let durationInSeconds: Double
    package let labelPlacement: LabelPlacement
    package let steps: [DemoStep]
    package var holdOffsetInSeconds: Double?
    package var stateSlots: [DemoStateSlot] = []
}
