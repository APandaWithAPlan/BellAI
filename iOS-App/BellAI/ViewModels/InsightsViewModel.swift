import Foundation
import Observation

// food and workout recommendations from today's meals and the person's preferences
@MainActor
@Observable
final class InsightsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(Insights)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var preferences: FoodPreferences
    private let service: any InsightsService
    private let journal: MealJournal
    private let defaults: UserDefaults
    private var run: UUID?

    init(service: any InsightsService, journal: MealJournal, defaults: UserDefaults = .standard) {
        self.service = service
        self.journal = journal
        self.defaults = defaults
        preferences = FoodPreferencesStore.load(defaults: defaults)
    }

    var mealCount: Int { journal.today().count }

    // asks for recommendations on today's meals, or on `sample` meals for trying it out without logging anything
    func refresh(sample: [LoggedMeal]? = nil) async {
        guard phase != .loading else { return }
        let id = UUID()
        run = id
        phase = .loading
        do {
            let result = try await service.insights(for: preferences, meals: sample ?? journal.today())
            guard run == id else { return } // preferences changed while it was working
            phase = .loaded(result)
        } catch is CancellationError {
            if run == id { phase = .idle }
        } catch {
            guard run == id else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    // returns what is wrong with the preferences, or nil once they are saved. what was shown no longer fits them
    func save(_ new: FoodPreferences) -> String? {
        if let problem = new.problem { return problem }
        guard new != preferences else { return nil }
        FoodPreferencesStore.save(new, defaults: defaults)
        preferences = new
        run = nil
        phase = .idle
        return nil
    }
}
