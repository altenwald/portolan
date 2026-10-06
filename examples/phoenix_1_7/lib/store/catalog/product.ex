defmodule Store.Catalog.Product do
  @moduledoc "A product of the catalog."

  @derive Jason.Encoder
  defstruct [:id, :name, :price_cents, :status]

  @typedoc """
  A product of the catalog.

  * `id` - unique identifier
  * `name` - the name shown to customers
  * `price_cents` - the price, in cents
  * `status` - whether the product can be sold
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          price_cents: non_neg_integer(),
          status: status()
        }

  @typedoc "Whether a product can be sold."
  @type status :: :available | :sold_out
end
