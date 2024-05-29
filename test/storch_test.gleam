import filepath
import gleeunit
import gleeunit/should
import sqlight
import storch

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  use conn <- sqlight.with_connection("/tmp/test.db")

  let migrations = [
    storch.Migration(
      0,
      "create table if not exists table_1 (id integer, data text);",
    ),
    storch.Migration(
      1,
      "create table if not exists table_2 (date integer, value blob);",
    ),
    storch.Migration(
      2,
      "insert into nonexistent_table (id, name) values (23, 45);",
    ),
  ]

  storch.migrate(migrations, on: conn)
}
