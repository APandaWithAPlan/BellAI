import Foundation
import Observation

// the places in the app other than chat
enum Feature: String, CaseIterable, Identifiable {
    case chat, tasks, mail, meals, captures, recorder

    var id: Self { self }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .tasks: "Tasks"
        case .mail: "Mail"
        case .meals: "Meals"
        case .captures: "Captures"
        case .recorder: "Recorder"
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left"
        case .tasks: "checklist"
        case .mail: "envelope"
        case .meals: "fork.knife"
        case .captures: "video"
        case .recorder: "mic"
        }
    }
}

// a meal is kept in the journal the recommendations come from. a Mac has no Apple Health to log it to as well
struct LocalMealLogger: MealLogging {
    func log(_ nutrition: Nutrition, name: String) async throws {}
}

// what the iOS app's screens are built on, shared with it: tasks and mail on the data and voice servers, meals and
// recommendations, and the home camera's captures
@MainActor @Observable
final class Features {
    var section = Feature.chat

    let tasks = TasksViewModel(store: HTTPUserDataService())
    let mail = MailViewModel(service: HTTPMailService())
    let captures = CapturesViewModel(service: HTTPCaptureService())
    let journal: MealJournal
    let meal: MealPhotoViewModel
    let insights: InsightsViewModel

    init() {
        let journal = MealJournal()
        self.journal = journal
        meal = MealPhotoViewModel(foodService: HTTPFoodAnalysisService(), logger: LocalMealLogger(), journal: journal)
        insights = InsightsViewModel(service: HTTPInsightsService(), journal: journal)
    }

    // BellAI gets your open tasks and important emails as context when you chat
    var chatContext: String? {
        let facts = [tasks.openTaskSummary, mail.importantSummary].compactMap { $0 }
        return facts.isEmpty ? nil : facts.joined(separator: ", and ")
    }

    // so the chat and the badges know about them without opening those screens
    func load() async {
        async let loadingMail: Void = mail.refresh()
        await tasks.load()
        await loadingMail
    }

    // after the server's address changed, what is there is a different set of data
    func reload() async {
        async let mailbox: Void = mail.reload()
        async let clips: Void = captures.reload()
        await tasks.reload()
        _ = await (mailbox, clips)
    }
}
