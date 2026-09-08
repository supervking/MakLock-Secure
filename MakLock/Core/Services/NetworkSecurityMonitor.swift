import Foundation
import Network

final class NetworkSecurityMonitor {
    static let shared = NetworkSecurityMonitor()

    var onNetworkLoss: (() -> Void)?

    private let queue = DispatchQueue(label: "com.makmak.MakLock.network-security", qos: .utility)
    private let probeEndpoints: [(host: NWEndpoint.Host, port: NWEndpoint.Port)] = [
        ("1.1.1.1", 443),
        ("8.8.8.8", 443),
        ("9.9.9.9", 443)
    ]

    private var pathMonitor: NWPathMonitor?
    private var probeTimer: DispatchSourceTimer?
    private var outageTracker = NetworkOutageTracker()
    private var pathIsSatisfied = false
    private var probeInFlight = false
    private var generation = 0

    private init() {}

    func reloadSettings() {
        if Defaults.shared.lockOnNetworkLoss {
            start()
        } else {
            stop()
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.pathMonitor == nil else { return }

            self.generation += 1
            let generation = self.generation
            self.outageTracker.reset()

            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self, generation == self.generation else { return }
                self.pathIsSatisfied = path.status == .satisfied
                if self.pathIsSatisfied {
                    self.runConnectivityProbe(generation: generation)
                } else {
                    self.recordConnectivity(isOnline: false)
                }
            }
            monitor.start(queue: self.queue)
            self.pathMonitor = monitor

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 10)
            timer.setEventHandler { [weak self] in
                guard let self, generation == self.generation else { return }
                if self.pathIsSatisfied {
                    self.runConnectivityProbe(generation: generation)
                } else {
                    self.recordConnectivity(isOnline: false)
                }
            }
            timer.resume()
            self.probeTimer = timer

            NSLog("[MakLock] Network security monitor started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.pathMonitor?.cancel()
            self.pathMonitor = nil
            self.probeTimer?.cancel()
            self.probeTimer = nil
            self.probeInFlight = false
            self.pathIsSatisfied = false
            self.outageTracker.reset()
            NSLog("[MakLock] Network security monitor stopped")
        }
    }

    private func runConnectivityProbe(generation: Int) {
        guard generation == self.generation,
              Defaults.shared.lockOnNetworkLoss,
              pathIsSatisfied,
              !probeInFlight else {
            return
        }

        probeInFlight = true
        var remaining = probeEndpoints.count
        var anyEndpointOnline = false

        for endpoint in probeEndpoints {
            probe(endpoint: endpoint) { [weak self] isOnline in
                guard let self, generation == self.generation else { return }
                anyEndpointOnline = anyEndpointOnline || isOnline
                remaining -= 1

                guard remaining == 0 else { return }
                self.probeInFlight = false
                self.recordConnectivity(isOnline: self.pathIsSatisfied && anyEndpointOnline)
            }
        }
    }

    private func probe(
        endpoint: (host: NWEndpoint.Host, port: NWEndpoint.Port),
        completion: @escaping (Bool) -> Void
    ) {
        let connection = NWConnection(host: endpoint.host, port: endpoint.port, using: .tcp)
        var completed = false

        let finish: (Bool) -> Void = { isOnline in
            guard !completed else { return }
            completed = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            completion(isOnline)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }

        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 4) {
            finish(false)
        }
    }

    private func recordConnectivity(isOnline: Bool) {
        guard Defaults.shared.lockOnNetworkLoss else {
            outageTracker.reset()
            return
        }

        let shouldLock = outageTracker.observe(
            isOnline: isOnline,
            now: ProcessInfo.processInfo.systemUptime,
            graceSeconds: TimeInterval(Defaults.shared.networkLossGraceSeconds)
        )

        guard shouldLock else { return }
        NSLog("[MakLock] Network unavailable beyond configured grace period")
        DispatchQueue.main.async { [weak self] in
            self?.onNetworkLoss?()
        }
    }
}
