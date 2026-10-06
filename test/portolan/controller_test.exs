defmodule Portolan.ControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias Portolan.Compiler
  alias Portolan.Contracts
  alias Portolan.Test.Router
  alias Portolan.Test.UserController

  doctest Portolan.Controller

  @ada "6f1c2a7e-3b4d-4e5f-8a9b-0c1d2e3f4a5b"

  setup do
    path = Contracts.path(:portolan)
    backup = File.read(path)

    {:ok, %{contracts: contracts}, _warnings} =
      Compiler.build(Router, title: "Test", version: "1")

    Contracts.save(contracts, path)
    Contracts.forget(:portolan)

    on_exit(fn ->
      case backup do
        {:ok, content} -> File.write!(path, content)
        {:error, _reason} -> File.rm(path)
      end

      Contracts.forget(:portolan)
    end)

    %{path: path, contracts: contracts}
  end

  defp request(method, path, params \\ nil) do
    method
    |> conn(path, params)
    |> Plug.Conn.fetch_query_params()
    |> Router.call(Router.init([]))
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)

  describe "parameters" do
    test "path parameters are cast" do
      conn = request(:get, "/api/users/#{String.upcase(@ada)}")
      assert conn.status == 200
      assert json(conn)["name"] == "Ada"
    end

    test "query parameters are cast into atoms" do
      conn = request(:get, "/api/users?role=member")
      assert [%{"name" => "Grace", "role" => "member"}] = json(conn)
    end

    test "body parameters are cast" do
      conn = request(:post, "/api/users", %{"name" => "Alan", "unknown" => "dropped"})
      assert conn.status == 201
      assert %{"name" => "Alan", "role" => "member", "email" => nil} = json(conn)
    end

    test "invalid parameters answer 422 without calling the action" do
      conn = request(:get, "/api/users/nope?role=boss&page=0")

      assert conn.status == 422

      assert json(conn) == %{"errors" => %{"id" => ["must be a UUID"]}}

      conn = request(:get, "/api/users?role=boss&page=0")

      assert json(conn) == %{
               "errors" => %{
                 "role" => [~s(must be one of "admin" or "member")],
                 "page" => ["must be greater than or equal to 1"]
               }
             }
    end

    test "map() parameters are given as they are" do
      conn = request(:get, "/api/users/export?format=csv")
      assert conn.resp_body =~ ~s("format" => "csv")
    end

    test "hidden actions get the parameters as they are" do
      conn = request(:get, "/api/internal?a=1")
      assert json(conn) == %{"a" => "1"}
    end
  end

  describe "responses" do
    test "errors" do
      conn = request(:get, "/api/users/0b5e7c1d-0000-4b6c-9d8e-7f6a5b4c3d2e")
      assert {conn.status, json(conn)} == {404, %{"errors" => %{"detail" => "Not Found"}}}

      conn = request(:put, "/api/users/#{@ada}", %{"name" => "Ada L."})
      assert conn.status == 403
    end

    test "statuses without body" do
      conn = request(:delete, "/api/users/#{@ada}")
      assert {conn.status, conn.resp_body} == {204, ""}
    end
  end

  test "must be used after Phoenix.Controller" do
    assert_raise CompileError, ~r/after use Phoenix.Controller/, fn ->
      defmodule WrongOrder do
        use Portolan.Controller
      end
    end
  end

  describe "contracts" do
    test "missing contracts explain how to generate them", %{path: path} do
      File.rm!(path)
      Contracts.forget(:portolan)

      assert_raise Plug.Conn.WrapperError,
                   ~r/compilers: Mix.compilers\(\) \+\+ \[:portolan\]/,
                   fn ->
                     request(:get, "/api/users")
                   end
    end

    test "outdated contracts are read again", %{path: path, contracts: contracts} do
      outdated = %{contracts | md5: %{UserController => <<0>>}}
      Contracts.save(outdated, path)
      Contracts.forget(:portolan)
      assert {:ok, ^outdated} = Contracts.fetch(:portolan)

      Contracts.save(contracts, path)
      assert request(:get, "/api/users").status == 200
    end

    test "contracts that are still outdated explain how to update them", %{
      path: path,
      contracts: contracts
    } do
      Contracts.save(%{contracts | md5: %{UserController => <<0>>}}, path)
      Contracts.forget(:portolan)

      assert_raise Plug.Conn.WrapperError, ~r/reloadable_compilers/, fn ->
        request(:get, "/api/users")
      end
    end

    test "contracts that cannot be read again", %{path: path, contracts: contracts} do
      Contracts.save(%{contracts | md5: %{UserController => <<0>>}}, path)
      Contracts.forget(:portolan)
      {:ok, _contracts} = Contracts.fetch(:portolan)
      File.rm!(path)

      assert_raise Plug.Conn.WrapperError, ~r/cannot read the Portolan contracts/, fn ->
        request(:get, "/api/users")
      end
    end
  end
end
