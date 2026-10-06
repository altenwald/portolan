defmodule StoreWeb.ProductControllerTest do
  use StoreWeb.ConnCase

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  test "lists products filtered by status", %{conn: conn} do
    assert [%{"name" => "Notebook"}] =
             conn |> get(~p"/api/products?status=sold_out") |> json_response(200)
  end

  test "fetches a product", %{conn: conn} do
    assert %{"name" => "Pen", "status" => "available"} =
             conn |> get(~p"/api/products/1") |> json_response(200)

    assert %{"errors" => %{"detail" => "Not Found"}} =
             conn |> get(~p"/api/products/9") |> json_response(404)
  end

  test "parameters are cast and validated", %{conn: conn} do
    assert %{"errors" => %{"id" => ["must be an integer"]}} =
             conn |> get(~p"/api/products/pen") |> json_response(422)

    conn = post(conn, ~p"/api/products", %{"name" => "Ink", "price_cents" => "99"})
    assert %{"name" => "Ink", "price_cents" => 99} = json_response(conn, 201)
  end
end
