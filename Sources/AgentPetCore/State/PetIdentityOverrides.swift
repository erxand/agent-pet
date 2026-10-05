import Foundation

struct PetIdentityOverrides {
    let nickname: String?
    let label: String?
    let accent: AccentColor?
    let agent: PetAgent?
    let tmuxTarget: String?
    let pid: Int32?
    let sprite: String?
    let focusTarget: String?
    let group: String?
    let owner: Bool

    static let none = PetIdentityOverrides(
        nickname: nil,
        label: nil,
        accent: nil,
        agent: nil,
        tmuxTarget: nil,
        pid: nil,
        sprite: nil,
        focusTarget: nil,
        group: nil,
        owner: false
    )

    var hasAnyOverride: Bool {
        nickname != nil
            || label != nil
            || accent != nil
            || agent != nil
            || tmuxTarget != nil
            || pid != nil
            || sprite != nil
            || focusTarget != nil
            || group != nil
            || owner
    }

    func applied(to session: PetSession) -> PetSession {
        var updated = session
        if let nickname { updated.nickname = nickname }
        if let label { updated.label = label }
        if let accent {
            updated.accent = accent
            updated.accentFromPack = false
        }
        if let agent { updated.agent = agent }
        if let tmuxTarget { updated.tmuxTarget = tmuxTarget }
        if let pid { updated.pid = pid }
        if let sprite { updated.sprite = sprite }
        if let focusTarget { updated.focusTarget = focusTarget }
        if let group { updated.group = group }
        if owner { updated.owner = true }
        if updated.group != nil, updated.enrolledAt == nil { updated.enrolledAt = Date().timeIntervalSince1970 }
        return updated
    }
}
