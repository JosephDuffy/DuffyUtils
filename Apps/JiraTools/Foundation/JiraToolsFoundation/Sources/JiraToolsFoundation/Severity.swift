public enum Severity: String, CaseIterable, Codable, Comparable, Sendable {
    case error
    case warning
    case ok
    case neutral

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.priority < rhs.priority
    }

    public var label: String {
        switch self {
        case .error:
            "ERROR"
        case .warning:
            "WARN"
        case .ok:
            "OK"
        case .neutral:
            "INFO"
        }
    }

    private var priority: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .neutral: 2
        case .ok: 3
        }
    }
}
