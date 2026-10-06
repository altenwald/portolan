defmodule MinimalWeb.Router do
  @moduledoc """
  A notes API.

  The smallest Phoenix application using Portolan: no Ecto and no Decimal.
  """
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MinimalWeb do
    pipe_through :api

    resources "/notes", NoteController, only: [:index, :show, :create, :delete]
  end
end
