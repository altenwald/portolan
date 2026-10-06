defmodule WithEctoWeb.UserController do
  @moduledoc """
  User accounts.

  Users are validated with an Ecto changeset.
  """
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias WithEcto.Accounts
  alias WithEcto.Accounts.User

  @typedoc """
  Filters for the list of users.

  * `role` - only users with this role
  """
  @type index_params :: %{optional(:role) => User.role()}

  @typedoc """
  Identifies a user.

  * `id` - the user identifier
  """
  @type show_params :: %{required(:id) => Ecto.UUID.t()}

  @typedoc """
  A new user.

  * `name` - the full name
  * `email` - where the user is contacted
  * `role` - what the user is allowed to do, `member` by default
  """
  @type create_params :: %{
          required(:name) => String.t(),
          required(:email) => String.t(),
          optional(:role) => User.role()
        }

  @typedoc """
  Changes to a user.

  * `id` - the user identifier
  * `name` - the full name
  * `email` - where the user is contacted
  """
  @type update_params :: %{
          required(:id) => Ecto.UUID.t(),
          optional(:name) => String.t(),
          optional(:email) => String.t()
        }

  @doc "Lists users, sorted by name."
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [User.t()]}
  def index(_conn, params) do
    {:ok, Enum.filter(Accounts.list(), &(params[:role] in [nil, &1.role]))}
  end

  @doc "Fetches a user."
  @spec show(Plug.Conn.t(), show_params()) :: {:ok, User.t()} | {:error, :not_found}
  def show(_conn, %{id: id}), do: Accounts.fetch(id)

  @doc """
  Creates a user.

  The email must be valid and the name at least two characters long.
  """
  @spec create(Plug.Conn.t(), create_params()) ::
          {:created, User.t()} | {:error, Ecto.Changeset.t()}
  def create(_conn, params) do
    with {:ok, user} <- Accounts.create(params), do: {:created, user}
  end

  @doc "Updates a user."
  @spec update(Plug.Conn.t(), update_params()) ::
          {:ok, User.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update(_conn, %{id: id} = params) do
    with {:ok, user} <- Accounts.fetch(id) do
      Accounts.update(user, Map.delete(params, :id))
    end
  end
end
