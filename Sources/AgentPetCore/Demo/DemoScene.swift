import Foundation

package enum DemoSceneName: String, CaseIterable {
    case title
    case climbOut = "climb-out"
    case needsInput = "needs-input"
    case lanes
    case group
    case nametags
    case reserved
    case click
    case dive
    case finale
}

package struct DemoActor: Equatable {
    package let sessionId: String
    package let nickname: String
    package let sprite: String
    package let accent: AccentColor
    package let group: String?
    package let isOwner: Bool

    package init(
        sessionId: String,
        nickname: String,
        sprite: String,
        accent: AccentColor,
        group: String? = nil,
        isOwner: Bool = false
    ) {
        self.sessionId = sessionId
        self.nickname = nickname
        self.sprite = sprite
        self.accent = accent
        self.group = group
        self.isOwner = isOwner
    }
}

package struct DemoTitleCard: Equatable {
    package let title: String
    package let subtitle: String
    package let splash: String?

    package init(title: String, subtitle: String, splash: String?) {
        self.title = title
        self.subtitle = subtitle
        self.splash = splash
    }
}

package struct DemoCaption: Equatable {
    package let text: String
    package let sceneNumber: Int
    package let sceneCount: Int

    package init(text: String, sceneNumber: Int, sceneCount: Int) {
        self.text = text
        self.sceneNumber = sceneNumber
        self.sceneCount = sceneCount
    }
}

package struct DemoToast: Equatable {
    package let title: String
    package let body: String
    package let sprite: String

    package init(title: String, body: String, sprite: String) {
        self.title = title
        self.body = body
        self.sprite = sprite
    }
}

package enum DemoAction: Equatable {
    case showTitle(DemoTitleCard)
    case hideTitle
    case show(actorId: String, mood: PetMood, message: String?)
    case hide(actorIds: [String])
    case click(actorId: String)
    case toast(DemoToast)
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
    package let disambiguatesLabels: Bool
    package let steps: [DemoStep]
}
