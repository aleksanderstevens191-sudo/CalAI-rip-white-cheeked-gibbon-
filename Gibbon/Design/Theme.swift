import SwiftUI
import UIKit

extension Color {
    static func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

enum Theme {
    static let background = Color.dyn(UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1), UIColor(white: 0.035, alpha: 1))
    static let card = Color.dyn(.white, UIColor(white: 0.11, alpha: 1))
    static let cardMuted = Color.dyn(UIColor(red: 0.95, green: 0.95, blue: 0.965, alpha: 1), UIColor(white: 0.16, alpha: 1))
    static let ink = Color.dyn(.black, .white)
    static let inkInverse = Color.dyn(.white, .black)
    static let track = Color.dyn(UIColor(white: 0.91, alpha: 1), UIColor(white: 0.24, alpha: 1))
    static let border = Color.dyn(UIColor(white: 0.9, alpha: 1), UIColor(white: 0.22, alpha: 1))

    static let protein = Color(red: 0.90, green: 0.38, blue: 0.36)
    static let carbs = Color(red: 0.91, green: 0.60, blue: 0.27)
    static let fat = Color(red: 0.31, green: 0.52, blue: 0.93)
    static let fiber = Color(red: 0.56, green: 0.42, blue: 0.86)
    static let sugar = Color(red: 0.93, green: 0.40, blue: 0.62)
    static let sodium = Color(red: 0.88, green: 0.70, blue: 0.24)
    static let water = Color(red: 0.25, green: 0.62, blue: 0.95)
    static let burn = Color(red: 0.96, green: 0.48, blue: 0.20)

    static let good = Color(red: 0.24, green: 0.72, blue: 0.45)
    static let warn = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let bad = Color(red: 0.91, green: 0.30, blue: 0.30)

    static let cornerRadius: CGFloat = 22
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(colors: scheme == .dark
                           ? [Color(white: 0.12), Theme.background]
                           : [Color(red: 0.93, green: 0.92, blue: 0.97), Theme.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
        }
        .ignoresSafeArea()
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.045), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(enabled ? Theme.inkInverse : Color.white.opacity(0.9))
            .background(enabled ? Theme.ink : Color.gray.opacity(0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Theme.ink)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? Theme.inkInverse : Theme.ink)
            .background(filled ? Theme.ink : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(filled ? .clear : Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
