defmodule WithEcto.Accounts.User do
  @moduledoc "A user account."
  use Ecto.Schema

  import Ecto.Changeset

  @derive JSON.Encoder
  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    field :name, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
  end

  @typedoc """
  A user account.

  * `id` - unique identifier
  * `name` - the full name
  * `email` - where the user is contacted
  * `role` - what the user is allowed to do
  """
  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          email: String.t(),
          role: role()
        }

  @typedoc "What a user is allowed to do."
  @type role :: :admin | :member

  @doc "Validates the data of a user."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role])
    |> validate_required([:name, :email])
    |> validate_length(:name, min: 2)
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
  end
end
