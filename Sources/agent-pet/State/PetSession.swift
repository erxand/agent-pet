import Foundation

enum PetMood: String, Codable, CaseIterable {
    case ready
    case needsInput
    case blocked
}

enum PetAgent: String, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case pi
}

struct PetSession: Codable {
    static let previewSessionIdPrefix = "preview-"
    static let previewNickname = "preview"

    var sessionId: String
    var enabled: Bool
    var visible: Bool
    var nickname: String?
    var label: String?
    var accent: AccentColor?
    var mood: PetMood
    var message: String?
    var agent: PetAgent
    var tmuxTarget: String?
    var pid: Int32?
    var sprite: String?
    var updatedAt: Double

    var isPreview: Bool {
        sessionId.hasPrefix(PetSession.previewSessionIdPrefix)
    }

    var resolvedAccent: AccentColor {
        accent ?? AccentColor.derived(fromSessionId: sessionId)
    }

    var parsedTmuxTarget: TmuxTarget? {
        tmuxTarget.flatMap { rawTarget in TmuxTarget(rawValue: rawTarget) }
    }
}

extension PetSession {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? false
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        accent = try container.decodeIfPresent(AccentColor.self, forKey: .accent)
        mood = try container.decodeIfPresent(PetMood.self, forKey: .mood) ?? .ready
        message = try container.decodeIfPresent(String.self, forKey: .message)
        agent = try container.decodeIfPresent(PetAgent.self, forKey: .agent) ?? .claudeCode
        tmuxTarget = try container.decodeIfPresent(String.self, forKey: .tmuxTarget)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        sprite = try container.decodeIfPresent(String.self, forKey: .sprite)
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? Date().timeIntervalSince1970
    }

    static func newlyEnrolled(sessionId: String) -> PetSession {
        PetSession(
            sessionId: sessionId,
            enabled: true,
            visible: false,
            nickname: nil,
            label: nil,
            accent: nil,
            mood: .ready,
            message: nil,
            agent: .claudeCode,
            tmuxTarget: nil,
            pid: nil,
            sprite: nil,
            updatedAt: Date().timeIntervalSince1970
        )
    }
}
