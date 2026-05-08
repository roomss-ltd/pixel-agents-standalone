import Foundation
import Network

final class HookSocketListener {
    private var listener: NWListener?
    private let socketPath: String
    private let queue = DispatchQueue(label: "agenttab.hooks")

    var onPayload: ((HookPayload) -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        listener = try NWListener(using: parameters)
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let data = data, !data.isEmpty else { return }
            do {
                let payload = try JSONDecoder().decode(HookPayload.self, from: data)
                self?.onPayload?(payload)
            } catch {
                print("[HookSocket] Decode error: \(error)")
            }
        }
    }
}
