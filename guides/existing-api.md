# Adopting Portolan in an existing API

This guide moves an API that already has clients, and maybe a
hand-written OpenAPI document, to Portolan, without changing what the
clients receive. It follows the order that keeps every step small: the
configuration first, then one controller at a time, with the tests of the
API passing after each one.

It assumes Portolan is installed and its compiler added, see steps 1 to 6
of [Getting started](getting-started.md).

## 1. Keep the error format of your clients

Portolan answers errors in the format of Phoenix,
`{"errors": {"detail": "Not Found"}}`, and validation errors with `422`.
If your clients read another format, write an error renderer that keeps
it, and it will be used both to answer and to document the errors:

```elixir
defmodule MyAppWeb.ApiErrors do
  @behaviour Portolan.ErrorRenderer

  import Plug.Conn

  alias Plug.Conn.Status

  # The message of {:error, {reason, message}}, or the status in words.
  @impl true
  def render_error(conn, status, _reason, message) do
    reason = message || status |> Status.reason_phrase() |> String.downcase()

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{status: "error", reason: reason})
  end

  @impl true
  def render_validation(conn, errors) do
    conn
    |> put_status(validation_status())
    |> Phoenix.Controller.json(%{status: "error", reason: "validation", errors: errors})
  end

  @impl true
  def validation_status, do: 400

  @impl true
  def error_schema do
    %{
      "type" => "object",
      "properties" => %{"status" => %{"const" => "error"}, "reason" => %{"type" => "string"}},
      "required" => ["status", "reason"]
    }
  end

  @impl true
  def validation_schema do
    %{
      "type" => "object",
      "properties" => %{
        "status" => %{"const" => "error"},
        "reason" => %{"const" => "validation"},
        "errors" => %{
          "type" => "object",
          "additionalProperties" => %{"type" => "array", "items" => %{"type" => "string"}}
        }
      },
      "required" => ["status", "reason", "errors"]
    }
  end
end
```

```elixir
config :my_app, Portolan,
  router: MyAppWeb.Router,
  error_renderer: MyAppWeb.ApiErrors
```

Validation errors have a single status for the whole API. If some
endpoints answered `400` and others `422`, pick one: it is a change for
the clients of the others.

## 2. Describe the authentication

Declare the schemes, and where the requirements of each operation come
from. A callback receives the controller and the action, so it can read
them from the same place the application enforces them, as a catalog of
token scopes:

```elixir
config :my_app, Portolan,
  router: MyAppWeb.Router,
  error_renderer: MyAppWeb.ApiErrors,
  security_schemes: %{bearer: %{type: "http", scheme: "bearer"}},
  security: {MyAppWeb.ApiSecurity, :requirements}
```

```elixir
defmodule MyAppWeb.ApiSecurity do
  def requirements(controller, action) do
    case MyApp.ApiScopes.for_route(controller, action) do
      nil -> [bearer: []]
      scope -> [bearer: [scope]]
    end
  end
end
```

See `Portolan.Security` for the forms requirements can take.

## 3. Move a controller without touching its actions

Add `use Portolan.Controller, cast: false` to the controller. With
`cast: false` the parameters are validated against their types, and
documented, but the actions keep receiving them as Phoenix gives them,
with string keys, so neither the actions nor the contexts they call
change:

```elixir
defmodule MyAppWeb.RecordsApi do
  @moduledoc """
  DNS records of a zone.
  """
  use MyAppWeb, :api
  use Portolan.Controller, cast: false, tag: "DNS records"
```

`:tag` names the group of the operations in the documentation. Without
it, the name of the module without `Controller` is used.

Then, for each action:

* add a `@doc`, its first paragraph is the summary of the operation
* add a `@spec` whose second argument describes the parameters, and
  whose return type describes the responses
* return the result instead of building the response:

```elixir
# Before
def index(conn, params) do
  json(conn, %{status: "ok", records: Records.list(conn.assigns.zone, params["type"])})
end

# After
@spec index(Plug.Conn.t(), index_params()) :: {:ok, records_response()} | {:error, :not_found}
def index(conn, params) do
  {:ok, %{status: :ok, records: Records.list(conn.assigns.zone, params["type"])}}
end
```

Wrappers such as `%{status: "ok", records: [...]}` are described with a
map type, `:ok` being the string `"ok"` in JSON:

```elixir
@typedoc "The records of a zone."
@type records_response :: %{status: :ok, records: [Record.t()]}
```

Run the tests of the controller: the clients receive the same, so they
should pass unchanged.

## 4. Errors with a message

When an error carries a message for the client, return it with its
status:

```elixir
@spec show(Plug.Conn.t(), show_params()) ::
        {:ok, Project.t()} | {:error, {:not_found | :conflict, String.t()}}
def show(_conn, params) do
  case Projects.find(params["name"]) do
    nil -> {:error, {:not_found, "Project not found"}}
    project -> {:ok, project}
  end
end
```

The message reaches the `render_error/4` of your renderer.

## 5. Plain text

Actions that answer text, as an export, return `Portolan.Text`. It can
share its status with JSON, and both are documented:

```elixir
@spec export(Plug.Conn.t(), export_params()) :: {:ok, [Entry.t()]} | {:ok, Portolan.Text.t()}
def export(_conn, %{"format" => "dotenv"} = params), do: {:ok, Portolan.Text.new(dotenv(params))}
def export(_conn, params), do: {:ok, entries(params)}
```

## 6. Ecto schemas as responses

A schema returned as is, with `@derive {Jason.Encoder, only: [...]}`, is
documented with the fields its encoder sends. The others, such as
`__meta__` or the associations, are left out, so their types do not
matter. With [TypedEctoSchema](https://hex.pm/packages/typed_ecto_schema),
the type is generated: add its `@typedoc` before `typed_schema`, mark the
fields that are never `nil` with `null: false`, and give `:map` fields a
type of their own:

```elixir
@derive {Jason.Encoder, only: ~w[id type host content]a}

@typedoc "The fields of the record, by its type."
@type content :: %{optional(String.t()) => String.t() | integer()}

@typedoc """
A DNS record.

* `host` - the name inside the zone
"""
typed_schema "records" do
  field :type, :string, null: false
  field :host, :string, null: false
  field(:content, :map, null: false) :: content()
end
```

`map()` alone cannot be documented: say what it holds.

## 7. Responses of plugs

Responses sent by plugs, as a `404` when the zone of the path does not
exist or a `403` when the token lacks a scope, happen before the action.
Add them to the `@spec` of the actions they guard, so they are documented:

```elixir
@spec index(Plug.Conn.t(), index_params()) ::
        {:ok, records_response()} | {:error, :forbidden | :not_found}
```

Keep their bodies in the format of your renderer, calling it from the
plug if you like:

```elixir
conn |> MyAppWeb.ApiErrors.render_error(404, :not_found, nil) |> halt()
```

## 8. Replace the old document

Once every controller is moved, remove the hand-written document and the
route serving it, and serve the generated one instead, see
[Embedding Scalar](embedding-scalar.md) to show it inside your layout.
A test keeps the document honest from then on, for example checking every
scope of the application appears in it:

```elixir
test "every scope is documented" do
  config = Application.fetch_env!(:my_app, Portolan)

  {:ok, %{document: document}, []} =
    Portolan.Compiler.build(
      config[:router],
      [title: "My API", version: "1"] ++
        Keyword.take(config, [:security_schemes, :security, :error_renderer])
    )

  scopes =
    for {_path, operations} <- document["paths"],
        {_method, operation} <- operations,
        %{"bearer" => scopes} <- operation["security"] || [],
        do: scopes

  assert Enum.sort(Enum.uniq(List.flatten(scopes))) == Enum.sort(MyApp.ApiScopes.all())
end
```

Matching `[]` as the warnings also makes the test fail when an action is
left undocumented.

## Pitfalls

* **`record() cannot be represented in OpenAPI`**: some names, as
  `record`, `list` or `map`, are built-in types. Name yours
  `record_response` or similar.
* **A parameter now answers `400` (or `422`)**: invalid parameters are
  rejected before the action, where the action may have answered `404` or
  crashed. Type the parameter as `String.t()` if the old answer must stay.
* **The document has no examples**: Portolan describes types, not values.
