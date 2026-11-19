import SwiftUI
import SwiftData

@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = WorkspaceStore.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}

#Preview("Sign In") {
    AuthenticationView()
        .environment(AuthenticationViewModel())
}

#Preview("Today") {
    TodayTabView(openTab: { _ in })
        .modelContainer(PreviewSupport.container)
        .environment(AuthenticationViewModel())
        .environment(CompetitionWorkspace())
}
