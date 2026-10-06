defmodule Portolan.CompilerTest do
  use ExUnit.Case, async: true

  alias Portolan.Compiler
  alias Portolan.Issue
  alias Portolan.Test.BrokenRouter
  alias Portolan.Test.EdgeRouter
  alias Portolan.Test.Router
  alias Portolan.Test.UserController

  @opts [title: "Test API", version: "1.2.3"]

  defp build!(opts \\ []) do
    assert {:ok, %{document: document}, warnings} =
             Compiler.build(Router, Keyword.merge(@opts, opts))

    {document, warnings}
  end

  defp errors(router, opts \\ []) do
    assert {:error, issues} = Compiler.build(router, Keyword.merge(@opts, opts))
    Enum.filter(issues, &(&1.severity == :error))
  end

  describe "build/2 document" do
    test "info comes from the options and the router documentation" do
      {document, _warnings} = build!()
      assert document["openapi"] == "3.1.1"

      assert document["info"] == %{
               "title" => "Test API",
               "version" => "1.2.3",
               "description" => "The example API.\n\nUsed to test Portolan.\n"
             }
    end

    test "only routes of Portolan controllers, without hidden actions" do
      {document, _warnings} = build!()

      assert document["paths"] |> Map.keys() |> Enum.sort() ==
               ["/api/users", "/api/users/export", "/api/users/{id}"]

      assert document["paths"]["/api/users/{id}"] |> Map.keys() |> Enum.sort() ==
               ["delete", "get", "patch", "put"]
    end

    test "operations are documented from the actions" do
      {document, _warnings} = build!()
      show = document["paths"]["/api/users/{id}"]["get"]

      assert show["operationId"] == "UserController.show"
      assert show["tags"] == ["User"]
      assert show["summary"] == "Fetches a user."

      assert show["parameters"] == [
               %{
                 "name" => "id",
                 "in" => "path",
                 "required" => true,
                 "description" => "the user identifier",
                 "schema" => %{"type" => "string", "format" => "uuid"}
               }
             ]

      assert show["responses"]["200"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.Test.User"}

      assert show["responses"]["404"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.Error"}

      assert show["responses"]["422"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.ValidationError"}
    end

    test "query parameters for reads" do
      {document, _warnings} = build!()
      index = document["paths"]["/api/users"]["get"]

      assert index["parameters"] == [
               %{
                 "name" => "role",
                 "in" => "query",
                 "required" => false,
                 "description" => "only users with this role",
                 "schema" => %{"$ref" => "#/components/schemas/Portolan.Test.User.role"}
               },
               %{
                 "name" => "page",
                 "in" => "query",
                 "required" => false,
                 "description" => "page number, starting at 1",
                 "schema" => %{"type" => "integer", "minimum" => 1}
               }
             ]
    end

    test "request bodies for writes" do
      {document, _warnings} = build!()
      create = document["paths"]["/api/users"]["post"]

      refute Map.has_key?(create, "parameters")

      assert create["requestBody"]["content"]["application/json"]["schema"] == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "email" => %{"type" => "string"}
               },
               "required" => ["name"]
             }

      assert Map.keys(create["responses"]) == ["201", "422"]

      update = document["paths"]["/api/users/{id}"]["put"]
      assert [%{"name" => "id", "in" => "path"}] = update["parameters"]
      assert update["requestBody"]["required"] == false
    end

    test "operation ids are unique" do
      {document, _warnings} = build!()
      update = document["paths"]["/api/users/{id}"]

      assert {update["patch"]["operationId"], update["put"]["operationId"]} ==
               {"UserController.update", "UserController.update_put"}
    end

    test "deprecated actions" do
      {document, _warnings} = build!()
      assert document["paths"]["/api/users/{id}"]["delete"]["deprecated"] == true
    end

    test "classic actions are documented with warnings" do
      {document, warnings} = build!()
      export = document["paths"]["/api/users/export"]["get"]

      assert export["responses"] == %{
               "default" => %{"description" => "The response is not documented."}
             }

      refute Map.has_key?(export, "parameters")
      assert [%Issue{severity: :warning}, %Issue{severity: :warning}] = warnings
    end

    test "component schemas are resolved with their documentation" do
      {document, _warnings} = build!()
      schemas = document["components"]["schemas"]

      assert schemas |> Map.keys() |> Enum.sort() == [
               "Portolan.Error",
               "Portolan.Test.User",
               "Portolan.Test.User.role",
               "Portolan.ValidationError"
             ]

      user = schemas["Portolan.Test.User"]
      assert user["description"] == "A user of the application."
      assert user["properties"]["id"]["description"] == "unique identifier"
      assert user["properties"]["role"]["$ref"] == "#/components/schemas/Portolan.Test.User.role"

      assert schemas["Portolan.Test.User.role"] == %{
               "enum" => ["admin", "member"],
               "description" => "What a user is allowed to do."
             }
    end

    test "tags come from the controllers" do
      {document, _warnings} = build!()

      assert document["tags"] == [
               %{
                 "name" => "User",
                 "description" =>
                   "Users of the application.\n\nUsers can be listed, created and removed."
               }
             ]
    end

    test "pages become tags before the controllers" do
      {document, _warnings} = build!(pages: ["test/fixtures/pages/auth.md"], openapi: "3.2")

      assert [page, controller] = document["tags"]

      assert page == %{
               "name" => "Authentication",
               "description" => "Send the token in the `Authorization` header.",
               "kind" => "nav"
             }

      assert controller["summary"] == "Users of the application."
    end
  end

  describe "build/2 contracts" do
    test "keep the parameters of documented actions with their types resolved" do
      assert {:ok, %{contracts: contracts}, _warnings} = Compiler.build(Router, @opts)

      assert contracts.actions[{UserController, :show}] ==
               {:ref, UserController, :show_params, []}

      assert contracts.actions[{UserController, :export}] == :undocumented
      refute Map.has_key?(contracts.actions, {UserController, :internal})

      assert contracts.types[{UserController, :index_params, []}] ==
               {:map,
                [
                  {:role, false, {:ref, Portolan.Test.User, :role, []}},
                  {:page, false, {:integer, 1, nil}}
                ], nil}

      assert contracts.types[{Portolan.Test.User, :role, []}] ==
               {:union, [{:literal, :admin}, {:literal, :member}]}

      assert contracts.md5 == %{UserController => UserController.module_info(:md5)}
    end
  end

  describe "build/2 edge cases" do
    setup do
      assert {:ok, %{document: document}, warnings} = Compiler.build(EdgeRouter, @opts)
      %{paths: document["paths"], schemas: document["components"]["schemas"], warnings: warnings}
    end

    test "glob paths and struct parameters", %{paths: paths} do
      file = paths["/files/{path}"]["get"]

      assert [
               %{
                 "name" => "path",
                 "in" => "path",
                 "description" => "the segments of the file path"
               }
             ] =
               file["parameters"]
    end

    test "responses with the same status are merged", %{paths: paths} do
      schema =
        paths["/files/{path}"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]

      assert [%{"$ref" => _}, %{"type" => "array"}] = schema["anyOf"]
    end

    test "types with @typedoc false have no description", %{schemas: schemas} do
      refute Map.has_key?(schemas["Portolan.Test.Item"], "description")
    end

    test "inline parameters and lists in the query", %{paths: paths} do
      assert [
               %{"name" => "tags", "schema" => %{"type" => "array"}},
               %{"name" => "limit", "required" => true}
             ] =
               paths["/search"]["get"]["parameters"]
    end

    test "bodies with additional properties", %{paths: paths} do
      upload = paths["/upload"]["post"]
      assert upload["requestBody"]["required"] == false
      assert Map.keys(upload["responses"]) == ["202", "422"]
    end

    test "undocumented parameters keep the path parameters", %{paths: paths, warnings: warnings} do
      assert [%{"name" => "id", "in" => "path", "schema" => %{"type" => "string"}}] =
               paths["/legacy/{id}"]["get"]["parameters"]

      assert length(warnings) == 2
    end

    test "controllers with @moduledoc false are hidden", %{paths: paths} do
      refute Map.has_key?(paths, "/hidden")
    end
  end

  describe "build/2 errors" do
    test "every problem of the API is reported" do
      messages = BrokenRouter |> errors() |> Enum.map(& &1.message)

      for expected <- [
            ~r/no_docs\/2 needs a @doc/,
            ~r/no_spec\/2 needs a @spec/,
            ~r/term\(\)/,
            ~r/untyped_params\/0 needs a @typedoc/,
            ~r/:boom/,
            ~r/no_conn\/2 must be Plug.Conn.t\(\)/,
            ~r/documents the field ghost/,
            ~r/path parameter slug/,
            ~r/UndocumentedController needs a @moduledoc/,
            ~r/mixed_conn\/2 cannot mix Plug.Conn.t\(\)/,
            ~r/unsupported response in .*bare_type\/2/,
            ~r/unsupported error in .*bad_error\/2/,
            ~r/mixed_bodies\/2 returns different kinds of bodies for the status 200/,
            ~r/guarded\/2 must have a single @spec clause/,
            ~r/parameters of .*scalar_params\/2 must be a map/,
            ~r/query parameter filter of .*map_query\/2/,
            ~r/Portolan.Fixtures.Types.any_term\/0 needs a @typedoc/
          ] do
        assert Enum.any?(messages, &(&1 =~ expected)),
               "expected an error matching #{inspect(expected)} in:\n#{Enum.join(messages, "\n")}"
      end
    end

    test "issues point to files and lines" do
      for issue <- errors(BrokenRouter) do
        assert issue.file =~ "test/support/", "missing file in #{inspect(issue)}"
        assert is_integer(issue.line), "missing line in #{inspect(issue)}"
      end
    end

    test "invalid options" do
      assert [%Issue{message: message}] = errors(Router, openapi: "2.0")
      assert message =~ "3.1"

      assert [%Issue{message: message}] = errors(NotARouter)
      assert message =~ "NotARouter"
    end

    test "missing pages" do
      assert [%Issue{file: "missing.md", message: message}] =
               errors(Router, pages: ["missing.md"])

      assert message =~ "cannot read"
    end

    test "pages without a heading" do
      assert [%Issue{message: message}] =
               errors(Router, pages: ["test/fixtures/pages/no_heading.md"])

      assert message =~ "heading"
    end
  end
end
