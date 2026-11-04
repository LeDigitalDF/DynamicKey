// LocalAuthHTTPServer.swift
// Loopback TCP listener that serves the extension auth HTTP API (M5).
//
// Flow: NWListener on 127.0.0.1 → parse HTTP → handler → write response → close.

import Foundation
import Network

enum LocalAuthHTTPServerError: Error, LocalizedError {
    case alreadyRunning
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Local auth server is already running."
        case .listenerFailed(let detail):
            return "Could not start local auth server: \(detail)"
        }
    }
}

final class LocalAuthHTTPServer {
    private let port: UInt16
    private let handler = LocalAuthRequestHandler()
    private let queue = DispatchQueue(label: "LeDigital.KeyStrokeAuth.localauth.server", qos: .userInitiated)

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16 = ExtensionAuthConfig.port) {
        self.port = port
    }

    /// Binds to loopback and begins accepting extension connections.
    func start() throws {
        guard listener == nil else { throw LocalAuthHTTPServerError.alreadyRunning }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LocalAuthHTTPServerError.listenerFailed("Invalid port \(port).")
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("KeyStrokeAuth local auth listener failed: \(error.localizedDescription)")
            }
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stops accepting connections and cancels active sockets.
    func stop() {
        queue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            listener?.cancel()
            listener = nil
        }
    }

    /// Registers a new client connection and begins reading its HTTP request.
    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.removeConnection(id)
            }
            if case .cancelled = state {
                self?.removeConnection(id)
            }
        }

        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    /// Accumulates bytes until a full HTTP request is available, then responds.
    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("KeyStrokeAuth local auth receive error: \(error.localizedDescription)")
                connection.cancel()
                self.removeConnection(ObjectIdentifier(connection))
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if let request = LocalHTTPParser.parseRequest(from: buffer) {
                let response = self.handler.handle(request)
                self.send(response: response, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                self.removeConnection(ObjectIdentifier(connection))
                return
            }

            self.receive(on: connection, accumulated: buffer)
        }
    }

    /// Writes the HTTP response and closes the connection.
    private func send(response: LocalHTTPResponse, on connection: NWConnection) {
        let payload = response.serialize()
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
            self.removeConnection(ObjectIdentifier(connection))
        })
    }

    /// Drops a finished connection from the active set.
    private func removeConnection(_ id: ObjectIdentifier) {
        queue.async {
            self.connections.removeValue(forKey: id)
        }
    }
}
