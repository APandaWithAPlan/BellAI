import Foundation
import Observation

// a photo of a meal: analyzed, shown for the person to correct, then logged. it never touches the chat
@MainActor
@Observable
final class MealPhotoViewModel {
    enum Phase: Equatable {
        case idle
        case analyzing
        case result(MealResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isLogging = false
    var logError: String?
    var isShown = false

    var isBusy: Bool { phase == .analyzing || isLogging }

    private let foodService: (any FoodAnalysisService)?
    private let logger: (any MealLogging)?
    private let journal: MealJournal?
    private var pending: (jpeg: Data, note: String)?
    private var note = ""
    private var run: UUID?

    init(foodService: (any FoodAnalysisService)? = nil, logger: (any MealLogging)? = nil, journal: MealJournal? = nil) {
        self.foodService = foodService
        self.logger = logger
        self.journal = journal
    }

    /// Starts on a JPEG with an optional note and shows the result sheet. Finish it with `analyzeStored()`.
    /// false if one is already going or there is no food server to ask.
    @discardableResult
    func begin(_ jpeg: Data, note: String = "") -> Bool {
        guard !isBusy, foodService != nil else { return false }
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        pending = (jpeg, self.note)
        phase = .analyzing
        logError = nil
        run = UUID()
        isShown = true
        return true
    }

    func analyzeStored() async {
        guard let photo = pending, let foodService, let id = run else { return }
        pending = nil
        do {
            let meal = try await foodService.analyze(jpeg: photo.jpeg, note: photo.note.isEmpty ? nil : photo.note)
            guard run == id else { return } // closed while it was working
            phase = .result(MealResult(meal))
        } catch {
            guard run == id else { return }
            phase = .failed(error is CancellationError ? "The request was cancelled. Please try again." : error.localizedDescription)
        }
    }

    /// The person's correction of the calories and protein, which logs the meal too. false if it was refused.
    @discardableResult
    func correctAndLog(_ nutrition: Nutrition) async -> Bool {
        guard !isLogging, case .result(var meal) = phase, !meal.isLogged, meal.correct(to: nutrition) else { return false }
        phase = .result(meal)
        await log()
        return true
    }

    /// Logs the meal as it stands.
    func log() async {
        guard !isLogging, case .result(let meal) = phase, !meal.isLogged, let nutrition = meal.current else { return }
        guard let logger else {
            logError = MealLoggingError.unavailable.localizedDescription
            return
        }
        isLogging = true
        logError = nil
        defer { isLogging = false }
        do {
            try await logger.log(nutrition, name: note.isEmpty ? "Meal" : note)
            // only once Health has it, so trying again after a failure can't count a meal twice
            if let nutrients = meal.loggedNutrients { journal?.add(name: note.isEmpty ? "Meal" : note, nutrients: nutrients) }
            if case .result(var latest) = phase {
                latest.isLogged = true
                phase = .result(latest)
            }
        } catch {
            logError = error.localizedDescription
        }
    }

    func dismiss() {
        isShown = false
        run = nil
        pending = nil
        phase = .idle
        logError = nil
    }
}
