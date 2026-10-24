import SwiftUI

/// 剪贴板设置页。
struct ClipboardPage: View {
    let runtime: AppRuntime

    var body: some View {
        MacCard {
            ClipboardCard(runtime: runtime)
        }
    }
}
