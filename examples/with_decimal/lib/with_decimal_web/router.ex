defmodule WithDecimalWeb.Router do
  @moduledoc """
  A catalog API.

  Prices are decimals, sent and received as strings to keep their
  precision.
  """
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WithDecimalWeb do
    pipe_through :api

    resources "/products", ProductController, only: [:index, :create]
  end
end
