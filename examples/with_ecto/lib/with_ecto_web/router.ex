defmodule WithEctoWeb.Router do
  @moduledoc """
  An accounts API.

  Uses Ecto schemas and changesets, without a database.
  """
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WithEctoWeb do
    pipe_through :api

    resources "/users", UserController, only: [:index, :show, :create, :update]
  end
end
