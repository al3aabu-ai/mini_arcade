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
                Button("📺  HOST PARTY") {
                    if client.connectionMode == .lan { client.startHosting() }
                    path = .host
                }
                .buttonStyle(NeonButtonStyle(color: Theme.pink))
                Button("🎮  JOIN PARTY") {
                    if client.connectionMode == .lan { client.startLANDiscovery() }
                    path = .join
                }
                .buttonStyle(NeonButtonStyle(color: Theme.cyan, textColor: Theme.bg))
            }
            .padding(.horizontal, 28)

            ConnectionModePicker()
                .environmentObject(client)
                .padding(.horizontal, 24)
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

/// Home-screen "Same WiFi vs. Other" chooser. LAN mode auto-discovers the server
/// on the local network (no address to type); Other mode reveals a ws:// field.
struct ConnectionModePicker: View {
    @EnvironmentObject var client: GameClient
    @State private var urlText = ""

    var body: some View {
        VStack(spacing: 12) {
            Picker("Connection", selection: modeBinding) {
                Text("📶  Same WiFi").tag(ConnectionMode.lan)
                Text("🌐  Other").tag(ConnectionMode.other)
            }
            .pickerStyle(.segmented)

            switch client.connectionMode {
            case .lan:
                Text("One phone hosts on this WiFi — tap HOST PARTY. Everyone else on the same WiFi taps JOIN and is found automatically.")
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            case .other:
                otherFields
            }
        }
        .onAppear { urlText = client.serverURLString }
        .onChange(of: client.connectionMode) { _, mode in
            if mode == .other { urlText = client.serverURLString }
        }
    }

    private var modeBinding: Binding<ConnectionMode> {
        Binding(
            get: { client.connectionMode },
            set: { client.connectionMode = $0 }
        )
    }

    @ViewBuilder
    private var otherFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("wss://your-server.com", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 15, design: .monospaced))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                .foregroundStyle(Theme.cyan)
                .onChange(of: urlText) { _, value in
                    client.serverURLString = value
                }
            Text("Use a deployed wss:// address to play over the internet.")
                .font(Theme.body(12))
                .foregroundStyle(.white.opacity(0.4))
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
