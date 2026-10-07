defmodule Portolan.ErrorRenderer do
  @moduledoc """
  Renders the error responses of the API and describes them in the
  document.

  Portolan answers errors in two situations:

  * an action returns `{:error, reason}`, rendered with `c:render_error/3`
  * the parameters cannot be cast, or an action returns
    `{:error, Ecto.Changeset.t()}`, rendered with `c:render_validation/2`

  `Portolan.ErrorRenderer.Default` follows the format used by Phoenix. An
  API that already has clients, with its own error format, can keep it
  with a module of its own:

      defmodule MyAppWeb.ApiErrors do
        @behaviour Portolan.ErrorRenderer

        import Plug.Conn

        @impl true
        def render_error(conn, status, reason) do
          conn
          |> put_status(status)
          |> Phoenix.Controller.json(%{status: "error", reason: Atom.to_string(reason)})
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
        def error_schema, do: %{"type" => "object", "properties" => %{...}}

        @impl true
        def validation_schema, do: %{"type" => "object", "properties" => %{...}}
      end

  And configure it:

      config :my_app, Portolan,
        router: MyAppWeb.Router,
        error_renderer: MyAppWeb.ApiErrors

  The same module is used at runtime, to answer, and by the compiler, to
  document those answers: the schemas become the `Portolan.Error` and
  `Portolan.ValidationError` components, and the validation status is the
  one documented for invalid parameters and changesets.
  """

  @typedoc """
  Validation errors, the messages of each field by its name.

  Cast errors join the path of nested fields with dots, as `"items.1.id"`.
  Changeset errors are the ones of `Ecto.Changeset.traverse_errors/2`, so
  nested changesets give nested maps.
  """
  @type errors :: %{optional(String.t() | atom()) => [String.t()] | map() | [map()]}

  @doc """
  Sends the response for `{:error, reason}`, with the `status` of `reason`.
  """
  @callback render_error(conn :: Plug.Conn.t(), status :: 100..999, reason :: atom()) ::
              Plug.Conn.t()

  @doc """
  Sends the response for invalid parameters or an invalid changeset.

  Errors on the parameters as a whole are listed under `"params"`.
  """
  @callback render_validation(conn :: Plug.Conn.t(), errors :: errors()) :: Plug.Conn.t()

  @doc """
  The HTTP status of validation errors, documented for every action with
  documented parameters.
  """
  @callback validation_status() :: 100..999

  @doc """
  The JSON Schema of the body sent by `c:render_error/3`.
  """
  @callback error_schema() :: map()

  @doc """
  The JSON Schema of the body sent by `c:render_validation/2`.
  """
  @callback validation_schema() :: map()

  @doc """
  Returns whether `module` implements this behaviour.

  ## Examples

      iex> Portolan.ErrorRenderer.renderer?(Portolan.ErrorRenderer.Default)
      true

      iex> Portolan.ErrorRenderer.renderer?(String)
      false

  """
  @spec renderer?(module()) :: boolean()
  def renderer?(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(
        [
          render_error: 3,
          render_validation: 2,
          validation_status: 0,
          error_schema: 0,
          validation_schema: 0
        ],
        fn {name, arity} -> function_exported?(module, name, arity) end
      )
  end
end
