import Foundation
@testable import PulseCore

/// Shared fixtures for the sync suites: an isolated directory container that the
/// test tears down, and the small item/command builders every case needs.
enum SyncFixture {
    static func makeContainer() throws -> LocalContainer {
        try LocalContainer.make()
    }

    /// An item with a known `updatedAt`, so the stale-command rule can be tested
    /// to the millisecond.
    static func item(
        id: String,
        status: Status = .open,
        updatedAt: Date,
        resolvedAt: Date? = nil,
        firstSeenAt: Date = Fixture.now.addingTimeInterval(-86_400)
    ) -> PulseItem {
        PulseItem(
            id: id,
            source: .calendar,
            kind: .followup,
            title: "Item \(id)",
            detail: "",
            priority: .normal,
            status: status,
            firstSeenAt: firstSeenAt,
            lastSeenAt: updatedAt,
            updatedAt: updatedAt,
            resolvedAt: resolvedAt,
            lastChangedBy: "capture"
        )
    }

    static func commandLine(
        id: String = UUID().uuidString,
        at: Date,
        op: String = "done",
        itemId: String,
        until: String? = nil,
        reason: String? = nil
    ) -> String {
        var fields = [
            #""id":"\#(id)""#,
            #""at":"\#(PulseJSON.dates.string(from: at))""#,
            #""op":"\#(op)""#,
            #""itemId":"\#(itemId)""#,
        ]
        fields.append(until.map { #""until":"\#($0)""# } ?? #""until":null"#)
        fields.append(reason.map { #""reason":"\#($0)""# } ?? #""reason":null"#)
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func appendCommands(_ lines: [String], to container: any CloudContainer) throws {
        for line in lines {
            try container.append(Data(line.utf8) + Data("\n".utf8), to: CommandReader.commandsFileName)
        }
    }

    /// A reader with an in-memory bookmark, so the tests never write the device
    /// cursor file and each case starts from a clean slate.
    static func reader(
        _ container: any CloudContainer,
        _ store: ItemStore,
        cursor: any CommandCursor = MemoryCommandCursor(),
        now: Date? = nil
    ) -> CommandReader {
        let instant = now ?? Fixture.now.addingTimeInterval(600)
        return CommandReader(container: container, store: store, cursor: cursor) { instant }
    }

    static func ackIDs(in container: any CloudContainer) throws -> [String] {
        guard let data = try container.read(CommandReader.ackFileName) else { return [] }
        return CommandReader.completeLines(in: data)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { line -> String? in
                struct Ack: Decodable { let id: String }
                return try? PulseJSON.decoder.decode(Ack.self, from: Data(line.utf8)).id
            }
    }
}
