defmodule Portolan.JSONSchemaTest do
  use ExUnit.Case, async: true

  alias Portolan.JSONSchema

  doctest Portolan.JSONSchema

  defp schema(type, opts \\ []), do: JSONSchema.from_type(type, opts)

  describe "from_type/2 with scalars" do
    test "strings and their formats" do
      assert schema({:string, nil}) == %{"type" => "string"}
      assert schema({:string, :uuid}) == %{"type" => "string", "format" => "uuid"}
      assert schema({:string, :date}) == %{"type" => "string", "format" => "date"}
      assert schema({:string, :date_time}) == %{"type" => "string", "format" => "date-time"}
      assert schema({:string, :decimal}) == %{"type" => "string", "format" => "decimal"}
    end

    test "formats without a standard name get an example" do
      assert schema({:string, :naive_date_time}) ==
               %{"type" => "string", "examples" => ["2024-01-31T10:30:00"]}

      assert schema({:string, :time}) == %{"type" => "string", "examples" => ["10:30:00"]}
    end

    test "integers and their bounds" do
      assert schema({:integer, nil, nil}) == %{"type" => "integer"}
      assert schema({:integer, 1, nil}) == %{"type" => "integer", "minimum" => 1}
      assert schema({:integer, nil, -1}) == %{"type" => "integer", "maximum" => -1}

      assert schema({:integer, 1, 100}) ==
               %{"type" => "integer", "minimum" => 1, "maximum" => 100}
    end

    test "numbers, booleans and null" do
      assert schema(:float) == %{"type" => "number", "format" => "double"}
      assert schema(:number) == %{"type" => "number"}
      assert schema(:boolean) == %{"type" => "boolean"}
      assert schema(:null) == %{"type" => "null"}
    end

    test "literals" do
      assert schema({:literal, :active}) == %{"const" => "active"}
      assert schema({:literal, 3}) == %{"const" => 3}
      assert schema({:literal, true}) == %{"const" => true}
    end
  end

  describe "from_type/2 with unions" do
    test "literals become an enum" do
      assert schema({:union, [{:literal, :a}, {:literal, :b}]}) == %{"enum" => ["a", "b"]}
    end

    test "nullable enums include null" do
      assert schema({:union, [{:literal, :a}, {:literal, :b}, :null]}) ==
               %{"enum" => ["a", "b", nil]}
    end

    test "nullable simple types use a type list" do
      assert schema({:union, [{:integer, 1, nil}, :null]}) ==
               %{"type" => ["integer", "null"], "minimum" => 1}
    end

    test "other unions use anyOf" do
      assert schema({:union, [{:string, nil}, {:integer, nil, nil}]}) ==
               %{"anyOf" => [%{"type" => "string"}, %{"type" => "integer"}]}

      assert schema({:union, [{:string, nil}, {:integer, nil, nil}, :null]}) ==
               %{
                 "anyOf" => [
                   %{"type" => "string"},
                   %{"type" => "integer"},
                   %{"type" => "null"}
                 ]
               }
    end

    test "nested unions are flattened" do
      assert schema({:union, [{:literal, :a}, {:union, [{:literal, :b}, :null]}]}) ==
               %{"enum" => ["a", "b", nil]}
    end
  end

  describe "from_type/2 with collections" do
    test "lists" do
      assert schema({:list, :boolean, false}) ==
               %{"type" => "array", "items" => %{"type" => "boolean"}}

      assert schema({:list, :boolean, true}) ==
               %{"type" => "array", "items" => %{"type" => "boolean"}, "minItems" => 1}
    end

    test "maps list their required properties" do
      type = {:map, [{:id, true, {:integer, 1, nil}}, {:filter, false, {:string, nil}}], nil}

      assert schema(type) == %{
               "type" => "object",
               "properties" => %{
                 "id" => %{"type" => "integer", "minimum" => 1},
                 "filter" => %{"type" => "string"}
               },
               "required" => ["id"]
             }
    end

    test "maps without required properties" do
      assert schema({:map, [{:a, false, :boolean}], nil}) == %{
               "type" => "object",
               "properties" => %{"a" => %{"type" => "boolean"}}
             }
    end

    test "maps with additional properties" do
      assert schema({:map, [], :number}) ==
               %{"type" => "object", "additionalProperties" => %{"type" => "number"}}
    end

    test "structs require every field" do
      type = {:struct, Foo, [{:a, true, :boolean}, {:b, true, {:union, [:boolean, :null]}}]}

      assert schema(type) == %{
               "type" => "object",
               "properties" => %{
                 "a" => %{"type" => "boolean"},
                 "b" => %{"type" => ["boolean", "null"]}
               },
               "required" => ["a", "b"]
             }
    end
  end

  describe "from_type/2 with references" do
    test "are resolved by the caller" do
      ref = fn MyApp.User, :t, [] -> %{"$ref" => "#/$defs/user"} end

      assert schema({:union, [{:ref, MyApp.User, :t, []}, :null]}, ref: ref) ==
               %{"anyOf" => [%{"$ref" => "#/$defs/user"}, %{"type" => "null"}]}
    end

    test "require a resolver" do
      assert_raise ArgumentError, ~r/MyApp.User.t\/0/, fn ->
        schema({:ref, MyApp.User, :t, []})
      end
    end

    test "unbound variables cannot be converted" do
      assert_raise ArgumentError, ~r/item/, fn -> schema({:var, :item}) end
    end
  end
end
