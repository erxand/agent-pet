import Foundation

struct PetIdentityOverrides {
    let nickname: String?
    let label: String?
    let accent: AccentColor?
    let agent: PetAgent?
    let tmuxTarget: String?
    let pid: Int32?
    let sprite: String?

    static let none = PetIdentityOverrides(
        nickname: nil,
        label: nil,
        accent: nil,
        agent: nil,
        tmuxTarget: nil,
        pid: nil,
        sprite: nil
    )

    var hasAnyOverride: Bool {
        nickname != nil
            || label != nil
            || accent != nil
            || agent != nil
            || tmuxTarget != nil
            || pid != nil
            || sprite != nil
    }

    func applied(to session: PetSession) -> PetSession {
        var updated = session
        if let nickname { updated.nickname = nickname }
        if let label { updated.label = label }
        if let accent { updated.accent = accent }
        if let agent { updated.agent = agent }
        if let tmuxTarget { updated.tmuxTarget = tmuxTarget }
        if let pid { updated.pid = pid }
        if let sprite { updated.sprite = sprite }
        return updated
    }
}
