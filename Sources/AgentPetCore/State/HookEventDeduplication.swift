import Foundation

enum HookEventDeduplication {
    static let retentionInSeconds: TimeInterval = 30
    static let maximumRememberedEvents = 16

    private static let fingerprintOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fingerprintPrime: UInt64 = 0x100000001b3
    private static let hexadecimalRadix = 16

    static func claim(identity: SubagentIdentity, in session: inout PetSession, now: TimeInterval) -> Bool {
        switch identity {
        case .reported, .unreported(fingerprint: nil):
            return true
        case .unreported(fingerprint: .some(let fingerprint)):
            var remembered = (session.handledHookEvents ?? []).filter { handledEvent in
                now - handledEvent.handledAt <= retentionInSeconds
            }
            let alreadyHandled = remembered.contains { handledEvent in handledEvent.fingerprint == fingerprint }
            if !alreadyHandled {
                remembered.append(HandledHookEvent(fingerprint: fingerprint, handledAt: now))
                remembered = Array(remembered.suffix(maximumRememberedEvents))
            }
            session.handledHookEvents = remembered.isEmpty ? nil : remembered
            return !alreadyHandled
        }
    }

    static func fingerprint(ofPayload payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              JSONSerialization.isValidJSONObject(object),
              let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        var hash = fingerprintOffsetBasis
        for byte in canonical {
            hash ^= UInt64(byte)
            hash = hash &* fingerprintPrime
        }
        return String(hash, radix: hexadecimalRadix)
    }
}
