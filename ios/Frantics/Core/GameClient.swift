import Foundation
import Combine

enum ConnectionPhase: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

/// How the app reaches the game server.
/// - `lan`: auto-discover a server on the same WiFi via Bonjour (no address typed).
/// - `other`: connect to a manually entered address (deployed server / internet).
enum ConnectionMode: String {
    case lan
    case other
}

/// Single source of client truth, shared by the phone scene and the
/// external-display (TV board) scene. The server remains authoritative;
/// this object just mirrors the latest `room_state` snapshot and relays input.
@MainActor
final class GameClient: NSObject, ObservableObject {
    static let shared = GameClient()

    @Published var connection: ConnectionPhase = .idle
    @Published var room: RoomState?
    @Published var playerId: String = ""
    @Published var lastError: String?
    @Published var boardDisplayConnected = false
    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: "serverURL") }
    }

    /// LAN auto-discovery vs. a manually typed address.
    @Published var connectionMode: ConnectionMode {
        didSet {
            UserDefaults.standard.set(connectionMode.rawValue, forKey: "connectionMode")
            if connectionMode == .lan { startLANDiscovery() } else { stopLANDiscovery() }
        }
    }

    /// Mirrors `LANDiscovery`'s progress for the UI (searching / found / failed).
    @Published var lanState: LANDiscovery.State = .idle

    /// Whether this phone is currently hosting the game for the WiFi.
    enum HostingState: Equatable {
        case off
        case starting
        case ready
        case failed(String)
    }
    @Published var hostingState: HostingState = .off

    private let lanDiscovery = LANDiscovery()
    private var lanServer: LANServer?
    /// The ws:// URL most recently resolved on the WiFi, if any.
    private(set) var discoveredURL: String?

    // Realtime relays for the host board's physics scene (golf).
    var onAim: ((String, Double, Double) -> Void)?
    var onAimClear: ((String) -> Void)?
    var onFire: ((String, Double, Double) -> Void)?
    /// Bumper: a player's joystick vector, relayed to the host board.
    var onJoystick: ((String, Double, Double) -> Void)?

    let isDemo: Bool
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var token = ""
    private var roomCode = ""
    private var introMessage: [String: Any]?
    private var reconnectAttempts = 0
    private var errorToastTask: Task<Void, Never>?

    override init() {
        self.isDemo = false
        self.serverURLString =
            UserDefaults.standard.string(forKey: "serverURL") ?? "ws://localhost:8080"
        // Default new installs to LAN auto-discovery — the zero-setup path.
        let savedMode = UserDefaults.standard.string(forKey: "connectionMode")
        self.connectionMode = savedMode.flatMap(ConnectionMode.init) ?? .lan
        super.init()

        lanDiscovery.onState = { [weak self] state in
            self?.lanState = state
        }
        lanDiscovery.onResolved = { [weak self] url in
            guard let self else { return }
            self.discoveredURL = url
            // In LAN mode the discovered server is the one we connect to.
            if self.connectionMode == .lan { self.serverURLString = url }
        }
    }

    // MARK: - LAN discovery

    /// Begin (or resume) browsing the WiFi for a Frantics server.
    func startLANDiscovery() {
        guard !isDemo else { return }
        lanDiscovery.start()
    }

    func stopLANDiscovery() {
        lanDiscovery.stop()
    }

    // MARK: - Hosting (this phone runs the game for the WiFi)

    /// Boot the on-device game server and advertise it on the WiFi. Once ready,
    /// the host's own controller connects to it over loopback.
    func startHosting() {
        guard !isDemo, lanServer == nil else { return }
        hostingState = .starting
        let server = LANServer()
        lanServer = server
        server.onReady = { [weak self] port in
            Task { @MainActor in
                guard let self else { return }
                self.serverURLString = "ws://127.0.0.1:\(port)"
                self.hostingState = .ready
            }
        }
        server.onError = { [weak self] message in
            Task { @MainActor in self?.hostingState = .failed(message) }
        }
        server.start(serviceName: "Frantics")
    }

    func stopHosting() {
        lanServer?.stop()
        lanServer = nil
        hostingState = .off
    }

    var isHostingReady: Bool { hostingState == .ready }

    /// DEBUG screenshots / previews: a frozen client with a canned snapshot.
    init(demoState: RoomState, playerId: String) {
        self.isDemo = true
        self.serverURLString = "demo"
        self.connectionMode = .other
        super.init()
        self.room = demoState
        self.playerId = playerId
        self.connection = .connected
    }

    var me: PlayerState? { room?.player(playerId) }
    var isHost: Bool { me?.isHost ?? false }

    // MARK: - Connection

    private func resolvedURL() -> URL? {
        var raw = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("http://") { raw = "ws://" + raw.dropFirst(7) }
        if raw.hasPrefix("https://") { raw = "wss://" + raw.dropFirst(8) }
        if !raw.hasPrefix("ws://") && !raw.hasPrefix("wss://") { raw = "ws://" + raw }
        return URL(string: raw)
    }

    func createRoom(name: String, avatar: String, color: String) {
        connect(intro: ["t": "create_room", "name": name, "avatar": avatar, "color": color])
    }

    func joinRoom(code: String, name: String, avatar: String, color: String) {
        connect(intro: [
            "t": "join_room",
            "code": code.uppercased(),
            "name": name,
            "avatar": avatar,
            "color": color,
        ])
    }

    private func connect(intro: [String: Any]) {
        guard !isDemo else { return }
        // In LAN mode, a host connects to its own on-device server (over
        // loopback, once it's ready); a joiner needs a discovered server.
        if connectionMode == .lan, !isHostingReady, discoveredURL == nil {
            startLANDiscovery()
            connection = .failed("Still looking for a game on this WiFi…")
            return
        }
        guard let url = resolvedURL() else {
            connection = .failed("Invalid server address")
            return
        }
        introMessage = intro
        connection = .connecting
        task?.cancel(with: .goingAway, reason: nil)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        listen(on: task)
    }

    func leaveRoom() {
        send(["t": "leave"])
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        room = nil
        playerId = ""
        token = ""
        roomCode = ""
        introMessage = nil
        reconnectAttempts = 0
        connection = .idle
        // If we were hosting the party on this phone, shut the server down.
        stopHosting()
    }

    private func handleDrop(_ reason: String) {
        guard !isDemo else { return }
        guard task != nil else { return }
        task = nil
        // If we were seated in a room, quietly try to reclaim the seat.
        if !roomCode.isEmpty, !playerId.isEmpty, reconnectAttempts < 5 {
            reconnectAttempts += 1
            connection = .connecting
            let rejoin: [String: Any] = [
                "t": "rejoin", "code": roomCode, "playerId": playerId, "token": token,
            ]
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.connect(intro: rejoin)
            }
        } else if room != nil || connection == .connecting {
            connection = .failed(reason)
        }
    }

    // MARK: - Receive

    private func listen(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return }
                switch result {
                case .failure(let error):
                    self.handleDrop(error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text: text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text: text) }
                    @unknown default: break
                    }
                    self.listen(on: task)
                }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return }
        switch envelope.t {
        case "room_joined":
            if let msg = try? decoder.decode(RoomJoinedMsg.self, from: data) {
                playerId = msg.playerId
                token = msg.token
                roomCode = msg.state.code
                room = msg.state
                connection = .connected
                reconnectAttempts = 0
            }
        case "room_state":
            if let msg = try? decoder.decode(RoomStateMsg.self, from: data) {
                if let current = room, current.rev > msg.state.rev { return } // stale
                room = msg.state
            }
        case "aim":
            if let msg = try? decoder.decode(AimMsg.self, from: data) {
                onAim?(msg.playerId, msg.angle, msg.power)
            }
        case "aim_clear":
            if let msg = try? decoder.decode(AimClearMsg.self, from: data) {
                onAimClear?(msg.playerId)
            }
        case "fire":
            if let msg = try? decoder.decode(FireMsg.self, from: data) {
                onFire?(msg.playerId, msg.angle, msg.power)
            }
        case "joystick":
            if let msg = try? decoder.decode(JoystickMsg.self, from: data) {
                onJoystick?(msg.playerId, msg.x, msg.y)
            }
        case "error":
            if let msg = try? decoder.decode(ErrorMsg.self, from: data) {
                showError(msg.message)
                if connection == .connecting { connection = .failed(msg.message) }
            }
        default:
            break
        }
    }

    private func showError(_ message: String) {
        lastError = message
        errorToastTask?.cancel()
        errorToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self?.lastError = nil }
        }
    }

    // MARK: - Send

    private func send(_ payload: [String: Any]) {
        guard !isDemo, let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    func startGame() { send(["t": "start_game"]) }
    /// Host live-updates the in-progress picks so the TV mirrors the slots.
    func previewLineup(_ lineup: [String]) { send(["t": "preview_lineup", "lineup": lineup]) }
    /// Host commits the chosen games (must be exactly the required count) → starts.
    func selectLineup(_ lineup: [String]) { send(["t": "select_lineup", "lineup": lineup]) }
    func submitBid(_ amount: Int) { send(["t": "submit_bid", "amount": amount]) }
    func chooseTarget(_ targetId: String) { send(["t": "choose_target", "targetId": targetId]) }
    func sendAim(angle: Double, power: Double) { send(["t": "aim", "angle": angle, "power": power]) }
    func sendAimClear() { send(["t": "aim_clear"]) }
    func fire(angle: Double, power: Double) { send(["t": "fire", "angle": angle, "power": power]) }
    func golfFinished(order: [String]) { send(["t": "golf_finished", "order": order]) }
    func golfProgress(turnId: String?, sunk: [String]) {
        send(["t": "golf_progress", "turnId": turnId ?? NSNull(), "sunk": sunk])
    }
    func passBomb(direction: String) { send(["t": "pass_bomb", "direction": direction]) }
    func voteReplay() { send(["t": "replay"]) }

    // MARK: bumper
    /// Stream the player's normalized joystick vector (bumper movement).
    func updateJoystick(x: Double, y: Double) { send(["t": "update_joystick", "x": x, "y": y]) }
    /// Host board reports a player splashed off the slab (and who shoved them).
    func reportBumperKnockout(playerId: String, byPlayerId: String?) {
        send(["t": "bumper_knockout", "playerId": playerId, "byPlayerId": byPlayerId ?? NSNull()])
    }

    // MARK: coins (host board only)
    /// Register the loose coins the board placed on this golf round's course.
    func registerCoins(_ coins: [GolfCoinSpawn]) {
        send(["t": "register_coins", "coins": coins.map { ["id": $0.id, "x": $0.x, "y": $0.y, "z": $0.z] }])
    }
    /// Report that `playerId`'s ball ran into a coin → server credits +COIN_VALUE.
    func collectCoin(coinId: String, playerId: String) {
        send(["t": "collect_coin", "coinId": coinId, "playerId": playerId])
    }
    /// Report that `playerId`'s ball fell in water / reset (fails the Safe Play task).
    func reportBallReset(playerId: String) {
        send(["t": "ball_reset", "playerId": playerId])
    }
}

/// A coin the board placed, sent to the server so it owns coin existence/credit.
struct GolfCoinSpawn {
    let id: String
    let x: Double
    let y: Double
    let z: Double
}

extension GameClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.task === webSocketTask else { return }
            if let intro = self.introMessage {
                self.send(intro)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.task === webSocketTask else { return }
            self.handleDrop("Connection closed")
        }
    }
}
