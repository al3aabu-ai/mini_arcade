import SwiftUI

struct MenuView: View {
    @EnvironmentObject var client: GameClient
    @State private var path: Destination?
    @State private var showSettings = false

    enum Destination: Identifiable {
        case host, join
        var id: Int { self == .host ? 0 : 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(12)
                }
            }

            Spacer()

            Text("🎉")
                .font(.system(size: 64))
            Text("FRANTICS")
                .font(Theme.title(56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.pink, Theme.purple, Theme.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .neonGlow(Theme.purple, radius: 18)
            Text("Phones in hand. Chaos on the TV.")
                .font(Theme.body(16))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 14) {
                Button("📺  HOST PARTY") { path = .host }
                    .buttonStyle(NeonButtonStyle(color: Theme.pink))
                Button("🎮  JOIN PARTY") { path = .join }
                    .buttonStyle(NeonButtonStyle(color: Theme.cyan, textColor: Theme.bg))
            }
            .padding(.horizontal, 28)

            Text("Host: AirPlay-mirror your iPhone to the TV.\nThe game board appears on the big screen.")
                .font(Theme.body(13))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .padding(.bottom, 30)
        }
        .sheet(item: $path) { dest in
            ProfileSetupView(isHost: dest == .host)
                .environmentObject(client)
        }
        .sheet(isPresented: $showSettings) {
            ServerSettingsView().environmentObject(client)
        }
    }
}

struct ServerSettingsView: View {
    @EnvironmentObject var client: GameClient
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Game server address")
                        .font(Theme.body(16))
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("ws://192.168.1.50:8080", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 17, design: .monospaced))
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .foregroundStyle(Theme.cyan)
                    Text("Same WiFi: run `npm run dev` in server/ and use the LAN address it prints.\nOver the internet: use your deployed wss:// address.")
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        client.serverURLString = urlText
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear { urlText = client.serverURLString }
        .presentationDetents([.medium])
    }
}
