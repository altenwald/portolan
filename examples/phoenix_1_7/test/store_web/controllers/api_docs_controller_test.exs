defmodule StoreWeb.ApiDocsControllerTest do
  use StoreWeb.ConnCase

  test "embeds Scalar in a page of the application", %{conn: conn} do
    html = conn |> get(~p"/api-docs") |> html_response(200)

    assert html =~ ~s(id="api-docs")
    assert html =~ ~s(data-document="/openapi.json")
    assert html =~ "@scalar/api-reference@"
    assert html =~ ~s(integrity="sha384-)
  end

  test "the document can be downloaded", %{conn: conn} do
    conn = get(conn, ~p"/api-docs/openapi.json")

    assert response(conn, 200) |> JSON.decode!() |> Map.fetch!("openapi") == "3.1.1"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="store-openapi.json")
           ]
  end

  test "the document is served for the interface", %{conn: conn} do
    assert %{"info" => %{"title" => "Store"}} = conn |> get("/openapi.json") |> json_response(200)
  end
end
