import SwiftUI

/// Name + avatar + color picker, used for both hosting and joining.
struct ProfileSetupView: View {
    @EnvironmentObject var client: GameClient
    @Environment(\.dismiss) private var dismiss
    let isHost: Bool

    @State private var name = ""
    @State private var code = ""
    @State private var avatar = Theme.avatars.randomElement() ?? "🐸"
    @State private var color = Theme.colors.randomElement() ?? "#FF2E88"

    private var canSubmit: Bool {
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let codeOK = isHost || code.trimmingCharacters(in: .whitespaces).count == 4
        return nameOK && codeOK && client.connection != .connecting
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(width: 44, height: 5)
                        .padding(.top, 10)

                    Text(isHost ? "HOST A PARTY" : "JOIN A PARTY")
                        .font(Theme.title(28))
                        .foregroundStyle(.white)

                    if !isHost {
                        TextField("ROOM CODE", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(Theme.title(32))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.cyan)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                            .onChange(of: code) { _, value in
                                code = String(value.uppercased().filter(\.isLetter).prefix(4))
                            }
                            .padding(.horizontal, 24)
                    }

                    TextField("Your name", text: $name)
                        .font(Theme.body(20))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                        .padding(.horizontal, 24)
                        .onChange(of: name) { _, value in
                            name = String(value.prefix(14))
                        }

                    VStack(spacing: 10) {
                        Text("PICK YOUR FIGHTER")
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.45))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(Theme.avatars, id: \.self) { emoji in
                                Button {
                                    avatar = emoji
                                    Haptics.tick()
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 30))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(avatar == emoji ? Color(hex: color).opacity(0.35) : Theme.panel)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(
                                                    avatar == emoji ? Color(hex: color) : .clear,
                                                    lineWidth: 2
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    VStack(spacing: 10) {
                        Text("PICK YOUR COLOR")
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.45))
                        HStack(spacing: 12) {
                            ForEach(Theme.colors, id: \.self) { hex in
                                Button {
                                    color = hex
                                    Haptics.tick()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle().strokeBorder(.white, lineWidth: color == hex ? 3 : 0)
                                        )
                                        .neonGlow(Color(hex: hex), radius: color == hex ? 8 : 0)
                                }
                            }
                        }
                    }

                    Button {
                        submit()
                    } label: {
                        if client.connection == .connecting {
                            ProgressView().tint(.white)
                        } else {
                            Text(isHost ? "CREATE PARTY  🚀" : "JUMP IN  🎉")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(color: isHost ? Theme.pink : Theme.cyan,
                                                 textColor: isHost ? .white : Theme.bg))
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    .padding(.horizontal, 24)

                    if case .failed(let why) = client.connection {
                        Text(why)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.red)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.large])
        .onChange(of: client.room != nil) { _, joined in
            if joined { dismiss() }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if isHost {
            client.createRoom(name: trimmed, avatar: avatar, color: color)
        } else {
            client.joinRoom(code: code, name: trimmed, avatar: avatar, color: color)
        }
    }
}
