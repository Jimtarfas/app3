import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            SendView()
                .tabItem { Label("Send Fax", systemImage: "paperplane") }
                .tag(Router.Tab.send)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Router.Tab.history)
            CoverSheetTab()
                .tabItem { Label("Cover Sheet", systemImage: "doc.text") }
                .tag(Router.Tab.cover)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
        .sheet(isPresented: $router.showPaywall) {
            PaywallView()
        }
    }
}
