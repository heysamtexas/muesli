import Foundation
import Testing
@testable import MuesliCLI

@Suite("MuesliCLI", .serialized)
struct MuesliCLITests {
    @Test("spec exposes the agent-facing command set")
    func specPayloadIncludesCommands() {
        let names = Set(MuesliCLI.specPayload().commands.map(\.name))

        #expect(names.contains("spec"))
        #expect(names.contains("info"))
        #expect(names.contains("meetings list"))
        #expect(names.contains("meetings get"))
        #expect(names.contains("meetings update-notes"))
        #expect(names.contains("dictations list"))
        #expect(names.contains("dictations get"))
    }

    @Test("explicit db path overrides support directory resolution")
    func cliContextUsesExplicitDatabasePath() {
        let context = CLIContext(
            dbPath: "/tmp/custom-muesli.db",
            supportDir: "/tmp/ignored-support"
        )

        #expect(context.databaseURL.path == "/tmp/custom-muesli.db")
        #expect(context.supportDirectory.path == "/tmp/ignored-support")
    }

    @Test("explicit support dir resolves the default db name inside it")
    func cliContextUsesExplicitSupportDirectory() {
        let context = CLIContext(
            dbPath: nil,
            supportDir: "/tmp/muesli-support"
        )

        #expect(context.supportDirectory.path == "/tmp/muesli-support")
        #expect(context.databaseURL.path == "/tmp/muesli-support/muesli.db")
    }
}
