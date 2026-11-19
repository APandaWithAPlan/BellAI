import Foundation

// one clip the home camera recorded when something moved
struct Capture: Identifiable, Equatable, Decodable {
    let id: String
    let startedAt: Date?
    let durationSeconds: Int
    let peakMotionPercent: Double?
    let sizeBytes: Int
    let isAvailable: Bool // false while the drive the recordings are on isn't connected to the Mac

    private enum CodingKeys: String, CodingKey {
        case id, available
        case startedAt = "started_at"
        case durationSeconds = "duration_s"
        case peakMotionPercent = "peak_motion_pct"
        case sizeBytes = "size_bytes"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        startedAt = ISO8601DateFormatter().date(from: try values.decodeIfPresent(String.self, forKey: .startedAt) ?? "")
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        peakMotionPercent = try values.decodeIfPresent(Double.self, forKey: .peakMotionPercent)
        sizeBytes = try values.decodeIfPresent(Int.self, forKey: .sizeBytes) ?? 0
        isAvailable = try values.decodeIfPresent(Bool.self, forKey: .available) ?? false
    }

    init(id: String, startedAt: Date?, durationSeconds: Int = 0, peakMotionPercent: Double? = nil, sizeBytes: Int = 0, isAvailable: Bool = true) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.peakMotionPercent = peakMotionPercent
        self.sizeBytes = sizeBytes
        self.isAvailable = isAvailable
    }

    // 0:18, or 1:04
    var durationText: String {
        "\(durationSeconds / 60):" + String(format: "%02d", durationSeconds % 60)
    }

    var motionText: String? {
        peakMotionPercent.map { "Motion \(Int($0.rounded()))%" }
    }
}
