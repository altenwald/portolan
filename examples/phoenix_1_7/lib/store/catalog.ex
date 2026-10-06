defmodule Store.Catalog do
  @moduledoc "The catalog of products."

  alias Store.Catalog.Product

  @products [
    %Product{id: 1, name: "Pen", price_cents: 150, status: :available},
    %Product{id: 2, name: "Notebook", price_cents: 400, status: :sold_out}
  ]

  @doc "Lists the products."
  @spec list_products() :: [Product.t()]
  def list_products, do: @products

  @doc "Fetches a product."
  @spec fetch_product(pos_integer()) :: {:ok, Product.t()} | {:error, :not_found}
  def fetch_product(id) do
    case Enum.find(@products, &(&1.id == id)) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end
end
