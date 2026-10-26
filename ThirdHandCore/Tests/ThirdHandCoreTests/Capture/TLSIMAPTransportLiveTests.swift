import Foundation
import Testing
@testable import ThirdHandCore

/// Tests that speak to a real IMAPS server.
///
/// Everything else in this module is verified against `FakeIMAPTransport`, which
/// proves the *protocol* logic but says nothing about the layer below it: the
/// `Network.framework` socket, the TLS handshake, and the byte framing that turns a
/// stream into lines and literals. Those only fail against a real peer.
///
/// They are skipped by default because they need the network, a DNS resolver and a
/// third-party uptime that a build should never depend on. Run them with:
///
///     THIRDHAND_LIVE_IMAP=1 swift test --filter TLSIMAPTransportLiveTests
///
/// Override the peer with `THIRDHAND_LIVE_IMAP_HOST` / `_PORT` if the default host is
/// unreachable from where the tests run.
///
/// **What these still do not prove.** No credentials are used, so `LOGIN`, `SELECT`,
/// `SEARCH UNSEEN` and a real message `FETCH` stay unexercised against a live server.
/// That needs a mailbox and is the remaining gap recorded in `docs/DEFERRED-SOURCES.md`.
@Suite(
    "TLSIMAPTransport against a live server",
    .enabled(if: LiveIMAP.isEnabled)
)
struct TLSIMAPTransportLiveTests {
    @Test("the TLS handshake completes and the server greeting is IMAP")
    func handshakeAndGreeting() async throws {
        let transport = TLSIMAPTransport(timeouts: .init(connect: 30, command: 30))
        // `open` only returns a session if the handshake completed *and* the first
        // line off the socket was `* OK` or `* PREAUTH`, so returning at all is the
        // assertion: TLS verified the certificate against the host name, and enough
        // bytes arrived to complete a line.
        let session = try await transport.open(account: LiveIMAP.account)
        await session.close()
    }

    @Test("a command round-trips over the socket")
    func capabilityRoundTrip() async throws {
        let transport = TLSIMAPTransport(timeouts: .init(connect: 30, command: 30))
        let session = try await transport.open(account: LiveIMAP.account)

        // CAPABILITY is the one useful command that needs no authentication, so it
        // exercises `send` and `readLine` against the live server without a password.
        do {
            try await session.send("A1 CAPABILITY")

            var response: [String] = []
            var sawCompletion = false
            while let line = try await session.readLine() {
                response.append(line)
                // The tagged line ends the response; an untagged `*` line is data.
                if line.hasPrefix("A1 ") {
                    sawCompletion = true
                    break
                }
                if response.count > 100 {
                    break
                }
            }

            #expect(sawCompletion, "the server never closed the CAPABILITY response")
            let joined = response.joined(separator: "\n").uppercased()
            // A tagged IMAP reply proves the framing: a written command reached the
            // server, and line reads came back delimited rather than as one blob.
            #expect(
                joined.contains("IMAP4REV1") || joined.contains("CAPABILITY"),
                "not an IMAP CAPABILITY reply: \(joined.prefix(400))"
            )
            let tagged = response.last ?? ""
            #expect(
                !tagged.uppercased().hasPrefix("A1 BAD"),
                "the server rejected CAPABILITY: \(tagged)"
            )
        } catch {
            await session.close()
            throw error
        }
        await session.close()
    }

    @Test("host-name verification is enforced: an IP endpoint is refused")
    func ipEndpointIsRefused() async throws {
        // The strongest available proof that `sec_protocol_options_set_peer_authentication_required`
        // is doing its job. This address is the server that answers `imap.gmail.com`,
        // and its certificate is valid -- for *that name*. Reaching it by bare IP puts
        // the wrong name in SNI, so the certificate does not match the endpoint.
        //
        // Measured both ways while writing this: with peer authentication on it fails
        // with NWError -9808 (`bad certificate format`); with the check disabled it
        // **opens and returns a session**. So this test genuinely tracks the setting
        // rather than merely observing that some unrelated error occurred.
        //
        // A badssl-style host cannot be used here: those close the connection for
        // reasons unrelated to our TLS options, so a test against them passes even
        // when verification is off.
        let transport = TLSIMAPTransport(timeouts: .init(connect: 15, command: 15))
        let byAddress = EmailAccount(
            host: "172.253.132.108",
            port: LiveIMAP.port,
            username: "probe@example.com"
        )

        var opened = false
        do {
            let session = try await transport.open(account: byAddress)
            opened = true
            await session.close()
        } catch {
            opened = false
        }
        #expect(!opened, "an endpoint whose certificate does not match its name was accepted")
    }

    @Test("close is safe to call twice")
    func closeIsIdempotent() async throws {
        let transport = TLSIMAPTransport(timeouts: .init(connect: 30, command: 30))
        let session = try await transport.open(account: LiveIMAP.account)
        await session.close()
        // A second close must not trap or resume a continuation twice; the board
        // closes a session on both the success and the failure path.
        await session.close()
    }
}

/// Where the live tests point, and whether they run at all.
enum LiveIMAP {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["THIRDHAND_LIVE_IMAP"] == "1"
    }

    static var host: String {
        ProcessInfo.processInfo.environment["THIRDHAND_LIVE_IMAP_HOST"] ?? "imap.gmail.com"
    }

    static var port: Int {
        Int(ProcessInfo.processInfo.environment["THIRDHAND_LIVE_IMAP_PORT"] ?? "") ?? 993
    }

    /// No password: these tests stop at the first command that needs one.
    static var account: EmailAccount {
        EmailAccount(host: host, port: port, username: "live-test@example.com")
    }
}
