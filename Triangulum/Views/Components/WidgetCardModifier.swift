import SwiftUI

struct WidgetCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.prussianBlue.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func widgetCard() -> some View {
        modifier(WidgetCardModifier())
    }
}
