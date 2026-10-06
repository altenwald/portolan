defmodule MinimalWeb.NoteControllerTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint MinimalWeb.Endpoint

  defp api, do: build_conn() |> put_req_header("accept", "application/json")

  test "creates, lists, fetches and deletes notes" do
    conn = post(api(), "/api/notes", %{"title" => "Buy milk", "tags" => ["home"], "pinned" => "true"})
    assert %{"id" => id, "title" => "Buy milk", "pinned" => true} = json_response(conn, 201)

    assert [%{"id" => ^id}] = api() |> get("/api/notes?tag=home") |> json_response(200)
    assert [] = api() |> get("/api/notes?tag=work") |> json_response(200)
    assert %{"id" => ^id} = api() |> get("/api/notes/#{id}") |> json_response(200)

    assert api() |> delete("/api/notes/#{id}") |> response(204) == ""
    assert %{"errors" => %{"detail" => "Not Found"}} = api() |> get("/api/notes/#{id}") |> json_response(404)
  end

  test "invalid parameters" do
    conn = post(api(), "/api/notes", %{"tags" => "home"})

    assert json_response(conn, 422) == %{
             "errors" => %{"title" => ["is required"], "tags" => ["must be a list"]}
           }

    assert %{"errors" => %{"id" => ["must be greater than or equal to 1"]}} =
             api() |> get("/api/notes/0") |> json_response(422)
  end

  test "the OpenAPI document is served" do
    document = api() |> get("/openapi.json") |> response(200) |> JSON.decode!()

    assert document["openapi"] == "3.1.1"
    assert document["info"]["title"] == "Minimal"
    assert Map.keys(document["paths"]) == ["/api/notes", "/api/notes/{id}"]
    assert [%{"name" => "Getting started"}, %{"name" => "Note"}] = document["tags"]
  end

  test "the documentation interface is served" do
    html = api() |> get("/openapi.html") |> response(200)
    assert html =~ "@scalar/api-reference"
    assert html =~ ~s("url":"openapi.json")
  end
end
