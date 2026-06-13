import Foundation
import JavaScriptCore

/// Runs the authoritative Frantics game server **on the host phone**, by loading
/// the bundled `FranticsEngine.js` (the same `room.ts` state machine the Node
/// server uses) into JavaScriptCore. `LANServer` owns the real WebSocket
/// transport and feeds connections in here; outgoing frames come back out via
/// `onSend` / `onClose`.
///
/// Everything touching the `JSContext` runs on a single serial queue — JSC is
/// not thread-safe, and the injected timers fire on that same queue.
final class FranticsEngine {
    /// Called when the engine wants to write a text frame to a connection.
    var onSend: ((_ connId: String, _ text: String) -> Void)?
    /// Called when the engine wants to close a connection.
    var onClose: ((_ connId: String) -> Void)?

    private let queue = DispatchQueue(label: "com.frantics.engine")
    private var context: JSContext?
    private var engine: JSValue?

    // JS timers, driven natively (JSC has no event loop).
    private var timeouts: [Int: DispatchWorkItem] = [:]
    private var intervals: [Int: DispatchSourceTimer] = [:]
    private var nextTimerId = 1

    func start() {
        queue.async { [weak self] in self?.boot() }
    }

    func stop() {
        queue.async { [weak self] in self?.teardown() }
    }

    // MARK: - Connection events (forwarded to the JS engine)

    func open(_ connId: String) {
        queue.async { [weak self] in
            self?.engine?.invokeMethod("open", withArguments: [connId])
        }
    }

    func message(_ connId: String, _ text: String) {
        queue.async { [weak self] in
            self?.engine?.invokeMethod("message", withArguments: [connId, text])
        }
    }

    func close(_ connId: String) {
        queue.async { [weak self] in
            self?.engine?.invokeMethod("close", withArguments: [connId])
        }
    }

    // MARK: - Boot / teardown

    private func boot() {
        guard context == nil else { return }
        guard let ctx = JSContext() else { return }
        context = ctx

        ctx.exceptionHandler = { _, exception in
            print("[engine] JS exception:", exception?.toString() ?? "unknown")
        }

        injectConsole(ctx)
        injectTimers(ctx)
        injectBridge(ctx)

        guard let url = Bundle.main.url(forResource: "FranticsEngine", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            print("[engine] FranticsEngine.js not found in app bundle")
            return
        }
        ctx.evaluateScript(source, withSourceURL: url)
        engine = ctx.objectForKeyedSubscript("FranticsEngine")
        if engine?.isObject != true {
            print("[engine] FranticsEngine global missing after load")
        }
    }

    private func teardown() {
        for work in timeouts.values { work.cancel() }
        for timer in intervals.values { timer.cancel() }
        timeouts.removeAll()
        intervals.removeAll()
        engine = nil
        context = nil
    }

    // MARK: - Injected globals

    private func injectConsole(_ ctx: JSContext) {
        let console = JSValue(newObjectIn: ctx)
        let log: @convention(block) (JSValue) -> Void = { value in
            print("[engine]", value.toString() ?? "")
        }
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        console?.setObject(log, forKeyedSubscript: "warn" as NSString)
        console?.setObject(log, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func injectTimers(_ ctx: JSContext) {
        let setTimeout: @convention(block) (JSValue, Double) -> Int = { [weak self] fn, ms in
            guard let self else { return 0 }
            let id = self.nextTimerId
            self.nextTimerId += 1
            let work = DispatchWorkItem { [weak self] in
                self?.timeouts[id] = nil
                fn.call(withArguments: [])
            }
            self.timeouts[id] = work
            self.queue.asyncAfter(deadline: .now() + max(0, ms) / 1000.0, execute: work)
            return id
        }
        ctx.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)

        let clearTimeout: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timeouts[id]?.cancel()
            self?.timeouts[id] = nil
        }
        ctx.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)

        let setInterval: @convention(block) (JSValue, Double) -> Int = { [weak self] fn, ms in
            guard let self else { return 0 }
            let id = self.nextTimerId
            self.nextTimerId += 1
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let period = max(0.001, ms / 1000.0)
            timer.schedule(deadline: .now() + period, repeating: period)
            timer.setEventHandler { fn.call(withArguments: []) }
            self.intervals[id] = timer
            timer.resume()
            return id
        }
        ctx.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)

        let clearInterval: @convention(block) (Int) -> Void = { [weak self] id in
            self?.intervals[id]?.cancel()
            self?.intervals[id] = nil
        }
        ctx.setObject(clearInterval, forKeyedSubscript: "clearInterval" as NSString)
    }

    private func injectBridge(_ ctx: JSContext) {
        let send: @convention(block) (String, String) -> Void = { [weak self] connId, text in
            self?.onSend?(connId, text)
        }
        ctx.setObject(send, forKeyedSubscript: "__frantics_send" as NSString)

        let close: @convention(block) (String) -> Void = { [weak self] connId in
            self?.onClose?(connId)
        }
        ctx.setObject(close, forKeyedSubscript: "__frantics_close" as NSString)
    }
}
