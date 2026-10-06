defmodule WithEcto.Accounts do
  @moduledoc "Keeps the users in memory."
  use Agent

  alias WithEcto.Accounts.User

  @doc false
  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Lists the users."
  @spec list() :: [User.t()]
  def list, do: Agent.get(__MODULE__, &(&1 |> Map.values() |> Enum.sort_by(fn user -> user.name end)))

  @doc "Fetches a user."
  @spec fetch(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :not_found}
  def fetch(id) do
    case Agent.get(__MODULE__, &Map.fetch(&1, id)) do
      {:ok, user} -> {:ok, user}
      :error -> {:error, :not_found}
    end
  end

  @doc "Creates a user."
  @spec create(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %User{id: Ecto.UUID.generate()}
    |> User.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
    |> tap(&store/1)
  end

  @doc "Updates a user."
  @spec update(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Ecto.Changeset.apply_action(:update)
    |> tap(&store/1)
  end

  defp store({:ok, user}), do: Agent.update(__MODULE__, &Map.put(&1, user.id, user))
  defp store(_error), do: :ok
end
