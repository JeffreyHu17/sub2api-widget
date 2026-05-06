import WidgetKit
import SwiftUI

@main
struct Sub2APIWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlatformActivityStatusWidget()
        PlatformActivityStatusWidget(platform: .anthropic)
        PlatformActivityStatusWidget(platform: .openai)
        PlatformActivityStatusWidget(platform: .gemini)
        PlatformActivityStatusWidget(platform: .antigravity)
        ServerHealthStatusWidget()
    }
}
