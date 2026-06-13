import SwiftUI

struct MenuView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @State private var path: Destination?
    @State private var showSettings = false

    enum Destination: Identifiable {
        case host, join
        var id: Int { self == .host ? 0 : 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Language toggle: flips the whole app between English and Arabic.
                Button {
                    loc.toggle()
                    Haptics.tick()
                } label: {
                    Text(loc.isArabic ? "EN" : "ع")
                        .font(Theme.title(18))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.panel))
                        .padding(.leading, 12)
                }
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
            Text(loc.tr("Phones in hand. Chaos on the TV."))
                .font(Theme.body(16))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 14) {
                Button(loc.tr("📺  HOST PARTY")) {
                    if client.connectionMode == .lan { client.startHosting() }
                    path = .host
                }
                .buttonStyle(NeonButtonStyle(color: Theme.pink))
                Button(loc.tr("🎮  JOIN PARTY")) {
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
    @ObservedObject private var loc = Localization.shared
    @State private var urlText = ""

    var body: some View {
        VStack(spacing: 12) {
            Picker(loc.tr("Connection"), selection: modeBinding) {
                Text(loc.tr("📶  Same WiFi")).tag(ConnectionMode.lan)
                Text(loc.tr("🌐  Other")).tag(ConnectionMode.other)
            }
            .pickerStyle(.segmented)

            switch client.connectionMode {
            case .lan:
                Text(loc.tr("One phone hosts on this WiFi — tap HOST PARTY. Everyone else on the same WiFi taps JOIN and is found automatically."))
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
            Text(loc.tr("Use a deployed wss:// address to play over the internet."))
                .font(Theme.body(12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct ServerSettingsView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text(loc.tr("Game server address"))
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
                    Text(loc.tr("Same WiFi: run `npm run dev` in server/ and use the LAN address it prints.\nOver the internet: use your deployed wss:// address."))
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(loc.tr("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.tr("Save")) {
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
