-- Private migration archive only. This is not the operational EventCore schema.
-- No HTTP endpoint exposes this data; no real IDs or records belong in this file.
CREATE TABLE migration_sources (
 source_sha256 TEXT PRIMARY KEY,
 captured_at TEXT NOT NULL,
 source_project TEXT NOT NULL,
 imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 state TEXT NOT NULL DEFAULT 'unreconciled' CHECK (state IN ('unreconciled','reconciled'))
) STRICT;
CREATE TABLE migration_recovery_rows (
 source_sha256 TEXT NOT NULL REFERENCES migration_sources(source_sha256),
 table_name TEXT NOT NULL,
 record_key TEXT NOT NULL,
 payload TEXT NOT NULL CHECK (json_valid(payload)),
 PRIMARY KEY (source_sha256,table_name,record_key)
) STRICT;
CREATE TABLE migration_table_inventory (
 source_sha256 TEXT NOT NULL REFERENCES migration_sources(source_sha256),
 table_name TEXT NOT NULL,
 expected_count INTEGER NOT NULL CHECK (expected_count>=0),
 archived_count INTEGER NOT NULL CHECK (archived_count>=0),
 excluded INTEGER NOT NULL CHECK (excluded IN (0,1)),
 PRIMARY KEY (source_sha256,table_name)
) STRICT;
-- Archive is append-only. Restore records into reviewed operational tables separately.
CREATE TRIGGER migration_recovery_rows_no_update BEFORE UPDATE ON migration_recovery_rows BEGIN SELECT RAISE(ABORT,'immutable_recovery_archive'); END;
CREATE TRIGGER migration_recovery_rows_no_delete BEFORE DELETE ON migration_recovery_rows BEGIN SELECT RAISE(ABORT,'immutable_recovery_archive'); END;
