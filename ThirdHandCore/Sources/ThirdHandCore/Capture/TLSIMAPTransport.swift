import Foundation

#if canImport(Network)
import Network
import Security

/// The real transport: an IMAPS connection over `Network.framework`.
///
/// TLS from the first byte (implicit TLS on port 993), hostname verified against the
/// certificate, minimum TLS 1.2 -- and no fallback. There is deliberately no
/// plaintext-then-`STARTTLS` path: a downgrade an attacker can trigger by stripping a
/// capability line is exactly the failure a password-bearing connection must not have,
/// so a server that cannot do implicit TLS is simply unsupported.
///
/// **What this file is and is not.** It is the socket plumbing plus `IMAPSession`'s
/// four primitives (read a line, read n literal bytes, send, close). It contains no
/// protocol knowledge -- no tags, no commands, no parsing. That split is what lets
/// every rule above it be tested against `FakeIMAPTransport` without a network.
///
/// **Verified against a real server, but not a real mailbox.** The handshake, the
/// greeting, line framing over a live socket and host-name verification are covered by
/// `TLSIMAPTransportLiveTests`, which talk to `imap.gmail.com` when
/// `THIRDHAND_LIVE_IMAP=1` is set. They are skipped by default so CI needs no network.
///
/// What remains unproven is everything past authentication: `LOGIN`, `SELECT`,
/// `SEARCH UNSEEN` and the `FETCH` of a real message. That needs an actual mailbox and
/// is recorded in the verification section of `docs/DEFERRED-SOURCES.md`.
public struct TLSIMAPTransport: IMAPTransport {
    /// How long a pass may spend establishing the connection, and how long one
    /// command's response may take. A capture pass that hangs is worse than one that
    /// reports a timeout, because the board would stay on yesterday's data with no
    /// error to show.
    public struct Timeouts: Sendable, Hashable {
        public var connect: TimeInterval
        public var command: TimeInterval

        public init(connect: TimeInterval = 15, command: TimeInterval = 20) {
            self.connect = connect
            self.command = command
        }

        public static let `default` = Timeouts()
    }

    private let timeouts: Timeouts

    public init(timeouts: Timeouts = .default) {
        self.timeouts = timeouts
    }

    /// Connects, performs the TLS handshake and consumes the server greeting.
    ///
    /// The greeting is consumed here rather than by `IMAPConversation` so the client's
    /// first command always meets a predictable stream; a server that answers
    /// `* BYE` (too many connections, IP blocked) fails here with the server's own
    /// words rather than as a generic timeout later.
    public func open(account: EmailAccount) async throws -> any IMAPSession {
        guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: account.port) ?? 993) else {
            throw IMAPError.connectionFailed("\(account.port) is not a usable port")
        }
        // `NWEndpoint.Host(name:)` (not a literal IP parse) so the endpoint's host is
        // what TLS validates and what SNI carries: passing a String that happens to be
        // an IP still verifies against that IP's SAN.
        let connection = NWConnection(
            host: NWEndpoint.Host(account.host),
            port: port,
            using: Self.parameters()
        )

        do {
            try await Self.start(connection, timeout: timeouts.connect)
            let session = NWIMAPSession(connection: connection, commandTimeout: timeouts.command)
            let greeting = try await session.readGreeting(timeout: timeouts.connect)
            guard greeting.uppercased().hasPrefix("* OK") || greeting.uppercased().hasPrefix("* PREAUTH") else {
                await session.close()
                throw IMAPError.connectionFailed("server refused the connection: \(greeting)")
            }
            return session
        } catch {
            connection.cancel()
            throw error
        }
    }

    /// Implicit TLS, 1.2 floor, hostname verification on, no local-network or
    /// cellular-specific behaviour.
    static func parameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        if let secOptions = tls.securityProtocolOptions as sec_protocol_options_t? {
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)
            // Default is already true; stated explicitly because "verify the server"
            // is the single most important line in this file.
            sec_protocol_options_set_peer_authentication_required(secOptions, true)
        }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    /// Waits for the connection to become ready, or fails.
    static func start(_ connection: NWConnection, timeout: TimeInterval) async throws {
        try await withTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // `stateUpdateHandler` fires on a Network-internal queue and can fire
                // more than once (ready, then failed on a later read error), so the
                // continuation is guarded against a double resume.
                let box = ResumeOnce(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        box.resume(returning: ())
                    case .failed(let error):
                        box.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    case .waiting(let error):
                        // `.waiting` means no route or a TLS problem that may or may not
                        // resolve; report it immediately rather than sit in a state the
                        // user cannot see.
                        box.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        box.resume(throwing: IMAPError.connectionClosed)
                    case .setup, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: NWIMAPSession.queue)
            }
        }
    }

    /// Races `operation` against a sleep. The operation's own cancellation is the
    /// caller's job (`withTaskCancellationHandler` where it matters); for a connect and
    /// a command read, cancelling the child is enough to abandon it.
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw IMAPError.connectionFailed("timed out after \(Int(seconds))s")
            }
            guard let first = try await group.next() else {
                throw IMAPError.connectionFailed("no result")
            }
            group.cancelAll()
            return first
        }
    }
}

/// A `CheckedContinuation` that tolerates a second resume. `NWConnection`'s state
/// handler can report `.failed` after `.ready` already resumed, and a double resume is
/// a crash, not a warning.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}

/// One `NWConnection` speaking `IMAPSession`.
///
/// A `final class` holding a byte buffer rather than an `actor` because `readLine`
/// must be able to serve a line that is already buffered without an `await` hop, and
/// because IMAP is strictly request/response: `IMAPConversation` drives it from one
/// task, so the lock only exists to satisfy `Sendable`.
final class NWIMAPSession: IMAPSession, @unchecked Sendable {
    /// One serial queue for every connection in the process. `NWConnection` only uses
    /// it to schedule its own callbacks; no user code runs there.
    static let queue = DispatchQueue(label: "com.steveafrost.thirdhand.imap", qos: .utility)

    private static let crlf = Data([0x0D, 0x0A])

    private let connection: NWConnection
    private let commandTimeout: TimeInterval
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false

    init(connection: NWConnection, commandTimeout: TimeInterval) {
        self.connection = connection
        self.commandTimeout = commandTimeout
    }

    /// Reads and returns the greeting line.
    func readGreeting(timeout: TimeInterval) async throws -> String {
        try await TLSIMAPTransport.withTimeout(seconds: timeout) { [self] in
            guard let line = try await readLine() else { throw IMAPError.connectionClosed }
            return line
        }
    }

    func readLine() async throws -> String? {
        while true {
            if let line = takeBufferedLine() { return line }
            try await fill()
        }
    }

    func readLiteral(count: Int) async throws -> String {
        // A literal can follow a line that left bytes in the buffer, and can itself span
        // several TCP segments.
        while lock.withLock({ buffer.count }) < count {
            try await fill()
        }
        let bytes: Data = lock.withLock {
            let slice = buffer.prefix(count)
            buffer.removeFirst(count)
            return Data(slice)
        }
        // Lossy on purpose: a header is ASCII or an RFC 2047 encoded word, so an
        // invalid UTF-8 byte is a non-conforming sender, not a reason to drop the mail.
        return String(decoding: bytes, as: UTF8.self)
    }

    func send(_ line: String) async throws {
        var payload = Data(line.utf8)
        payload.append(Self.crlf)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func close() async {
        let alreadyClosed = lock.withLock { () -> Bool in
            let was = closed
            closed = true
            buffer.removeAll()
            return was
        }
        guard !alreadyClosed else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    /// The next CRLF-terminated line, without its CRLF, if the buffer holds one.
    private func takeBufferedLine() -> String? {
        lock.withLock {
            guard let range = buffer.firstRange(of: Self.crlf) else { return nil }
            let lineData = buffer[buffer.startIndex..<range.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            // Strip a stray CR is not needed (CRLF is the terminator) but a lone LF from
            // a sloppy server is: it is inside `lineData` only if the server wrote one,
            // and IMAP permits bare LF in practice.
            var text = String(decoding: Data(lineData), as: UTF8.self)
            while text.hasSuffix("\r") { text.removeLast() }
            return text
        }
    }

    /// One `receive`, appended to the buffer. `nil` data with `isComplete` is the
    /// server hanging up, which is `connectionClosed`.
    private func fill() async throws {
        let chunk: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: IMAPError.connectionClosed)
                    return
                }
                // No data, not complete: an empty keep-alive read. Hand back nothing and
                // let the caller loop.
                continuation.resume(returning: Data())
            }
        }
        guard !chunk.isEmpty else {
            // Avoid a busy loop on a keep-alive that delivered no bytes.
            try await Task.sleep(nanoseconds: 20_000_000)
            return
        }
        lock.withLock { buffer.append(chunk) }
    }
}
#endif
