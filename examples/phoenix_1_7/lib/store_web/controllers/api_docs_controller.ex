defmodule StoreWeb.ApiDocsController do
  use StoreWeb, :controller

  # Shows the API documentation with Scalar, inside the layout of the
  # application.
  def show(conn, _params) do
    render(conn, :show,
      page_title: "API",
      scalar_assets: Portolan.UI.assets(:scalar),
      scalar_config: Portolan.UI.scalar_config()
    )
  end

  # Sends the OpenAPI document as a file to save.
  def download(conn, _params) do
    send_download(conn, {:file, Application.app_dir(:store, "priv/static/openapi.json")},
      filename: "store-openapi.json",
      content_type: "application/json"
    )
  end
end
