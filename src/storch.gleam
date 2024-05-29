import gleam/bool
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/result
import sqlight.{type Connection}

pub type Migration {
  Migration(id: Int, up: String)
}

pub fn migrate(
  migrations: List(Migration),
  on connection: Connection,
) -> Result(Nil, sqlight.Error) {
  let transaction = {
    use _ <- result.try(sqlight.exec("begin transaction;", connection))
    use _ <- result.try(sqlight.exec(
      "create table if not exists storch_migrations (id integer, applied integer);",
      connection,
    ))

    let migrations_decoder = dynamic.tuple2(dynamic.int, sqlight.decode_bool)

    let applications =
      list.try_each(migrations, fn(migration) {
        use migrated <- result.try(sqlight.query(
          "select id, applied from storch_migrations where id = ?;",
          on: connection,
          with: [sqlight.int(migration.id)],
          expecting: migrations_decoder,
        ))

        let already_applied = case migrated {
          [] -> False
          [#(_, applied)] -> applied
          _ ->
            panic as "Multiple migrations with the same id in the storch migrations table"
        }

        use <- bool.guard(when: already_applied, return: Ok(Nil))

        use _ <- result.try(sqlight.exec(migration.up, connection))
        use _ <- result.try(sqlight.query(
          "insert into storch_migrations (id, applied) values (?,?) returning *;",
          on: connection,
          with: [sqlight.int(migration.id), sqlight.bool(True)],
          expecting: migrations_decoder,
        ))

        Ok(Nil)
      })

    use _ <- result.try(applications)

    use _ <- result.try(sqlight.exec("commit;", connection))
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
