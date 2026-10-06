defmodule Portolan.OpenAPITest do
  use ExUnit.Case, async: true

  alias Portolan.OpenAPI
  alias Portolan.OpenAPI.Operation
  alias Portolan.OpenAPI.Parameter
  alias Portolan.OpenAPI.Response
  alias Portolan.OpenAPI.Schema
  alias Portolan.OpenAPI.Tag

  doctest Portolan.OpenAPI

  @user {:ref, MyApp.User, :t, []}

  defp spec(attrs \\ []) do
    struct!(
      OpenAPI,
      Keyword.merge(
        [
          version: "3.1",
          title: "My App",
          api_version: "1.0.0",
          description: "The API.",
          tags: [
            %Tag{name: "Authentication", description: "Use a token.", page: true},
            %Tag{name: "User", summary: "Users.", description: "Users.\n\nMore."}
          ],
          operations: [
            %Operation{
              method: :get,
              path: "/users/{id}",
              operation_id: "User.show",
              tag: "User",
              summary: "Fetches a user.",
              description: "Long.",
              parameters: [
                %Parameter{
                  name: "id",
                  in: :path,
                  required: true,
                  type: {:string, :uuid},
                  description: "The id."
                },
                %Parameter{name: "include", in: :query, required: false, type: :boolean}
              ],
              responses: [
                %Response{status: 200, body: {:type, @user}},
                %Response{status: 404, body: {:component, "Portolan.Error"}}
              ]
            },
            %Operation{
              method: :post,
              path: "/users",
              operation_id: "User.create",
              tag: "User",
              summary: "Creates a user.",
              deprecated: "Use v2",
              request_body: {:map, [{:name, true, {:string, nil}}], nil},
              responses: [%Response{status: 204, body: nil}]
            },
            %Operation{
              method: :get,
              path: "/export",
              operation_id: "User.export",
              tag: "User",
              summary: "Exports.",
              responses: :undocumented
            }
          ],
          schemas: %{
            "MyApp.User" => %Schema{
              type:
                {:struct, MyApp.User,
                 [{:id, true, {:string, :uuid}}, {:role, true, {:ref, MyApp.User, :role, []}}]},
              description: "A user.",
              fields: %{"id" => "Unique.", "role" => "What they can do."}
            },
            "MyApp.User.role" => %Schema{
              type: {:union, [{:literal, :admin}, {:literal, :member}]},
              deprecated: true
            },
            "Portolan.Error" => %Schema{json: %{"type" => "object"}}
          }
        ],
        attrs
      )
    )
  end

  describe "build/1" do
    test "info" do
      document = OpenAPI.build(spec())
      assert document["openapi"] == "3.1.1"

      assert document["info"] == %{
               "title" => "My App",
               "version" => "1.0.0",
               "description" => "The API."
             }
    end

    test "operations grouped by path and method" do
      document = OpenAPI.build(spec())
      show = document["paths"]["/users/{id}"]["get"]

      assert show["operationId"] == "User.show"
      assert show["tags"] == ["User"]
      assert show["summary"] == "Fetches a user."
      assert show["description"] == "Long."
      refute Map.has_key?(show, "deprecated")

      assert show["parameters"] == [
               %{
                 "name" => "id",
                 "in" => "path",
                 "required" => true,
                 "description" => "The id.",
                 "schema" => %{"type" => "string", "format" => "uuid"}
               },
               %{
                 "name" => "include",
                 "in" => "query",
                 "required" => false,
                 "schema" => %{"type" => "boolean"}
               }
             ]
    end

    test "responses" do
      responses = OpenAPI.build(spec())["paths"]["/users/{id}"]["get"]["responses"]

      assert responses["200"] == %{
               "description" => "OK",
               "content" => %{
                 "application/json" => %{
                   "schema" => %{"$ref" => "#/components/schemas/MyApp.User"}
                 }
               }
             }

      assert responses["404"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.Error"}

      assert OpenAPI.build(spec())["paths"]["/users"]["post"]["responses"] ==
               %{"204" => %{"description" => "No Content"}}

      assert OpenAPI.build(spec())["paths"]["/export"]["get"]["responses"] ==
               %{"default" => %{"description" => "The response is not documented."}}
    end

    test "request bodies and deprecations" do
      create = OpenAPI.build(spec())["paths"]["/users"]["post"]

      assert create["requestBody"] == %{
               "required" => true,
               "content" => %{
                 "application/json" => %{
                   "schema" => %{
                     "type" => "object",
                     "properties" => %{"name" => %{"type" => "string"}},
                     "required" => ["name"]
                   }
                 }
               }
             }

      assert create["deprecated"] == true
      assert create["description"] == "**Deprecated:** Use v2"
    end

    test "component schemas with field descriptions" do
      schemas = OpenAPI.build(spec())["components"]["schemas"]

      assert schemas["MyApp.User"] == %{
               "type" => "object",
               "description" => "A user.",
               "properties" => %{
                 "id" => %{"type" => "string", "format" => "uuid", "description" => "Unique."},
                 "role" => %{
                   "$ref" => "#/components/schemas/MyApp.User.role",
                   "description" => "What they can do."
                 }
               },
               "required" => ["id", "role"]
             }

      assert schemas["MyApp.User.role"] == %{"enum" => ["admin", "member"], "deprecated" => true}
      assert schemas["Portolan.Error"] == %{"type" => "object"}
    end

    test "tags in 3.1 keep pages as plain tags" do
      assert OpenAPI.build(spec())["tags"] == [
               %{"name" => "Authentication", "description" => "Use a token."},
               %{"name" => "User", "description" => "Users.\n\nMore."}
             ]
    end

    test "tags in 3.2 mark pages for navigation and use summaries" do
      document = OpenAPI.build(spec(version: "3.2"))
      assert document["openapi"] == "3.2.0"

      assert document["tags"] == [
               %{"name" => "Authentication", "description" => "Use a token.", "kind" => "nav"},
               %{"name" => "User", "summary" => "Users.", "description" => "Users.\n\nMore."}
             ]
    end

    test "optional parts are left out" do
      document = OpenAPI.build(spec(description: nil, tags: [], schemas: %{}, operations: []))
      assert document["info"] == %{"title" => "My App", "version" => "1.0.0"}
      assert document["paths"] == %{}
      refute Map.has_key?(document, "tags")
      refute Map.has_key?(document, "components")
    end
  end

  describe "encode/1" do
    test "pretty prints with sorted keys" do
      assert OpenAPI.encode(%{"b" => nil, "a" => [1, true]}) ==
               ~s({\n  "a": [1,true],\n  "b": null\n}\n)
    end
  end

  describe "component_name/3" do
    test "names t/0 after the module" do
      assert OpenAPI.component_name(MyApp.User, :t, []) == "MyApp.User"
      assert OpenAPI.component_name(MyApp.User, :status, []) == "MyApp.User.status"
    end

    test "includes the arguments of parametric types" do
      assert OpenAPI.component_name(MyApp.Page, :t, [@user]) == "MyApp.Page_MyApp.User"

      assert OpenAPI.component_name(MyApp.Page, :t, [{:string, nil}, {:list, :boolean, false}]) ==
               "MyApp.Page_string_list_boolean"

      assert OpenAPI.component_name(MyApp.Page, :t, [
               {:union, [{:literal, :a}, :null]},
               {:map, [], nil},
               {:struct, MyApp.User, []},
               {:integer, 1, nil},
               {:string, :uuid}
             ]) == "MyApp.Page_a_or_null_map_MyApp.User_integer_uuid"
    end
  end
end
