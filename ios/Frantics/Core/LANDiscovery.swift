import Foundation
import Network

/// Finds the Frantics game server on the local WiFi via Bonjour (`_frantics._tcp`)
/// and resolves it to a concrete `ws://host:port` URL — so "Same WiFi" mode needs
/// no typed-in address. The server advertises the matching service (see server.ts).
@MainActor
final class LANDiscovery {
    enum State: Equatable {
        case idle
        case searching
        case found(String)   // resolved ws:// URL
        case failed(String)
    }

    /// Pushed on every state change (idle/searching/found/failed).
    var onState: ((State) -> Void)?
    /// Fired once with the resolved `ws://host:port` URL when a server is found.
    var onResolved: ((String) -> Void)?

    private(set) var state: State = .idle {
        didSet { onState?(state) }
    }

    private var browser: NWBrowser?
    private var resolver: NWConnection?

    var isRunning: Bool { browser != nil }

    func start() {
        // Already actively browsing — don't churn the browser.
        if browser != nil { return }
        state = .searching

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_frantics._tcp", domain: nil),
            using: params
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            // Pick the first advertised service endpoint and resolve it.
            let service = results.first { result in
                if case .service = result.endpoint { return true }
                return false
            }
            guard let endpoint = service?.endpoint else { return }
            Task { @MainActor in self.resolve(endpoint) }
        }

        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .failed(let error):
                    if case .found = self.state { return } // keep a resolved result
                    self.state = .failed(error.localizedDescription)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolver?.cancel()
        resolver = nil
        if case .found = state {} else { state = .idle }
    }

    /// Bonjour gives us a service endpoint, not an address. Briefly open a
    /// connection to it; once `.ready`, the resolved host:port shows up on the
    /// connection's current path. Read it, build the ws URL, then tear down.
    private func resolve(_ endpoint: NWEndpoint) {
        resolver?.cancel()
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolver = connection

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    let url = "ws://\(Self.hostString(host)):\(port.rawValue)"
                    Task { @MainActor in
                        self.state = .found(url)
                        self.onResolved?(url)
                    }
                }
                connection.cancel()
            case .failed(let error):
                Task { @MainActor in
                    if case .found = self.state { return }
                    self.state = .failed(error.localizedDescription)
                }
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// Render a resolved host for a URL: dotted IPv4 as-is, IPv6 bracketed,
    /// names verbatim — stripping any link-local `%interface` zone suffix.
    nonisolated private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let addr):
            return String("\(addr)".split(separator: "%").first ?? "")
        case .ipv6(let addr):
            let raw = String("\(addr)".split(separator: "%").first ?? "")
            return "[\(raw)]"
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
