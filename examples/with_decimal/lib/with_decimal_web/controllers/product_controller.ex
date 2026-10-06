defmodule WithDecimalWeb.ProductController do
  @moduledoc "Products of the catalog."
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias WithDecimal.Catalog
  alias WithDecimal.Catalog.Product

  @typedoc """
  Filters for the list of products.

  * `max_price` - only products up to this price
  * `currency` - only products in this currency
  """
  @type index_params :: %{
          optional(:max_price) => Decimal.t(),
          optional(:currency) => Product.currency()
        }

  @typedoc """
  A new product.

  * `name` - the product name
  * `price` - the price, as a string or a number
  * `currency` - the currency of the price
  """
  @type create_params :: %{
          required(:name) => String.t(),
          required(:price) => Decimal.t(),
          required(:currency) => Product.currency()
        }

  @doc "Lists products, cheapest first."
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [Product.t()]}
  def index(_conn, params) do
    products =
      Enum.filter(Catalog.list(), fn product ->
        params[:currency] in [nil, product.currency] and
          (params[:max_price] == nil or Decimal.compare(product.price, params[:max_price]) != :gt)
      end)

    {:ok, products}
  end

  @doc "Adds a product to the catalog."
  @spec create(Plug.Conn.t(), create_params()) ::
          {:created, Product.t()} | {:error, Ecto.Changeset.t()}
  def create(_conn, params) do
    with {:ok, product} <- Catalog.create(params), do: {:created, product}
  end
end
