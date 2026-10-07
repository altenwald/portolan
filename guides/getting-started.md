# Getting started

This guide adds Portolan to a Phoenix application, step by step. At the
end, the application will have a documented JSON API whose parameters are
cast and validated from their typespecs, an OpenAPI document generated on
every compilation and a page to read it.

The steps work for applications generated with `mix phx.new` in Phoenix
1.7 and 1.8. Where they differ, both versions are shown. The examples use
an application called `MyApp`, replace it with yours.

Portolan requires Elixir 1.18 or later.

## 1. Add the dependency

Add Portolan to the dependencies in `mix.exs`:

```elixir
defp deps do
  [
    # ...
    {:portolan, "~> 0.1"}
  ]
end
```

And fetch it:

```bash
mix deps.get
```

## 2. Add the compiler

Portolan reads the routes, docs and specs of the application once it is
compiled, so its compiler goes after the default ones. In the `project/0`
function of `mix.exs`:

**Phoenix 1.8** already lists the compilers, add `:portolan` at the end:

```elixir
compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:portolan],
```

**Phoenix 1.7** does not list them, add the line:

```elixir
compilers: Mix.compilers() ++ [:portolan],
```

## 3. Configure Portolan

Tell Portolan which router describes the API, in `config/config.exs`:

```elixir
config :my_app, Portolan, router: MyAppWeb.Router
```

This is enough to start. The title and version of the API come from
`mix.exs`, and the description from the `@moduledoc` of the router. See
`Mix.Tasks.Compile.Portolan` for every option, such as the OpenAPI
version or Markdown pages to add to the documentation.

## 4. Keep it updated in development

The code reloader of Phoenix only runs some compilers when the code
changes. Add Portolan to them in `config/dev.exs`, in the configuration of
the endpoint:

```elixir
config :my_app, MyAppWeb.Endpoint,
  # ...
  code_reloader: true,
  reloadable_compilers: [:phoenix_live_view, :gettext, :elixir, :app, :portolan],
```

The list is the default of Phoenix plus `:portolan`, and it is the same
for 1.7 and 1.8. Compilers your project does not use are skipped.

Without this, Portolan detects that a controller changed after its
contracts were generated, and the request fails explaining how to fix it.

## 5. Serve the document and its interface

Portolan writes two static files on every compilation:

* `priv/static/openapi.json` - the OpenAPI document
* `priv/static/openapi.html` - a page showing it with
  [Scalar](https://scalar.com)

Phoenix only serves the static files listed in `static_paths/0`, in
`lib/my_app_web.ex`. Add them:

```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt openapi.json openapi.html)
```

## 6. Ignore the generated contracts

Portolan also writes `priv/portolan/contracts.etf`, the types used to cast
parameters at runtime. It is generated on every compilation, so add it to
`.gitignore`:

```text
/priv/portolan/
```

Whether to commit `openapi.json` and `openapi.html` is up to you. They
are generated too, but committing them shows the changes to the API in
every pull request.

## 7. Describe your data

Responses are described by the types of the data they return. A struct
with its type is enough:

```elixir
defmodule MyApp.Catalog.Product do
  @moduledoc "A product of the catalog."

  @derive Jason.Encoder
  defstruct [:id, :name, :price_cents, :status]

  @typedoc """
  A product of the catalog.

  * `id` - unique identifier
  * `name` - the name shown to customers
  * `price_cents` - the price, in cents
  * `status` - whether the product can be sold
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          price_cents: non_neg_integer(),
          status: status()
        }

  @typedoc "Whether a product can be sold."
  @type status :: :available | :sold_out
end
```

* Every type in the document needs a `@typedoc`, it becomes the
  description of its schema.
* The list of fields in the `@typedoc` is optional. When present, each
  field gets its description, and documenting a field that does not exist
  is an error.
* The struct must be encodable as JSON by the library Phoenix uses. New
  applications use Jason, hence `@derive Jason.Encoder`. If your
  application configures `config :phoenix, :json_library, JSON`, use
  `@derive JSON.Encoder` instead.
* Fields left out of the JSON, as with
  `@derive {Jason.Encoder, except: [:internal_notes]}`, are left out of
  the document too.

## 8. Write a documented controller

Add `use Portolan.Controller` to the controllers of the API, **after**
`use MyAppWeb, :controller`, as it replaces the `action/2` that Phoenix
defines:

```elixir
defmodule MyAppWeb.ProductController do
  @moduledoc """
  Products of the catalog.
  """
  use MyAppWeb, :controller
  use Portolan.Controller

  alias MyApp.Catalog
  alias MyApp.Catalog.Product

  @typedoc """
  Filters for the list of products.

  * `status` - only products with this status
  """
  @type index_params :: %{optional(:status) => Product.status()}

  @typedoc """
  Identifies a product.

  * `id` - the product identifier
  """
  @type show_params :: %{required(:id) => pos_integer()}

  @doc """
  Lists products.

  Products can be filtered by status.
  """
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [Product.t()]}
  def index(_conn, params) do
    {:ok, Enum.filter(Catalog.list_products(), &(params[:status] in [nil, &1.status]))}
  end

  @doc "Fetches a product."
  @spec show(Plug.Conn.t(), show_params()) :: {:ok, Product.t()} | {:error, :not_found}
  def show(_conn, %{id: id}), do: Catalog.fetch_product(id)
end
```

What Portolan takes from each part:

* the `@moduledoc` of the controller groups and describes its operations
* the first paragraph of each `@doc` is the summary of the operation, the
  rest its description
* the second argument of the `@spec` describes the parameters. Keys in the
  route path, as `:id`, are path parameters. The rest are query parameters
  for `GET`, `HEAD`, `DELETE` and `OPTIONS`, and the JSON body for the
  other methods
* the return type of the `@spec` describes the responses: `{:ok, data}`
  answers `200`, `{:error, :not_found}` answers `404`, and
  `{:error, {:not_found, "Product not found"}}` adds a message to it.
  `{:ok, Portolan.Text.t()}` answers plain text. See `Portolan.Response`
  for all of them

At runtime, `params` arrives cast into the type: atom keys, integers as
integers and `"available"` as `:available`. Parameters that do not match
are answered with `422`, without calling the action.

Other controllers, such as the ones rendering HTML, do not use
`Portolan.Controller` and stay out of the document.

## 9. Route it

Routes are written as usual. A new application already has an `:api`
pipeline, uncomment the scope and add the routes:

```elixir
scope "/api", MyAppWeb do
  pipe_through :api

  resources "/products", ProductController, only: [:index, :show]
end
```

Optionally, add a `@moduledoc` to the router: it becomes the description
of the API.

## 10. Compile and try it

```bash
mix compile
```

When something needed for the document is missing, compilation stops and
tells you what and where:

```text
error: MyAppWeb.ProductController.show/2 needs a @spec to be documented
  lib/my_app_web/controllers/product_controller.ex:36
```

Once it compiles, start the server:

```bash
mix phx.server
```

And try the API:

```bash
curl "localhost:4000/api/products?status=sold_out"
```

```json
[{"id":2,"name":"Notebook","status":"sold_out","price_cents":400}]
```

```bash
curl localhost:4000/api/products/pen
```

```json
{"errors":{"id":["must be an integer"]}}
```

The documentation is at <http://localhost:4000/openapi.html> and the
OpenAPI document at <http://localhost:4000/openapi.json>.

## Troubleshooting

* **`use Portolan.Controller after use Phoenix.Controller`**: move
  `use Portolan.Controller` below `use MyAppWeb, :controller`.
* **`params` has string keys**: the controller does not use
  `Portolan.Controller`, or the action is documented with `@doc false`.
* **`cannot read the Portolan contracts`**: `:portolan` is missing from
  the compilers in `mix.exs`, see step 2.
* **`the Portolan contracts of ... are outdated`**: `:portolan` is missing
  from the reloadable compilers, see step 4.
* **`Jason.Encoder not implemented`**: the returned struct is not
  encodable, see step 7.

## What's next

* Show the documentation inside a page of your application, with its
  layout and navigation: see [Embedding Scalar](embedding-scalar.md).
* Prefer Swagger UI, or no interface at all: set `ui: :swagger_ui` or
  `ui: false`.
* Serve the interface without depending on a CDN: run
  `mix portolan.ui.install` and set `ui_assets: :local`.
* Move an API that already has clients: see
  [Adopting Portolan in an existing API](existing-api.md).
* Name the group of a controller with `use Portolan.Controller, tag: "Products"`.
* Add Markdown pages to the documentation with the `:pages` option.
* Document how the API is authenticated with `:security_schemes` and
  `:security`, see `Portolan.Security`.
* Answer errors with your own format with `:error_renderer`, see
  `Portolan.ErrorRenderer`.
* Document the responses of plugs, as the `401` of an authentication
  pipeline, with `:responses`, see `Portolan.SharedResponses`.
