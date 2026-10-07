defmodule Portolan.ErrorRenderer.Default do
  @moduledoc """
  The error responses of Portolan, in the format used by Phoenix.

  Errors answer their status with:

      {"errors": {"detail": "Not Found"}}

  The detail is the message of `{:error, {reason, message}}`, when there
  is one.

  Validation errors answer `422`, listing the messages by field:

      {"errors": {"email": ["can't be blank"], "items.1.id": ["must be an integer"]}}

  See `Portolan.ErrorRenderer` to use another format.
  """

  @behaviour Portolan.ErrorRenderer

  import Plug.Conn

  alias Plug.Conn.Status

  @impl true
  def render_error(conn, status, _reason, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{errors: %{detail: message || Status.reason_phrase(status)}})
  end

  @impl true
  def render_validation(conn, errors) do
    conn
    |> put_status(validation_status())
    |> Phoenix.Controller.json(%{errors: errors})
  end

  @impl true
  def validation_status, do: 422

  @impl true
  def error_schema do
    %{
      "type" => "object",
      "description" => "An error.",
      "properties" => %{
        "errors" => %{
          "type" => "object",
          "properties" => %{"detail" => %{"type" => "string"}},
          "required" => ["detail"]
        }
      },
      "required" => ["errors"]
    }
  end

  @impl true
  def validation_schema do
    %{
      "type" => "object",
      "description" => "The request is not valid. Errors are listed by field.",
      "properties" => %{
        "errors" => %{
          "type" => "object",
          "additionalProperties" => %{"type" => "array", "items" => %{"type" => "string"}}
        }
      },
      "required" => ["errors"]
    }
  end
end
