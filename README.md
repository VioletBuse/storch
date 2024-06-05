# storch

[![Package Version](https://img.shields.io/hexpm/v/storch)](https://hex.pm/packages/storch)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/storch/)

```sh
gleam add storch
```
```gleam
import storch
import gleam/result
import gleam/erlang
import sqlight

pub fn main() {
  let assert Ok(priv_dir) = erlang.priv_directory("my_module_name")
  use migrations <- result.try(storch.get_migrations(priv_dir <> "/migrations"))
  use connection <- sqlight.with_connection(":memory:")
  storch.migrate(migrations, on: connection)
}
```

Further documentation can be found at <https://hexdocs.pm/storch>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
