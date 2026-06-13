import Foundation
import Network

/// Hosts a Frantics party **on this phone**: a WebSocket server (Network
/// framework) that advertises itself over Bonjour (`_frantics._tcp`) so other
/// phones on the same WiFi auto-discover and join. Incoming frames are handed to
/// the embedded `FranticsEngine`; the engine's replies are written back out.
final class LANServer {
    /// Fired with the bound port once the listener is ready.
    var onReady: ((UInt16) -> Void)?
    var onError: ((String) -> Void)?

    private let engine = FranticsEngine()
    private let queue = DispatchQueue(label: "com.frantics.lanserver")
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]

    func start(serviceName: String) {
        engine.onSend = { [weak self] connId, text in self?.send(connId, text) }
        engine.onClose = { [weak self] connId in self?.cancelConnection(connId) }
        engine.start()

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            // Port 0 → the system picks a free port; Bonjour advertises whichever
            // it lands on, so clients never need to know it.
            let listener = try NWListener(using: params)
            self.listener = listener
            listener.service = NWListener.Service(name: serviceName, type: "_frantics._tcp")

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.onReady?(listener.port?.rawValue ?? 0)
                case .failed(let error):
                    self?.onError?(error.localizedDescription)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for conn in self.connections.values { conn.cancel() }
            self.connections.removeAll()
            self.engine.stop()
        }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let connId = UUID().uuidString
        connections[connId] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.engine.open(connId)
                self?.receive(connId, conn)
            case .failed, .cancelled:
                self?.handleClosed(connId)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receive(_ connId: String, _ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let data, !data.isEmpty,
               let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                   as? NWProtocolWebSocket.Metadata,
               meta.opcode == .text || meta.opcode == .binary,
               let text = String(data: data, encoding: .utf8) {
                self.engine.message(connId, text)
            }
            if error == nil {
                self.receive(connId, conn) // keep reading the next frame
            } else {
                self.handleClosed(connId)
            }
        }
    }

    private func send(_ connId: String, _ text: String) {
        queue.async { [weak self] in
            guard let conn = self?.connections[connId], let data = text.data(using: .utf8) else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "text", metadata: [meta])
            conn.send(content: data, contentContext: context, isComplete: true,
                      completion: .contentProcessed { _ in })
        }
    }

    private func cancelConnection(_ connId: String) {
        queue.async { [weak self] in self?.connections[connId]?.cancel() }
    }

    private func handleClosed(_ connId: String) {
        guard connections.removeValue(forKey: connId) != nil else { return }
        engine.close(connId)
    }
}
