import SwiftUI

/// Legacy entry point — now routes to the Celestial Atlas instrument surface
/// so existing callers pick up the dark observatory styling automatically.
struct WidgetCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.instrumentCard()
    }
}

extension View {
    func widgetCard() -> some View {
        modifier(WidgetCardModifier())
    }
}
