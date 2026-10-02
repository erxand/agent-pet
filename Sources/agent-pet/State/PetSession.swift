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

struct TrackedSubagent: Codable, Equatable {
    var id: String
    var startedAt: TimeInterval
}

struct PetSession: Codable, Equatable {
    static let previewSessionIdPrefix = "preview-"
    static let previewNickname = "preview"
    static let initialTranscriptScanOffset = 0

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
    var activeSubagents: [TrackedSubagent]
    var transcriptPath: String?
    var transcriptScanOffset: Int
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
    private enum LegacyCodingKeys: String, CodingKey {
        case activeSubagentIds
    }

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
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        transcriptScanOffset = try container.decodeIfPresent(Int.self, forKey: .transcriptScanOffset)
            ?? PetSession.initialTranscriptScanOffset
        activeSubagents = try container.decodeIfPresent([TrackedSubagent].self, forKey: .activeSubagents)
            ?? PetSession.decodeLegacySubagents(from: decoder, startedAt: updatedAt)
    }

    private static func decodeLegacySubagents(from decoder: Decoder, startedAt: TimeInterval) throws -> [TrackedSubagent] {
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyIds = try legacyContainer.decodeIfPresent([String].self, forKey: .activeSubagentIds) ?? []
        return legacyIds.map { legacyId in TrackedSubagent(id: legacyId, startedAt: startedAt) }
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
            activeSubagents: [],
            transcriptPath: nil,
            transcriptScanOffset: initialTranscriptScanOffset,
            updatedAt: Date().timeIntervalSince1970
        )
    }
}
