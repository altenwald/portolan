defmodule Portolan.SharedResponses do
  @moduledoc """
  Responses many operations share, sent before their actions run.

  Plugs answer before the action: a pipeline of the router rejecting a
  request without a token, or a plug of the controller answering `404`
  when the resource of the path does not exist. Those responses are not in
  the `@spec` of the actions, so they are declared apart.

  For every operation, with the `:responses` option of the configuration,
  either the responses themselves or a `{module, function}` called with
  the controller and the action name, as the pipelines of the router
  decide:

      config :my_app, Portolan,
        router: MyAppWeb.Router,
        responses: [unauthorized: :text]

  For the operations of a controller, with the `:responses` option of
  `Portolan.Controller`, as its own plugs decide:

      use Portolan.Controller, responses: [:forbidden, :not_found]

  Responses are written as:

  * a status, as `:not_found`: an error body, sent by the error renderer,
    see `Portolan.ErrorRenderer`
  * `{status, :text}`: plain text
  * `{status, nil}`: no body

  They are added to the ones of the `@spec`. A status in both gets the
  bodies of both as alternatives.
  """

  alias Plug.Conn.Status

  @typedoc "A shared response, as written by the user."
  @type response :: atom() | {atom(), :text | nil}

  @typedoc "Where the shared responses come from."
  @type source :: [response()] | {module(), atom()} | nil

  @typedoc "A shared response with its HTTP status code."
  @type t :: {100..999, :error | :text | nil}

  @doc """
  Normalizes the responses written by the user.

  ## Examples

      iex> Portolan.SharedResponses.normalize([:not_found, unauthorized: :text, no_content: nil])
      {:ok, [{404, :error}, {401, :text}, {204, nil}]}

      iex> Portolan.SharedResponses.normalize(nil)
      {:ok, []}

      iex> Portolan.SharedResponses.normalize([:missing])
      {:error, "unknown status :missing in the shared responses"}

  """
  @spec normalize(term()) :: {:ok, [t()]} | {:error, String.t()}
  def normalize(nil), do: {:ok, []}

  def normalize(responses) when is_list(responses) do
    Enum.reduce_while(responses, {:ok, []}, fn response, {:ok, acc} ->
      case response(response) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        error -> {:halt, error}
      end
    end)
  end

  def normalize(other),
    do: {:error, "the shared responses must be a list, got: #{inspect(other)}"}

  defp response({status, body}) when is_atom(status) and body in [:text, nil],
    do: with({:ok, code} <- code(status), do: {:ok, {code, body}})

  defp response(status) when is_atom(status),
    do: with({:ok, code} <- code(status), do: {:ok, {code, :error}})

  defp response(other) do
    {:error,
     "unsupported shared response #{inspect(other)}, use a status, {status, :text} or {status, nil}"}
  end

  defp code(status) do
    {:ok, Status.code(status)}
  rescue
    FunctionClauseError -> {:error, "unknown status #{inspect(status)} in the shared responses"}
  end

  @doc """
  The shared responses of `action` of `controller`, from the `source` of
  the configuration and the ones of the controller.
  """
  @spec resolve(source(), module(), atom()) :: {:ok, [t()]} | {:error, String.t()}
  def resolve(source, controller, action) do
    global =
      case source do
        {module, function} when is_atom(module) and is_atom(function) ->
          normalize(apply(module, function, [controller, action]))

        responses ->
          normalize(responses)
      end

    with {:ok, global} <- global,
         {:ok, own} <- normalize(controller.__portolan__(:responses)) do
      {:ok, global ++ own}
    end
  end
end
