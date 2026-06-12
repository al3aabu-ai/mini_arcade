import Foundation
import Combine

enum ConnectionPhase: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
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

    // Realtime relays for the host board's physics scene (golf).
    var onAim: ((String, Double, Double) -> Void)?
    var onAimClear: ((String) -> Void)?
    var onFire: ((String, Double, Double) -> Void)?

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
        super.init()
    }

    /// DEBUG screenshots / previews: a frozen client with a canned snapshot.
    init(demoState: RoomState, playerId: String) {
        self.isDemo = true
        self.serverURLString = "demo"
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
