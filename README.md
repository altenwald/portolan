# Portolan

[![Hex Package](https://img.shields.io/hexpm/v/portolan.svg)](https://hex.pm/packages/portolan)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/portolan)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/altenwald/portolan/blob/main/LICENSE)

> A *portolan* was a medieval nautical chart describing ports and the routes
> between them. Portolan does the same for your Phoenix API.

Portolan builds the [OpenAPI](https://www.openapis.org) document of a
Phoenix application from what the code already says:

* the **router** gives the paths, verbs and actions
* **`@spec`** gives the parameters and responses of every action
* **`@type`** gives the schemas
* **`@moduledoc`**, **`@doc`** and **`@typedoc`** give the descriptions
* **`@deprecated`** marks deprecated operations

There is no extra DSL to learn and nothing to keep in sync. If something
needed for the document is missing, such as an action without `@spec` or a
type that cannot be represented in JSON, the build fails with a compiler
diagnostic pointing to the exact file and line.

> **Status:** under active development. The type conversion layer is
> available; the compiler, the controller integration and the documentation
> UI are being built. The API may change before 1.0.

## How it looks

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  @typedoc """
  Parameters to fetch a user.

  * `id` - the user identifier
  * `include` - related data to embed in the response
  """
  @type show_params :: %{
          required(:id) => Ecto.UUID.t(),
          optional(:include) => [:roles | :teams]
        }

  @doc """
  Fetches a user.

  Returns the user with the requested related data.
  """
  @spec show(Plug.Conn.t(), show_params()) :: {:ok, MyApp.User.t()} | {:error, :not_found}
  def show(_conn, %{id: id} = params) do
    MyApp.Accounts.fetch_user(id, params[:include] || [])
  end
end
```

From this Portolan knows that `GET /users/{id}` takes a UUID in the path
and an optional `include` query parameter, that it answers `200` with a
`MyApp.User` or `404`, and how to describe all of it. The same description
is used to cast the incoming parameters, so `params` arrives with atom keys
and typed values, and the documentation can never disagree with the
validation.

## Types

Typespecs are translated into JSON Schema (the dialect used by OpenAPI 3.1
and 3.2):

| Typespec                                  | JSON Schema                                     |
| ----------------------------------------- | ----------------------------------------------- |
| `String.t()`, `binary()`                  | `{"type": "string"}`                            |
| `Ecto.UUID.t()`                           | `{"type": "string", "format": "uuid"}`          |
| `Date.t()`, `DateTime.t()`                | `{"type": "string", "format": "date"}`, `"date-time"` |
| `Decimal.t()`                             | `{"type": "string", "format": "decimal"}`       |
| `integer()`, `pos_integer()`, `1..100`    | `{"type": "integer"}` with `minimum`/`maximum`  |
| `float()`, `number()`                     | `{"type": "number"}`                            |
| `boolean()`                               | `{"type": "boolean"}`                           |
| `:active \| :inactive`                    | `{"enum": ["active", "inactive"]}`              |
| `integer() \| nil`                        | `{"type": ["integer", "null"]}`                 |
| `[t]`, `list(t)`, `nonempty_list(t)`      | `{"type": "array", "items": ...}`               |
| `%{required(:a) => t, optional(:b) => t}` | `{"type": "object", "required": ["a"], ...}`    |
| `%{optional(String.t()) => t}`            | `{"type": "object", "additionalProperties": ...}` |
| `%MyStruct{}` and other named types       | `{"$ref": "#/components/schemas/..."}`          |

Types that cannot be represented, such as `term()`, `atom()`, `map()`,
`pid()` or tuples, are reported as errors. See `Portolan.Type` for the
complete reference.

## Installation

Add `portolan` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:portolan, "~> 0.1.0"}
  ]
end
```

`Decimal.t()` support requires the optional
[`decimal`](https://hex.pm/packages/decimal) dependency.

## License

Portolan is released under the [MIT License](LICENSE).
