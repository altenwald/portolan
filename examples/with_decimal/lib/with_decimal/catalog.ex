defmodule WithDecimal.Catalog do
  @moduledoc "Keeps the products in memory."
  use Agent

  alias WithDecimal.Catalog.Product

  @doc false
  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Lists the products, cheapest first."
  @spec list() :: [Product.t()]
  def list do
    Agent.get(__MODULE__, &(&1 |> Map.values() |> Enum.sort_by(fn product -> product.price end, Decimal)))
  end

  @doc "Creates a product."
  @spec create(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Product{id: Ecto.UUID.generate()}
    |> Product.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
    |> tap(fn
      {:ok, product} -> Agent.update(__MODULE__, &Map.put(&1, product.id, product))
      _error -> :ok
    end)
  end
end
