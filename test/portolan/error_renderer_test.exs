defmodule Portolan.ErrorRendererTest do
  # The error renderer is read from the application environment.
  use ExUnit.Case, async: false

  import Plug.Test

  alias Portolan.Compiler
  alias Portolan.Contracts
  alias Portolan.Test.AccountRouter
  alias Portolan.Test.ApiErrors

  doctest Portolan.ErrorRenderer
  doctest Portolan.EncodedFields
  doctest Portolan.Text

  @opts [
    title: "Accounts",
    version: "1.0.0",
    security_schemes: %{bearer: %{type: "http", scheme: "bearer"}, api_key: %{type: "apiKey"}}
  ]

  setup do
    path = Contracts.path(:portolan)
    backup = File.read(path)
    config = Application.get_env(:portolan, Portolan)

    {:ok, %{contracts: contracts}, _warnings} = Compiler.build(AccountRouter, @opts)
    Contracts.save(contracts, path)
    Contracts.forget(:portolan)

    on_exit(fn ->
      case backup do
        {:ok, content} -> File.write!(path, content)
        {:error, _reason} -> File.rm(path)
      end

      if config,
        do: Application.put_env(:portolan, Portolan, config),
        else: Application.delete_env(:portolan, Portolan)

      Contracts.forget(:portolan)
    end)
  end

  defp request(method, path, params \\ nil) do
    method
    |> conn(path, params)
    |> Plug.Conn.fetch_query_params()
    |> AccountRouter.call(AccountRouter.init([]))
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)

  defp use_renderer(renderer),
    do: Application.put_env(:portolan, Portolan, error_renderer: renderer)

  describe "runtime" do
    test "the default renderer follows Phoenix" do
      conn = request(:get, "/accounts/3")
      assert conn.status == 404
      assert json(conn) == %{"errors" => %{"detail" => "Not Found"}}

      conn = request(:get, "/accounts/zero")
      assert conn.status == 422
      assert %{"errors" => %{"id" => [_message]}} = json(conn)
    end

    test "errors are sent by the configured renderer" do
      use_renderer(ApiErrors)

      conn = request(:get, "/accounts/3")
      assert conn.status == 404
      assert json(conn) == %{"status" => "error", "reason" => "not_found"}
    end

    test "invalid parameters are sent by the configured renderer" do
      use_renderer(ApiErrors)

      conn = request(:get, "/accounts/zero")
      assert conn.status == 400

      assert %{"status" => "error", "reason" => "invalid", "errors" => %{"id" => [_]}} =
               json(conn)
    end

    test "changesets are sent by the configured renderer" do
      use_renderer(ApiErrors)

      conn = request(:delete, "/accounts/1")
      assert conn.status == 400
      assert json(conn)["errors"] == %{"id" => ["is in use"]}
    end
  end

  describe "document" do
    test "the schemas and the validation status come from the renderer" do
      {:ok, %{document: document}, _warnings} =
        Compiler.build(AccountRouter, Keyword.put(@opts, :error_renderer, ApiErrors))

      schemas = document["components"]["schemas"]
      assert schemas["Portolan.Error"] == ApiErrors.error_schema()
      assert schemas["Portolan.ValidationError"] == ApiErrors.validation_schema()

      responses = document["paths"]["/accounts/{id}"]["delete"]["responses"]
      assert Map.keys(responses) == ["204", "400"]

      assert responses["400"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.ValidationError"}
    end

    test "errors sharing the validation status are alternatives" do
      {:ok, %{document: document}, _warnings} =
        Compiler.build(AccountRouter, Keyword.put(@opts, :error_renderer, ApiErrors))

      response = document["paths"]["/accounts/{id}"]["get"]["responses"]["400"]

      assert response["content"]["application/json"]["schema"] == %{
               "oneOf" => [
                 %{"$ref" => "#/components/schemas/Portolan.Error"},
                 %{"$ref" => "#/components/schemas/Portolan.ValidationError"}
               ]
             }
    end

    test "the renderer must implement the behaviour" do
      assert {:error, [issue]} =
               Compiler.build(AccountRouter, Keyword.put(@opts, :error_renderer, String))

      assert issue.message =~ "String does not implement Portolan.ErrorRenderer"
    end
  end

  describe "encoded fields" do
    # Account has an owner: pid(), which cannot be documented, left out.
    test "fields left out by @derive only and except are not documented" do
      {:ok, %{document: document}, _warnings} = Compiler.build(AccountRouter, @opts)
      schemas = document["components"]["schemas"]

      assert Map.keys(schemas["Portolan.Test.Account"]["properties"]) == ["email", "id"]
      assert Map.keys(schemas["Portolan.Test.Token"]["properties"]) == ["name"]
    end

    test "nor sent" do
      assert json(request(:get, "/accounts/1")) == %{"id" => 1, "email" => "ada@example.com"}

      assert json(request(:post, "/login", %{"email" => "ada@example.com"})) == %{
               "name" => "ada@example.com"
             }
    end
  end

  describe "messages and plain text" do
    test "errors carry their message" do
      conn = request(:get, "/accounts/3/export")
      assert conn.status == 404
      assert json(conn) == %{"errors" => %{"detail" => "Account not found"}}

      use_renderer(ApiErrors)

      assert json(request(:get, "/accounts/3/export")) ==
               %{"status" => "error", "reason" => "Account not found"}
    end

    test "text is sent as text/plain" do
      conn = request(:get, "/accounts/1/export?format=text")
      assert conn.status == 200
      assert [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "text/plain"
      assert conn.resp_body == "email=ada@example.com"

      assert json(request(:get, "/accounts/1/export")) == %{
               "id" => 1,
               "email" => "ada@example.com"
             }
    end

    test "both content types are documented for the status" do
      {:ok, %{document: document}, _warnings} = Compiler.build(AccountRouter, @opts)
      responses = document["paths"]["/accounts/{id}/export"]["get"]["responses"]

      assert responses["200"]["content"] == %{
               "application/json" => %{
                 "schema" => %{"$ref" => "#/components/schemas/Portolan.Test.Account"}
               },
               "text/plain" => %{"schema" => %{"type" => "string"}}
             }

      assert responses["404"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.Error"}
    end

    test "only strings are messages" do
      assert {:error, [issue]} =
               Portolan.Action.fetch(
                 Portolan.Test.BadErrorController,
                 :show,
                 elem(Portolan.Docs.fetch(Portolan.Test.BadErrorController), 1)
               )

      assert issue.message =~ "{:not_found, String.t()}"
    end
  end

  describe "cast: false" do
    test "actions get the parameters as Phoenix gives them, once validated" do
      assert json(request(:get, "/echo?count=3")) == %{"count" => "3"}

      conn = request(:get, "/echo?count=none")
      assert conn.status == 422
    end
  end
end
