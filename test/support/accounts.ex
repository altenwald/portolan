defmodule Portolan.Test.Account do
  @moduledoc false
  @derive {JSON.Encoder, only: [:id, :email]}
  defstruct [:id, :email, :password_hash, :owner]

  @typedoc """
  An account.

  * `id` - unique identifier
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          email: String.t(),
          password_hash: String.t(),
          owner: pid()
        }
end

defmodule Portolan.Test.Token do
  @moduledoc false
  @derive {JSON.Encoder, except: [:secret]}
  defstruct [:name, :secret]

  @typedoc "An API token."
  @type t :: %__MODULE__{name: String.t(), secret: String.t()}
end

defmodule Portolan.Test.ApiErrors do
  @moduledoc false
  @behaviour Portolan.ErrorRenderer

  import Plug.Conn

  @impl true
  def render_error(conn, status, reason, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{status: "error", reason: message || Atom.to_string(reason)})
  end

  @impl true
  def render_validation(conn, errors) do
    conn
    |> put_status(validation_status())
    |> Phoenix.Controller.json(%{status: "error", reason: "invalid", errors: errors})
  end

  @impl true
  def validation_status, do: 400

  @impl true
  def error_schema do
    %{"type" => "object", "properties" => %{"reason" => %{"type" => "string"}}}
  end

  @impl true
  def validation_schema do
    %{"type" => "object", "properties" => %{"errors" => %{"type" => "object"}}}
  end
end

defmodule Portolan.Test.AccountSecurity do
  @moduledoc false

  @spec requirements(module(), atom()) :: keyword() | nil
  def requirements(_controller, :login), do: []
  def requirements(_controller, _action), do: [bearer: []]
end

defmodule Portolan.Test.AccountController do
  @moduledoc "Accounts."
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias Portolan.Test.Account
  alias Portolan.Test.Token

  @typedoc "Identifies an account."
  @type show_params :: %{required(:id) => pos_integer()}

  @typedoc "Credentials."
  @type login_params :: %{required(:email) => String.t()}

  @doc "Fetches an account."
  @spec show(Plug.Conn.t(), show_params()) ::
          {:ok, Account.t()} | {:error, :bad_request | :not_found}
  def show(_conn, %{id: 1}),
    do: {:ok, %Account{id: 1, email: "ada@example.com", password_hash: "secret"}}

  def show(_conn, %{id: 2}), do: {:error, :bad_request}
  def show(_conn, _params), do: {:error, :not_found}

  @doc "Logs in."
  @spec login(Plug.Conn.t(), login_params()) :: {:ok, Token.t()}
  def login(_conn, %{email: email}), do: {:ok, %Token{name: email, secret: "s3cr3t"}}

  @typedoc """
  The format of an export.

  * `id` - the account
  * `format` - `json` or `text`
  """
  @type export_params :: %{required(:id) => pos_integer(), optional(:format) => :json | :text}

  @doc "Exports an account."
  @spec export(Plug.Conn.t(), export_params()) ::
          {:ok, Account.t()} | {:ok, Portolan.Text.t()} | {:error, {:not_found, String.t()}}
  def export(_conn, %{id: 1, format: :text}),
    do: {:ok, Portolan.Text.new("email=ada@example.com")}

  def export(_conn, %{id: 1}), do: {:ok, %Account{id: 1, email: "ada@example.com"}}
  def export(_conn, _params), do: {:error, {:not_found, "Account not found"}}

  @doc "Removes an account."
  @doc security: [[bearer: ["admin"]], [api_key: []]]
  @spec delete(Plug.Conn.t(), show_params()) :: :no_content | {:error, Ecto.Changeset.t()}
  def delete(_conn, _params) do
    changeset =
      {%{}, %{id: :integer}}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:id, "is in use")

    {:error, changeset}
  end
end

defmodule Portolan.Test.RawController do
  @moduledoc "Parameters as Phoenix gives them."
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller, cast: false, tag: "Raw parameters"

  @typedoc "Echoed parameters."
  @type echo_params :: %{required(:count) => pos_integer()}

  @doc "Echoes the parameters."
  @spec echo(Plug.Conn.t(), echo_params()) :: {:ok, %{optional(String.t()) => String.t()}}
  def echo(_conn, params), do: {:ok, params}
end

defmodule Portolan.Test.AccountRouter do
  @moduledoc false
  use Phoenix.Router

  alias Portolan.Test.AccountController
  alias Portolan.Test.RawController

  post "/login", AccountController, :login
  get "/accounts/:id", AccountController, :show
  get "/accounts/:id/export", AccountController, :export
  delete "/accounts/:id", AccountController, :delete
  get "/echo", RawController, :echo
end

defmodule Portolan.Test.BadErrorController do
  @moduledoc "Errors with messages that are not strings."
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  @doc "Shows."
  @spec show(Plug.Conn.t(), %{required(:id) => pos_integer()}) ::
          {:ok, String.t()} | {:error, {:not_found, integer()}}
  def show(_conn, _params), do: {:ok, "shown"}
end
