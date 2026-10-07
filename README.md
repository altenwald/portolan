<p align="center">
  <img src="assets/logo.png" alt="Portolan Logo" width="160">
</p>

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

> **Status:** under active development. The API may change before 1.0.

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
`MyApp.User` or `404`, and how to describe all of it.

The same description is used at runtime: `params` arrives with atom keys
and typed values, invalid parameters are answered with `422` (or the status
of your error renderer) before the action runs, and the action returns its result instead of building the
response. The documentation can never disagree with the validation.

## Setup

The [getting started guide](guides/getting-started.md) goes through every
step in a Phoenix 1.7 or 1.8 application, and the
[embedding guide](guides/embedding-scalar.md) shows the documentation
inside a page of your application. In short:

Add the Portolan compiler after the default ones in `mix.exs`:

```elixir
def project do
  [
    compilers: Mix.compilers() ++ [:portolan],
    # ...
  ]
end
```

Tell it which router describes the API in `config/config.exs`:

```elixir
config :my_app, Portolan,
  router: MyAppWeb.Router,
  pages: ["docs/authentication.md"]
```

And add `use Portolan.Controller`, after `use Phoenix.Controller`, to every
controller of the API. Other controllers, such as the ones rendering HTML,
are left out of the document.

In development, add `:portolan` to the reloadable compilers of the
endpoint, so the code reloader keeps everything up to date:

```elixir
config :my_app, MyAppWeb.Endpoint,
  reloadable_compilers: [:elixir, :app, :portolan]
```

Serve the document and its interface, written next to it, with the
`Plug.Static` of the endpoint:

```elixir
plug Plug.Static, at: "/", from: :my_app, only: ~w(assets openapi.json openapi.html)
```

The interface is [Scalar](https://scalar.com) by default, and it can be
[Swagger UI](https://swagger.io/tools/swagger-ui/) with `ui: :swagger_ui`,
or none with `ui: false`. It is loaded from the jsDelivr CDN, with pinned
versions and subresource integrity. To serve it from the application
instead, without depending on the CDN, install a copy with
`mix portolan.ui.install`, commit it, and set `ui_assets: :local`. See
`Portolan.UI`.

The document is written to `priv/static/openapi.json` on every compilation,
and the contracts used to cast parameters at runtime to
`priv/portolan/contracts.etf`, which can be ignored by version control.
See `Mix.Tasks.Compile.Portolan` for all the options, including the OpenAPI
version (`"3.1"` by default, or `"3.2"`).

## Where the information comes from

| OpenAPI                       | Source                                                    |
| ----------------------------- | --------------------------------------------------------- |
| API title and version         | the `:name` and `:version` of the project                 |
| API description               | the `@moduledoc` of the router                            |
| Paths and methods             | the routes of the router                                  |
| Tags                          | the controllers and their `@moduledoc`                    |
| Summary and description       | the first paragraph and the rest of the action `@doc`     |
| Deprecated operations         | `@deprecated` or `@doc deprecated: "..."`                 |
| Parameters and request body   | the second argument of the action `@spec`                 |
| Responses                     | the return type of the action `@spec`                     |
| Schemas                       | the referenced `@type`s and their `@typedoc`              |
| Security schemes              | the `:security_schemes` option                            |
| Security of the operations    | `@doc security: ...` or the `:security` option            |
| Error bodies                  | the `:error_renderer` option                              |
| Documentation pages           | the Markdown files in the `:pages` option                 |

### Parameters

The second argument of the spec is a map type. Keys that appear in the
route path are path parameters. The rest are query parameters for `GET`,
`HEAD`, `DELETE` and `OPTIONS`, and the JSON body for the other methods.

Fields can be documented in the `@typedoc` with a list where each item
starts with the field name between backticks. It is optional, but
documenting a field that does not exist is an error.

### Responses

| Return type                    | Response                                     |
| ------------------------------ | -------------------------------------------- |
| `{:ok, data}`                  | `200` with `data`                            |
| `{:created, data}`             | `201` with `data`, the same for any status   |
| `:no_content`                  | `204` without body, the same for any status  |
| `{:error, :not_found}`         | `404` with an error body                     |
| `{:error, Ecto.Changeset.t()}` | `422` with the validation errors             |

Statuses are the atoms known by `Plug.Conn.Status`. Actions with documented
parameters also answer `422` when the parameters are not valid. See
`Portolan.Response` for the bodies of errors.

Fields left out of the JSON of a struct, with
`@derive {Jason.Encoder, only: [...]}` or `except: [...]`, are left out of
its schema too.

### Errors

Errors follow the format of Phoenix, `{"errors": {"detail": "Not Found"}}`,
and validation errors answer `422`. An API with clients that expect
another format can keep it with a module implementing
`Portolan.ErrorRenderer`:

```elixir
config :my_app, Portolan,
  router: MyAppWeb.Router,
  error_renderer: MyAppWeb.ApiErrors
```

The same module answers the errors and describes them in the document,
including the status of validation errors.

### Security

Declare the security schemes, and the requirements of the operations:

```elixir
config :my_app, Portolan,
  router: MyAppWeb.Router,
  security_schemes: %{bearer: %{type: "http", scheme: "bearer"}},
  security: {MyAppWeb.ApiSecurity, :requirements}
```

`:security` takes the requirements of every operation, as `[bearer: []]`,
or a function called with the controller and the action, so they can
follow the pipelines of the router. An action can declare its own with
`@doc security: []`, for a public one, or `@doc security: [bearer: ["admin"]]`.
See `Portolan.Security`.

### Adopting it in an existing controller

Actions receive their parameters cast, with atom keys. When the actions,
or the contexts they call, expect the parameters as Phoenix gives them,
use `use Portolan.Controller, cast: false`: parameters are still
validated, and documented, but arrive with string keys.

Actions written the classic way, receiving `map()` or returning
`Plug.Conn.t()`, keep working, but Portolan cannot know what they receive
or answer, so they are documented without that information and a warning
is reported.

## Diagnostics

Anything needed for the document that is missing or cannot be represented
is reported as a compiler diagnostic, with the file and line to fix:

```text
error: MyAppWeb.UserController.show/2 needs a @spec to be documented
  lib/my_app_web/controllers/user_controller.ex:42
error: term() accepts any value and cannot be documented, use a more specific type
  lib/my_app/accounts/user.ex:12
warning: the response of MyAppWeb.PageController.export/2 is not documented, return {:ok, data} or {:error, reason} instead of Plug.Conn.t()
  lib/my_app_web/controllers/page_controller.ex:30
```

Errors stop the compilation. Actions and controllers documented with
`@doc false` or `@moduledoc false` are left out of the document.

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

## Examples

The [`examples`](https://github.com/altenwald/portolan/tree/main/examples)
directory has complete Phoenix applications: one with Phoenix only, one
with Ecto and one with Ecto and Decimal.

## Installation

Add `portolan` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:portolan, "~> 0.1.0"}
  ]
end
```

`Decimal.t()` parameters require the optional
[`decimal`](https://hex.pm/packages/decimal) dependency, version 3.0 or
later, as earlier ones accept exponents that exhaust the memory
([CVE-2026-32686](https://osv.dev/vulnerability/EEF-CVE-2026-32686)), and
`{:error, Ecto.Changeset.t()}` results the optional
[`ecto`](https://hex.pm/packages/ecto) one.

## License

Portolan is released under the [MIT License](LICENSE).
