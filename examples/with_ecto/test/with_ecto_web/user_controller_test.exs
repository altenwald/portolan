defmodule WithEctoWeb.UserControllerTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint WithEctoWeb.Endpoint

  defp api, do: build_conn() |> put_req_header("accept", "application/json")

  test "creates, updates and lists users" do
    conn = post(api(), "/api/users", %{"name" => "Ada", "email" => "ada@example.com", "role" => "admin"})
    assert %{"id" => id, "role" => "admin"} = json_response(conn, 201)

    conn = put(api(), "/api/users/#{String.upcase(id)}", %{"name" => "Ada Lovelace"})
    assert %{"id" => ^id, "name" => "Ada Lovelace"} = json_response(conn, 200)

    assert [%{"id" => ^id}] = api() |> get("/api/users?role=admin") |> json_response(200)
  end

  test "parameters that do not match the spec are rejected by Portolan" do
    conn = post(api(), "/api/users", %{"name" => "Ada", "email" => "ada@example.com", "role" => "root"})

    assert json_response(conn, 422) == %{
             "errors" => %{"role" => [~s(must be one of "admin" or "member")]}
           }

    assert %{"errors" => %{"id" => ["must be a UUID"]}} =
             api() |> get("/api/users/42") |> json_response(422)
  end

  test "data rejected by the changeset" do
    conn = post(api(), "/api/users", %{"name" => "A", "email" => "nope"})

    assert json_response(conn, 422) == %{
             "errors" => %{
               "name" => ["should be at least 2 character(s)"],
               "email" => ["has invalid format"]
             }
           }
  end

  test "unknown users" do
    conn = put(api(), "/api/users/#{Ecto.UUID.generate()}", %{"name" => "Nobody"})
    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end

  test "the OpenAPI document uses version 3.2" do
    document = api() |> get("/openapi.json") |> response(200) |> JSON.decode!()

    assert document["openapi"] == "3.2.0"
    assert document["info"]["title"] == "Accounts API"
    assert [%{"name" => "Validation", "kind" => "nav"}, %{"name" => "User", "summary" => "User accounts."}] = document["tags"]

    user = document["components"]["schemas"]["WithEcto.Accounts.User"]
    assert user["properties"]["id"] == %{"type" => "string", "format" => "uuid", "description" => "unique identifier"}
  end
end
