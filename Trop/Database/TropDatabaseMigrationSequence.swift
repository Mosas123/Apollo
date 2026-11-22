import GRDB

/// Reuse production registrations in an isolated in-memory database.
/// This invokes only a static registration function. It never opens the
/// singleton's persistent storage or accesses user-library rows.
enum TropDatabaseMigrationSequence {
    static func register(_ migrator: inout DatabaseMigrator) {
        DatabaseService.registerMigrations(&migrator)
    }
}
