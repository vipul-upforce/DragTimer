import Foundation

struct DurationMapper {
    /// Converts drag distance (screen points) into a friendly timer duration.
    /// Piecewise mapping keeps short timers precise while still allowing long drags.
    static func seconds(for distance: CGFloat, optionMultiplier: Bool = false, precisionMode: Bool = false) -> TimeInterval {
        let d = max(0, Double(distance))
        var minutes: Double

        switch d {
        case 0..<18:
            minutes = 0
        case 18..<120:
            // 1–20 min: fine control
            minutes = max(1, ((d - 18) / 5.1).rounded())
        case 120..<360:
            // 20 min–2 h: 5 minute steps
            let extra = ((d - 120) / 12.0).rounded() * 5.0
            minutes = 20 + extra
        default:
            // Beyond 2 h: 15 minute steps
            let extra = ((d - 360) / 20.0).rounded() * 15.0
            minutes = 120 + extra
        }

        if precisionMode { minutes = max(1, (minutes / 4.0).rounded()) }
        if optionMultiplier { minutes *= 4.0 }

        return min(minutes * 60.0, 72 * 60 * 60)
    }

    static func label(for seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Drag farther" }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(minutes)m"
    }
}
