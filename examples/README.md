# Examples

Small Phoenix applications using Portolan. Each one keeps its data in
memory, so they run without a database.

| Example                         | Dependencies                  | Shows                                                    |
| ------------------------------- | ----------------------------- | -------------------------------------------------------- |
| [`minimal`](minimal)            | Phoenix                       | Portolan without Ecto, Decimal or Jason                  |
| [`with_ecto`](with_ecto)        | Phoenix, Ecto                 | `Ecto.UUID.t()`, changeset errors and OpenAPI 3.2        |
| [`with_decimal`](with_decimal)  | Phoenix, Ecto, Decimal        | `Decimal.t()` prices sent and received as strings        |

Run any of them with:

```bash
cd examples/minimal
mix deps.get
mix phx.server
```

The OpenAPI document is served at <http://localhost:4000/openapi.json>.

`check.sh` builds and tests all of them, checks that `minimal` depends on
neither Ecto nor Decimal, and runs `minimal` as a release, where typespecs
are no longer available, to check that parameters are still cast.
