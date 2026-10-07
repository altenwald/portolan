defmodule Portolan.Response do
  @moduledoc """
  Turns the result of an action into the HTTP response.

  | Result                          | Response                                  |
  | ------------------------------- | ----------------------------------------- |
  | `{:ok, data}`                   | `200` with `data` as JSON                 |
  | `{status, data}`                | `status` with `data` as JSON              |
  | `status`                        | `status` without body                     |
  | `{:error, Ecto.Changeset.t()}`  | the validation errors, `422` by default   |
  | `{:error, reason}`              | the status of `reason` with an error body |
  | `{:error, {reason, message}}`   | the same, with `message` in the body      |
  | `{status, Portolan.Text.t()}`   | `status` with the text as `text/plain`    |
  | `Plug.Conn.t()`                 | the connection, as it is                  |

  Statuses are the atoms known by `Plug.Conn.Status`. Data is encoded with
  the JSON library configured for Phoenix, so structs must be encodable.

  Errors are sent by an error renderer, `Portolan.ErrorRenderer.Default`
  unless another one is given, see `Portolan.ErrorRenderer`.
  """

  import Plug.Conn

  alias Plug.Conn.Status
  alias Portolan.ErrorRenderer

  @compile {:no_warn_undefined, Ecto.Changeset}

  @typedoc """
  The result of an action.
  """
  @type result :: Plug.Conn.t() | atom() | {atom(), term()}

  @doc """
  Sends the response for the `result` of an action, with errors sent by
  `renderer`.

  Raises `ArgumentError` when the result is not one of the supported ones.
  """
  @spec render(Plug.Conn.t(), result(), module()) :: Plug.Conn.t()
  def render(conn, result, renderer \\ ErrorRenderer.Default)

  def render(_conn, %Plug.Conn{} = conn, _renderer), do: conn

  def render(conn, {:error, %{__struct__: Ecto.Changeset} = changeset}, renderer),
    do: renderer.render_validation(conn, changeset_errors(changeset))

  def render(conn, {:error, reason}, renderer) when is_atom(reason),
    do: renderer.render_error(conn, code!(reason, {:error, reason}), reason, nil)

  def render(conn, {:error, {reason, message}} = result, renderer)
      when is_atom(reason) and is_binary(message),
      do: renderer.render_error(conn, code!(reason, result), reason, message)

  def render(conn, {status, %Portolan.Text{body: body}} = result, _renderer)
      when is_atom(status) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(code!(status, result), body)
  end

  def render(conn, {status, data}, _renderer) when is_atom(status) do
    conn
    |> put_status(code!(status, {status, data}))
    |> Phoenix.Controller.json(data)
  end

  def render(conn, status, _renderer) when is_atom(status) do
    send_resp(conn, code!(status, status), "")
  end

  def render(_conn, result, _renderer), do: unsupported!(result)

  @doc """
  Sends the response for parameters that cannot be cast, with `renderer`.

  The errors are the ones returned by `Portolan.Cast.cast/3`. Errors on
  the parameters as a whole are listed under `params`.
  """
  @spec invalid_params(Plug.Conn.t(), [Portolan.Cast.error()], module()) :: Plug.Conn.t()
  def invalid_params(conn, errors, renderer \\ ErrorRenderer.Default) do
    errors = Enum.group_by(errors, &key/1, fn {_path, message} -> message end)
    renderer.render_validation(conn, errors)
  end

  defp changeset_errors(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, &interpolate/1)

  defp key({[], _message}), do: "params"
  defp key({path, _message}), do: Enum.map_join(path, ".", &to_string/1)

  # Error options are looked up by name, so no atoms are created.
  defp interpolate({message, opts}) do
    Regex.replace(~r/%{(\w+)}/, message, fn match, key -> option(opts, key, match) end)
  end

  defp option(opts, key, default) do
    case Enum.find(opts, fn {name, _value} -> Atom.to_string(name) == key end) do
      {_name, value} -> to_string(value)
      nil -> default
    end
  end

  defp code!(status, result) do
    Status.code(status)
  rescue
    FunctionClauseError -> unsupported!(result)
  end

  @spec unsupported!(term()) :: no_return()
  defp unsupported!(result) do
    raise ArgumentError,
          "unsupported action result: #{inspect(result)}. Return {:ok, data}, " <>
            "{status, data}, status, {:error, reason} or a Plug.Conn"
  end
end
