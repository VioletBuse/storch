import filepath
import gleam/bool
import gleam/erlang
import gleam/int
import gleam/io
import gleam/list
import gleam/regex
import gleam/result
import gleam/string
import simplifile

pub fn main() {
  use migrations_dir <- result.try(get_migrations_dir())
  use filenames <- result.try(get_migration_filenames(in: migrations_dir))
  use migrations <- result.try(get_migrations(filenames))

  io.debug(migrations)
  Ok(filenames)
}

fn get_migrations(
  scripts paths: List(String),
) -> Result(List(#(Int, String)), Nil) {
  list.try_map(paths, fn(path) {
    let filename = filepath.base_name(path)

    use #(id, _) <- result.try(string.split_once(filename, "_"))
    use id <- result.try(int.parse(id))
    use contents <- result.try(simplifile.read(path) |> result.nil_error)

    Ok(#(id, contents))
  })
}

fn get_migration_filenames(in directory: String) {
  use is_dir <- result.try(
    simplifile.is_directory(directory) |> result.nil_error,
  )
  use <- bool.guard(when: !is_dir, return: Error(Nil))

  use filenames_raw <- result.try(
    simplifile.get_files(directory) |> result.nil_error,
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

fn get_migrations_dir() {
  use priv_dir <- result.try(erlang.priv_directory("storch"))
  Ok(filepath.join(priv_dir, "/migrations"))
}
