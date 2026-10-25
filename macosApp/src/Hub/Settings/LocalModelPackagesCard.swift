import SwiftUI

struct LocalModelPackagesCard: View {
    let runtime: AppRuntime

    var body: some View {
        ModelSetupSettingsCard(
            model: runtime.modelSetup,
            language: runtime.language
        )
    }
}
