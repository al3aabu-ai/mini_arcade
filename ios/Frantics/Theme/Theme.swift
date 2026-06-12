import SwiftUI

enum Theme {
    static let bg = Color(hex: "#0B0B1F")
    static let panel = Color(hex: "#181834")
    static let panelLight = Color(hex: "#23234A")
    static let pink = Color(hex: "#FF2E88")
    static let cyan = Color(hex: "#00F5D4")
    static let yellow = Color(hex: "#FEE440")
    static let purple = Color(hex: "#9B5DE5")
    static let blue = Color(hex: "#00BBF9")
    static let orange = Color(hex: "#FB5607")
    static let red = Color(hex: "#FF3355")

    static let avatars = ["🐸", "🦊", "🐼", "🐙", "🦄", "🐯", "🐷", "🦖", "👻", "🤖", "🐳", "🦁"]
    static let colors = [
        "#FF2E88", "#00F5D4", "#FEE440", "#9B5DE5",
        "#00BBF9", "#FB5607", "#8AC926", "#FF99C8",
    ]

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Reusable pieces

struct NeonButtonStyle: ButtonStyle {
    var color: Color = Theme.pink
    var textColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.title(22))
            .foregroundStyle(textColor)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.65), radius: configuration.isPressed ? 4 : 16)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    func neonGlow(_ color: Color, radius: CGFloat = 14) -> some View {
        shadow(color: color.opacity(0.8), radius: radius)
    }
}

/// A player's circular avatar chip, used on both the phone and the TV board.
struct AvatarChip: View {
    let player: PlayerState
    var size: CGFloat = 64
    var dimmed: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(hex: player.color).opacity(0.25))
                Circle()
                    .strokeBorder(Color(hex: player.color), lineWidth: size / 16)
                Text(player.avatar)
                    .font(.system(size: size * 0.52))
            }
            .frame(width: size, height: size)
            .neonGlow(Color(hex: player.color), radius: size / 7)

            Text(player.name)
                .font(Theme.body(size * 0.24))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .opacity(dimmed ? 0.35 : 1)
        .saturation(dimmed ? 0.1 : 1)
    }
}

/// Countdown text driven by a server deadline.
struct CountdownLabel: View {
    let endsAt: Date
    var font: Font = Theme.title(44)
    var color: Color = Theme.yellow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            Text(String(format: "%.0f", remaining.rounded(.up)))
                .font(font)
                .foregroundStyle(remaining < 4 ? Theme.red : color)
                .contentTransition(.numericText())
                .monospacedDigit()
        }
    }
}
