defmodule Portolan.Response do
  @moduledoc """
  Turns the result of an action into the HTTP response.

  | Result                          | Response                                  |
  | ------------------------------- | ----------------------------------------- |
  | `{:ok, data}`                   | `200` with `data` as JSON                 |
  | `{status, data}`                | `status` with `data` as JSON              |
  | `status`                        | `status` without body                     |
  | `{:error, Ecto.Changeset.t()}`  | `422` with the errors by field            |
  | `{:error, reason}`              | the status of `reason` with an error body |
  | `Plug.Conn.t()`                 | the connection, as it is                  |

  Statuses are the atoms known by `Plug.Conn.Status`. Data is encoded with
  the JSON library configured for Phoenix, so structs must be encodable.

  Error bodies follow the format used by Phoenix:

      {"errors": {"detail": "Not Found"}}

  Validation errors list the messages by field:

      {"errors": {"email": ["can't be blank"], "items.1.id": ["must be an integer"]}}

  """

  import Plug.Conn

  alias Plug.Conn.Status

  @compile {:no_warn_undefined, Ecto.Changeset}

  @typedoc """
  The result of an action.
  """
  @type result :: Plug.Conn.t() | atom() | {atom(), term()}

  @doc """
  Sends the response for the `result` of an action.

  Raises `ArgumentError` when the result is not one of the supported ones.
  """
  @spec render(Plug.Conn.t(), result()) :: Plug.Conn.t()
  def render(_conn, %Plug.Conn{} = conn), do: conn

  def render(conn, {:error, %{__struct__: Ecto.Changeset} = changeset}),
    do: errors(conn, Ecto.Changeset.traverse_errors(changeset, &interpolate/1))

  def render(conn, {:error, reason}) when is_atom(reason) do
    status = code!(reason, {:error, reason})

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{errors: %{detail: Status.reason_phrase(status)}})
  end

  def render(conn, {status, data}) when is_atom(status) do
    conn
    |> put_status(code!(status, {status, data}))
    |> Phoenix.Controller.json(data)
  end

  def render(conn, status) when is_atom(status) do
    send_resp(conn, code!(status, status), "")
  end

  def render(_conn, result), do: unsupported!(result)

  @doc """
  Sends the `422` response for parameters that cannot be cast.

  The errors are the ones returned by `Portolan.Cast.cast/3`. Errors on
  the parameters as a whole are listed under `params`.
  """
  @spec invalid_params(Plug.Conn.t(), [Portolan.Cast.error()]) :: Plug.Conn.t()
  def invalid_params(conn, errors) do
    errors =
      errors
      |> Enum.group_by(&key/1, fn {_path, message} -> message end)

    errors(conn, errors)
  end

  defp errors(conn, errors) do
    conn
    |> put_status(422)
    |> Phoenix.Controller.json(%{errors: errors})
  end

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
