defmodule Portolan.ResponseTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Portolan.Response

  defmodule Changeset do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
    end

    def changeset(params) do
      %__MODULE__{}
      |> Ecto.Changeset.cast(params, [:name, :age])
      |> Ecto.Changeset.validate_required([:name])
      |> Ecto.Changeset.validate_number(:age, greater_than: 17)
    end
  end

  defp render(result), do: Response.render(conn(:get, "/"), result)

  defp json(conn), do: JSON.decode!(conn.resp_body)

  describe "render/2" do
    test "{:ok, data} answers 200 with JSON" do
      conn = render({:ok, %{name: "Ada"}})
      assert conn.status == 200
      assert json(conn) == %{"name" => "Ada"}
      assert ["application/json" <> _] = Plug.Conn.get_resp_header(conn, "content-type")
    end

    test "any status can tag the data" do
      conn = render({:created, [1, 2]})
      assert {conn.status, json(conn)} == {201, [1, 2]}
    end

    test "bare statuses answer without body" do
      conn = render(:no_content)
      assert {conn.status, conn.resp_body} == {204, ""}
    end

    test "errors answer the status of their reason" do
      conn = render({:error, :not_found})
      assert {conn.status, json(conn)} == {404, %{"errors" => %{"detail" => "Not Found"}}}
    end

    test "changesets answer 422 with the errors by field" do
      conn = render({:error, Changeset.changeset(%{"age" => "3"})})

      assert {conn.status, json(conn)} ==
               {422,
                %{
                  "errors" => %{
                    "name" => ["can't be blank"],
                    "age" => ["must be greater than 17"]
                  }
                }}
    end

    test "connections are returned as they are" do
      conn = conn(:get, "/") |> Plug.Conn.send_resp(200, "classic")
      assert Response.render(conn(:get, "/"), conn) == conn
    end

    test "anything else is an error" do
      assert_raise ArgumentError, ~r/"oops"/, fn -> render("oops") end
      assert_raise ArgumentError, ~r/:not_a_status/, fn -> render(:not_a_status) end
    end
  end

  describe "invalid_params/2" do
    test "answers 422 with the errors by path" do
      conn =
        Response.invalid_params(conn(:get, "/"), [
          {[:id], "is required"},
          {[:items, 1, :id], "must be an integer"},
          {[:items, 1, :id], "must be greater than 0"},
          {[], "must be an object"}
        ])

      assert conn.status == 422

      assert json(conn) == %{
               "errors" => %{
                 "id" => ["is required"],
                 "items.1.id" => ["must be an integer", "must be greater than 0"],
                 "params" => ["must be an object"]
               }
             }
    end
  end
end
