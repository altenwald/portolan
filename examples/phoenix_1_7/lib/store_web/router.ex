defmodule StoreWeb.Router do
  @moduledoc """
  The Store API.

  An example of Portolan in a Phoenix 1.7 application.
  """
  use StoreWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StoreWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StoreWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/api-docs", ApiDocsController, :show
    get "/api-docs/openapi.json", ApiDocsController, :download
  end

  scope "/api", StoreWeb do
    pipe_through :api

    resources "/products", ProductController, only: [:index, :show, :create]
  end
end
