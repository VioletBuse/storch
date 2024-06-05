//// Storch is a module to migrate sqlight databases

import filepath
import gleam/bool
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/regex
import gleam/result
import gleam/string
import simplifile
import sqlight.{type Connection}

/// Migrations with an id and a sql script
/// 
pub type Migration {
  Migration(id: Int, up: String)
}

/// Migration error type
pub type MigrationError {
  /// Folder that you gave does not exist
  DirectoryNotExist(String)
  /// The migration script file name is not valid
  InvalidMigrationName(String)
  /// The migration script file has a non-integer id
  InvalidMigrationId(String)
  /// Error starting or comitting the migration transaction
  TransactionError(sqlight.Error)
  /// Error reading/writing/creating the transactions table
  MigrationsTableError(sqlight.Error)
  /// Error applying the migrations script
  MigrationScriptError(Int, sqlight.Error)
}

fn migration_error(error: MigrationError) -> fn(a) -> MigrationError {
  fn(_) { error }
}

/// Pass in a list of migrations and a sqlight connection
/// 
pub fn migrate(
  migrations: List(Migration),
  on connection: Connection,
) -> Result(Nil, MigrationError) {
  let transaction = {
    use _ <- result.try(
      sqlight.exec("begin transaction;", connection)
      |> result.map_error(TransactionError),
    )
    use _ <- result.try(
      sqlight.exec(
        "create table if not exists storch_migrations (id integer, applied integer);",
        connection,
      )
      |> result.map_error(MigrationsTableError),
    )

    let migrations_decoder = dynamic.tuple2(dynamic.int, sqlight.decode_bool)

    let applications =
      list.try_each(migrations, fn(migration) {
        use migrated <- result.try(
          sqlight.query(
            "select id, applied from storch_migrations where id = ?;",
            on: connection,
            with: [sqlight.int(migration.id)],
            expecting: migrations_decoder,
          )
          |> result.map_error(MigrationsTableError),
        )

        let already_applied = case migrated {
          [] -> False
          [#(_, applied)] -> applied
          _ ->
            panic as "Multiple migrations with the same id in the storch migrations table"
        }

        use <- bool.guard(when: already_applied, return: Ok(Nil))

        use _ <- result.try(
          sqlight.exec(migration.up, connection)
          |> result.map_error(MigrationScriptError(migration.id, _)),
        )
        use _ <- result.try(
          sqlight.query(
            "insert into storch_migrations (id, applied) values (?,?) returning *;",
            on: connection,
            with: [sqlight.int(migration.id), sqlight.bool(True)],
            expecting: migrations_decoder,
          )
          |> result.map_error(MigrationsTableError),
        )

        Ok(Nil)
      })

    use _ <- result.try(applications)

    use _ <- result.try(
      sqlight.exec("commit;", connection) |> result.map_error(TransactionError),
    )
    Ok(Nil)
  }

  case transaction {
    Ok(_) -> {
      Ok(Nil)
    }
    Error(err) -> {
      io.println("error running migration")
      io.debug(err)
      io.println("rolling back")
      let _ = sqlight.exec("rollback;", connection)
      Error(err)
    }
  }
}

/// Get a list of migrations from a folder in the filesystem
/// migration files *must* end in .sql and start with an integer id followed by an underscore
/// example: 0000001_init.sql
/// 
/// you could store these in the priv directory if you like, that's probably the best way
pub fn get_migrations(
  in directory: String,
) -> Result(List(Migration), MigrationError) {
  use filenames <- result.try(get_migration_filenames(directory))
  use raw_migrations <- result.try(read_migrations(filenames))

  list.map(raw_migrations, fn(raw) { Migration(raw.0, raw.1) })
  |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  |> Ok
}

fn read_migrations(
  scripts paths: List(String),
) -> Result(List(#(Int, String)), MigrationError) {
  list.try_map(paths, fn(path) {
    let filename = filepath.base_name(path)

    use #(id, _) <- result.try(
      string.split_once(filename, "_")
      |> result.map_error(migration_error(InvalidMigrationName(filename))),
    )
    use id <- result.try(
      int.parse(id) |> result.map_error(migration_error(InvalidMigrationId(id))),
    )

    let assert Ok(contents) = simplifile.read(path)

    Ok(#(id, contents))
  })
}

fn get_migration_filenames(
  in directory: String,
) -> Result(List(String), MigrationError) {
  use is_dir <- result.try(
    simplifile.is_directory(directory)
    |> result.map_error(migration_error(DirectoryNotExist(directory))),
  )
  use <- bool.guard(when: !is_dir, return: Error(DirectoryNotExist(directory)))

  use filenames_raw <- result.try(
    simplifile.get_files(directory)
    |> result.map_error(migration_error(DirectoryNotExist(directory))),
  )

  list.map(filenames_raw, fn(path) {
    use extension <- result.try(filepath.extension(path))
    let base_path = filepath.directory_name(path)
    let filename = filepath.base_name(path) |> filepath.strip_extension

    use <- bool.guard(when: extension != "sql", return: Error(Nil))
    use <- bool.guard(when: base_path != directory, return: Error(Nil))

    use #(numbers, _) <- result.try(string.split_once(filename, "_"))

    use regex <- result.try(regex.from_string("^[0-9]+$") |> result.nil_error)
    use <- bool.guard(when: !regex.check(regex, numbers), return: Error(Nil))
    Ok(path)
  })
  |> result.values
  |> Ok
}
