defmodule WithDecimalWeb.ProductControllerTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint WithDecimalWeb.Endpoint

  defp api, do: build_conn() |> put_req_header("accept", "application/json")

  test "prices keep their precision" do
    conn = post(api(), "/api/products", %{"name" => "Pen", "price" => "1.50", "currency" => "eur"})
    assert %{"price" => "1.50", "currency" => "eur"} = json_response(conn, 201)

    conn = post(api(), "/api/products", %{"name" => "Book", "price" => 12, "currency" => "eur"})
    assert %{"price" => "12"} = json_response(conn, 201)

    assert [%{"name" => "Pen"}] = api() |> get("/api/products?max_price=10.00") |> json_response(200)
  end

  test "invalid decimals are rejected by Portolan" do
    conn = post(api(), "/api/products", %{"name" => "Pen", "price" => "cheap", "currency" => "eur"})
    assert json_response(conn, 422) == %{"errors" => %{"price" => ["must be a decimal number"]}}
  end

  test "invalid prices are rejected by the changeset" do
    conn = post(api(), "/api/products", %{"name" => "Pen", "price" => "-1", "currency" => "usd"})
    assert json_response(conn, 422) == %{"errors" => %{"price" => ["must be greater than 0"]}}
  end

  test "prices are documented as decimal strings" do
    document = api() |> get("/openapi.json") |> response(200) |> JSON.decode!()
    product = document["components"]["schemas"]["WithDecimal.Catalog.Product"]

    assert product["properties"]["price"] == %{
             "type" => "string",
             "format" => "decimal",
             "description" => "the price, with the precision it was given"
           }
  end
end
