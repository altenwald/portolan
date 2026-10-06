defmodule WithDecimal.Catalog.Product do
  @moduledoc "A product of the catalog."
  use Ecto.Schema

  import Ecto.Changeset

  @derive JSON.Encoder
  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    field :name, :string
    field :price, :decimal
    field :currency, Ecto.Enum, values: [:eur, :usd]
  end

  @typedoc """
  A product of the catalog.

  * `id` - unique identifier
  * `name` - the product name
  * `price` - the price, with the precision it was given
  * `currency` - the currency of the price
  """
  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          price: Decimal.t(),
          currency: currency()
        }

  @typedoc "A supported currency."
  @type currency :: :eur | :usd

  @doc "Validates the data of a product."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price, :currency])
    |> validate_required([:name, :price, :currency])
    |> validate_number(:price, greater_than: 0)
  end
end
