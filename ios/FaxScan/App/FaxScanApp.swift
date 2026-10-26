import SwiftUI
import SwiftData

@main
struct FaxScanApp: App {
    @State private var store = Store()
    @State private var router = Router()
    @State private var draft = FaxDraft()
    private let container: ModelContainer

    init() {
        #if DEBUG
        if DemoMode.screen != nil {
            DemoMode.prepareDefaults()
            container = DemoMode.container()
            return
        }
        #endif
        container = try! ModelContainer(for: FaxRecord.self)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(draft)
                .tint(Theme.accent)
                #if DEBUG
                .task {
                    if let screen = DemoMode.screen {
                        DemoMode.apply(screen: screen, router: router, draft: draft, context: container.mainContext)
                    }
                }
                #endif
        }
        .modelContainer(container)
    }
}

enum AppLinks {
    static let site = URL(string: "https://jimtarfas.github.io/fax-and-scan-site/")!
    static let privacy = URL(string: "https://jimtarfas.github.io/fax-and-scan-site/privacy.html")!
    static let terms = URL(string: "https://jimtarfas.github.io/fax-and-scan-site/terms.html")!
    static let support = URL(string: "https://jimtarfas.github.io/fax-and-scan-site/support.html")!
    static let supportEmail = "nouhe.tarfas@gmail.com"
}

enum Theme {
    static let accent = Color("AccentColor")
    static let weeklyPageLimit = 100
    static let maxPagesPerFax = 50
}

@MainActor @Observable
final class Router {
    enum Tab: Hashable { case send, history, cover, settings }
    var tab: Tab = .send
    var openFaxID: UUID?
    var showPaywall = false
}
