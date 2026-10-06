defmodule StoreWeb.ProductController do
  @moduledoc """
  Products of the catalog.
  """
  use StoreWeb, :controller
  use Portolan.Controller

  alias Store.Catalog
  alias Store.Catalog.Product

  @typedoc """
  Filters for the list of products.

  * `status` - only products with this status
  * `max_price_cents` - only products up to this price
  """
  @type index_params :: %{
          optional(:status) => Product.status(),
          optional(:max_price_cents) => non_neg_integer()
        }

  @typedoc """
  Identifies a product.

  * `id` - the product identifier
  """
  @type show_params :: %{required(:id) => pos_integer()}

  @typedoc """
  A new product.

  * `name` - the name shown to customers
  * `price_cents` - the price, in cents
  """
  @type create_params :: %{
          required(:name) => String.t(),
          required(:price_cents) => non_neg_integer()
        }

  @doc """
  Lists products.

  Products can be filtered by status.
  """
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [Product.t()]}
  def index(_conn, params) do
    max = params[:max_price_cents]

    {:ok,
     Enum.filter(
       Catalog.list_products(),
       &(params[:status] in [nil, &1.status] and (max == nil or &1.price_cents <= max))
     )}
  end

  @doc "Fetches a product."
  @spec show(Plug.Conn.t(), show_params()) :: {:ok, Product.t()} | {:error, :not_found}
  def show(_conn, %{id: id}), do: Catalog.fetch_product(id)

  @doc "Creates a product."
  @spec create(Plug.Conn.t(), create_params()) :: {:created, Product.t()}
  def create(_conn, params) do
    {:created, struct(Product, Map.merge(params, %{id: 3, status: :available}))}
  end
end
