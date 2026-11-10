import Observation
import EuphonaKit
import SwiftData

/// The history store. With iCloud sync on, the store mirrors to the user's private iCloud database;
/// off, the same store stays on this device. Switching rebuilds the container on the same file, so
/// nothing is lost either way.
@MainActor @Observable
final class HistoryContainer {
    private(set) var container: ModelContainer
    private(set) var syncs: Bool
    /// The store could not be opened; history lives in memory until the app closes.
    private(set) var isTemporary = false

    init(syncs: Bool) {
        self.syncs = syncs
        (container, isTemporary) = Self.make(syncs: syncs)
    }

    func setSyncs(_ syncs: Bool) {
        guard syncs != self.syncs else { return }
        self.syncs = syncs
        (container, isTemporary) = Self.make(syncs: syncs)
    }

    private static func make(syncs: Bool) -> (ModelContainer, temporary: Bool) {
        let schema = Schema(HistorySchema.models)
        // Without an iCloud account the mirrored configuration fails; the local one still works.
        var configurations = [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
        if syncs { configurations.insert(ModelConfiguration(schema: schema, cloudKitDatabase: .automatic), at: 0) }
        for configuration in configurations {
            if let container = try? ModelContainer(for: schema, configurations: configuration) { return (container, false) }
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store with this schema cannot fail short of the schema itself being invalid.
        return ((try? ModelContainer(for: schema, configurations: memory))!, true)
    }
}
