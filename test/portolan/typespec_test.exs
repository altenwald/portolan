defmodule Portolan.TypespecTest do
  use ExUnit.Case, async: true

  alias Portolan.Fixtures.Types
  alias Portolan.Fixtures.User
  alias Portolan.Issue
  alias Portolan.Typespec

  doctest Portolan.Typespec

  defp fetch!(name, args \\ []) do
    {:ok, type} = Typespec.fetch(Types, name, args)
    type
  end

  defp issues(name) do
    {:error, issues} = Typespec.fetch(Types, name)
    issues
  end

  describe "fetch/3 with scalar types" do
    test "strings" do
      assert fetch!(:text) == {:string, nil}
      assert fetch!(:binary_string) == {:string, nil}
    end

    test "integers keep their bounds" do
      assert fetch!(:integer_any) == {:integer, nil, nil}
      assert fetch!(:positive) == {:integer, 1, nil}
      assert fetch!(:non_negative) == {:integer, 0, nil}
      assert fetch!(:negative) == {:integer, nil, -1}
      assert fetch!(:range) == {:integer, 1, 100}
      assert fetch!(:negative_range) == {:integer, -5, 5}
    end

    test "floats, numbers and booleans" do
      assert fetch!(:float_value) == :float
      assert fetch!(:number_value) == :number
      assert fetch!(:boolean_value) == :boolean
    end

    test "literals and nil" do
      assert fetch!(:literal_atom) == {:literal, :ok}
      assert fetch!(:literal_integer) == {:literal, 3}
      assert fetch!(:literal_true) == {:literal, true}
      assert fetch!(:null) == :null
    end

    test "well-known remote types become formatted strings" do
      assert fetch!(:uuid) == {:string, :uuid}
      assert fetch!(:date) == {:string, :date}
      assert fetch!(:datetime) == {:string, :date_time}
      assert fetch!(:naive_datetime) == {:string, :naive_date_time}
      assert fetch!(:time) == {:string, :time}
      assert fetch!(:decimal) == {:string, :decimal}
    end
  end

  describe "fetch/3 with composite types" do
    test "unions" do
      assert fetch!(:nullable) == {:union, [{:integer, nil, nil}, :null]}

      assert fetch!(:enum) ==
               {:union, [{:literal, :a}, {:literal, :b}, {:literal, :c}]}
    end

    test "lists" do
      assert fetch!(:list_of) == {:list, {:integer, nil, nil}, false}
      assert fetch!(:list_call) == {:list, :boolean, false}
      assert fetch!(:nonempty) == {:list, {:string, nil}, true}
    end

    test "maps with required and optional keys" do
      assert fetch!(:params) ==
               {:map, [{:id, true, {:integer, 1, nil}}, {:filter, false, {:string, nil}}], nil}

      assert fetch!(:keyword_map) ==
               {:map, [{:name, true, {:string, nil}}, {:age, true, {:integer, 0, nil}}], nil}
    end

    test "maps with string keys become additional properties" do
      assert fetch!(:string_map) == {:map, [], {:integer, nil, nil}}
    end

    test "structs" do
      assert {:ok, {:struct, User, fields}} = Typespec.fetch(User, :t)

      assert fields == [
               {:id, true, {:string, :uuid}},
               {:name, true, {:string, nil}},
               {:email, true, {:union, [{:string, nil}, :null]}},
               {:status, true, {:ref, User, :status, []}},
               {:tags, true, {:list, {:string, nil}, false}}
             ]
    end

    test "local and remote references" do
      assert fetch!(:local_ref) == {:ref, Types, :text, []}
      assert fetch!(:remote_ref) == {:ref, User, :t, []}
    end

    test "parametric types substitute their arguments" do
      assert fetch!(:page, [:boolean]) ==
               {:map,
                [{:items, true, {:list, :boolean, false}}, {:total, true, {:integer, 0, nil}}],
                nil}

      assert fetch!(:user_page) == {:ref, Types, :page, [{:ref, User, :t, []}]}
    end
  end

  describe "fetch/3 errors" do
    test "types without an OpenAPI representation" do
      for {name, text} <- [
            any_term: "term()",
            any_value: "any()",
            any_atom: "atom()",
            any_map: "map()",
            tuple_value: "tuple",
            pid_value: "pid()",
            empty_list: "[]",
            integer_keys: "map key"
          ] do
        assert [%Issue{severity: :error, message: message, line: line}] = issues(name)
        assert message =~ text, "expected #{inspect(message)} to mention #{text}"
        assert is_integer(line)
      end
    end

    test "maps with more than one kind of string keys" do
      assert [%Issue{message: message}] = issues(:two_string_keys)
      assert message =~ "one kind of string keys"
    end

    test "invalid map keys report the key type" do
      assert [%Issue{message: message}] = issues(:invalid_key)
      assert message =~ "term()"
    end

    test "collects every issue in a type" do
      assert [%Issue{message: first}, %Issue{message: second}] = issues(:many_errors)
      assert first =~ "term()"
      assert second =~ "pid()"
    end

    test "issues point to the source file" do
      assert [%Issue{file: file}] = issues(:any_term)
      assert file =~ "test/support/fixtures.ex"
    end

    test "opaque types are rejected" do
      assert [%Issue{message: message}] = issues(:secret)
      assert message =~ "opaque"
    end

    test "unknown types and modules" do
      assert {:error, [%Issue{message: message}]} = Typespec.fetch(Types, :missing)
      assert message =~ "Portolan.Fixtures.Types.missing/0"

      assert {:error, [%Issue{message: message}]} = Typespec.fetch(Types, :page)
      assert message =~ "page/0"

      assert {:error, [%Issue{message: message}]} = Typespec.fetch(NotAModule, :t)
      assert message =~ "NotAModule"
    end
  end

  describe "to_type/2" do
    test "converts annotated types used in specs" do
      form = {:ann_type, 1, [{:var, 1, :id}, {:type, 1, :pos_integer, []}]}
      assert Typespec.to_type(form) == {:ok, {:integer, 1, nil}}
    end

    test "keeps unbound type variables" do
      assert Typespec.to_type({:var, 1, :item}) == {:ok, {:var, :item}}
    end

    test "unknown forms" do
      assert {:error, [%Issue{message: message}]} = Typespec.to_type({:char, 2, ?a})
      assert message =~ "{:char, 2, 97}"
    end

    test "local types need a module" do
      assert {:error, [%Issue{message: message}]} = Typespec.to_type({:user_type, 3, :t, []})
      assert message =~ "t/0"
    end
  end
end
