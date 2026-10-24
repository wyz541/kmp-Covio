#if DEBUG
import SwiftUI

/// Debug-only canvas for comparing plate materials over stable artwork.
/// The artwork contains no user data.
@MainActor
struct HubGlassPlatePreviewRoot: View {
    let colorScheme: ColorScheme

    @State private var workbench = WorkbenchModel()
    @State private var chrome = HubChromeModel()

    private let size = CGSize(width: 1_120, height: 760)

    private var geometry: ScreenGeometry {
        ScreenGeometry(
            frame: CGRect(origin: .zero, size: size),
            visibleFrame: CGRect(origin: .zero, size: size),
            safeAreaTop: 0,
            notch: nil
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            HubView(
                geometry: geometry,
                isExpanded: true,
                reduceMotion: true,
                hubState: .open,
                outputState: .ready,
                workbench: workbench,
                chrome: chrome,
                runtime: nil
            )
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, colorScheme)
        .onAppear {
            workbench.language = .simplifiedChinese
        }
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.10, blue: 0.20), Color(red: 0.20, green: 0.08, blue: 0.19)]
                    : [Color(red: 0.82, green: 0.91, blue: 0.98), Color(red: 0.98, green: 0.91, blue: 0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(colorScheme == .dark ? Color.cyan.opacity(0.38) : Color.teal.opacity(0.28))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(x: -360, y: -180)
            Circle()
                .fill(colorScheme == .dark ? Color.pink.opacity(0.28) : Color.orange.opacity(0.24))
                .frame(width: 500, height: 500)
                .blur(radius: 50)
                .offset(x: 340, y: 210)
        }
        .ignoresSafeArea()
    }
}
#endif
