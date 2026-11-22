import GRDB

/// One canonical registration order for both Trop's real persistent store
/// and the wholly separate in-memory combined-recovery rehearsal.
enum TropDatabaseMigrationSequence {
    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1", migrate: DatabaseMigrations.v1)
        migrator.registerMigration("v2", migrate: DatabaseMigrations.v2)
        migrator.registerMigration("v3", migrate: DatabaseMigrations.v3)
        migrator.registerMigration("v4", migrate: DatabaseMigrations.v4)
        migrator.registerMigration("v5", migrate: DatabaseMigrations.v5)
        migrator.registerMigration("v6", migrate: DatabaseMigrations.v6)
        migrator.registerMigration("v7", migrate: DatabaseMigrations.v7)
        migrator.registerMigration("v8", migrate: DatabaseMigrations.v8)
        migrator.registerMigration("v9", migrate: DatabaseMigrations.v9)
        migrator.registerMigration("v10", migrate: DatabaseMigrations.v10)
        migrator.registerMigration("v11", migrate: DatabaseMigrations.v11)
        migrator.registerMigration("v12", migrate: DatabaseMigrations.v12)
        migrator.registerMigration("v13", migrate: DatabaseMigrations.v13)
    }
}
