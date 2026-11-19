import Foundation
import Observation

// the camera's previous captures, newest first
@MainActor
@Observable
final class CapturesViewModel {
    // one day of captures, newest first
    struct Day: Identifiable, Equatable {
        let date: Date // the start of the day
        let captures: [Capture]
        var id: Date { date }
    }

    private(set) var captures: [Capture] = []
    private(set) var total = 0
    private(set) var isLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: any CaptureService
    private let limit = 500 // the most the server gives at once, which is a good many days of clips

    init(service: any CaptureService) {
        self.service = service
    }

    var recent: [Capture] { Array(captures.prefix(3)) }

    func days(calendar: Calendar = .current) -> [Day] {
        Dictionary(grouping: captures) { calendar.startOfDay(for: $0.startedAt ?? .distantPast) }
            .map { Day(date: $0.key, captures: $0.value.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }) }
            .sorted { $0.date > $1.date }
    }

    func videoURL(for capture: Capture) -> URL { service.videoURL(for: capture) }
    func thumbnailURL(for capture: Capture) -> URL { service.thumbnailURL(for: capture) }

    // keeps what is shown if it fails, so a bad connection doesn't empty the screen
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.captures(limit: limit)
            captures = result.captures
            total = result.total
            isLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // for after the server changed, what is there is a different set of clips
    func reload() async {
        captures = []
        total = 0
        isLoaded = false
        errorMessage = nil
        await load()
    }
}
