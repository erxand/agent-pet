import Foundation

package enum PetMood: String, Codable, CaseIterable {
    case ready
    case needsInput
    case blocked
}

package enum PetAgent: String, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case pi
}

package struct TrackedSubagent: Codable, Equatable {
    package var id: String
    package var startedAt: TimeInterval
}

package struct PetSession: Codable, Equatable {
    package static let previewSessionIdPrefix = "preview-"
    package static let previewNickname = "preview"
    package static let initialTranscriptScanOffset = 0

    package var sessionId: String
    package var enabled: Bool
    package var visible: Bool
    package var nickname: String?
    package var label: String?
    package var accent: AccentColor?
    package var mood: PetMood
    package var message: String?
    package var agent: PetAgent
    package var tmuxTarget: String?
    package var pid: Int32?
    package var sprite: String?
    package var focusTarget: String?
    package var activeSubagents: [TrackedSubagent]
    package var transcriptPath: String?
    package var transcriptScanOffset: Int
    package var updatedAt: Double

    package var isPreview: Bool {
        sessionId.hasPrefix(PetSession.previewSessionIdPrefix)
    }

    package var resolvedAccent: AccentColor {
        accent ?? AccentColor.derived(fromSessionId: sessionId)
    }

    package var parsedTmuxTarget: TmuxTarget? {
        tmuxTarget.flatMap { rawTarget in TmuxTarget(rawValue: rawTarget) }
    }
}

extension PetSession {
    private enum LegacyCodingKeys: String, CodingKey {
        case activeSubagentIds
    }

    package init(from decoder: Decoder) throws {
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
        focusTarget = try container.decodeIfPresent(String.self, forKey: .focusTarget)
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

    package static func newlyEnrolled(sessionId: String) -> PetSession {
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
            focusTarget: nil,
            activeSubagents: [],
            transcriptPath: nil,
            transcriptScanOffset: initialTranscriptScanOffset,
            updatedAt: Date().timeIntervalSince1970
        )
    }
}
