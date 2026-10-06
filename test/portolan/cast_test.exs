defmodule Portolan.CastTest do
  use ExUnit.Case, async: true

  alias Portolan.Cast
  alias Portolan.Fixtures.User

  doctest Portolan.Cast

  @uuid "6f1c2a7e-3b4d-4e5f-8a9b-0c1d2e3f4a5b"

  defp ok(type, value), do: Cast.cast(type, value)

  defp error(type, value) do
    assert {:error, errors} = Cast.cast(type, value)
    errors
  end

  describe "strings" do
    test "accepts binaries only" do
      assert ok({:string, nil}, "hello") == {:ok, "hello"}
      assert error({:string, nil}, 5) == [{[], "must be a string"}]
    end

    test "UUIDs are normalized to lowercase" do
      assert ok({:string, :uuid}, String.upcase(@uuid)) == {:ok, @uuid}
      assert error({:string, :uuid}, "nope") == [{[], "must be a UUID"}]
      assert error({:string, :uuid}, 1) == [{[], "must be a UUID"}]
    end

    test "dates and times" do
      assert ok({:string, :date}, "2024-01-31") == {:ok, ~D[2024-01-31]}
      assert ok({:string, :date}, ~D[2024-01-31]) == {:ok, ~D[2024-01-31]}
      assert ok({:string, :time}, "10:30:00") == {:ok, ~T[10:30:00]}

      assert ok({:string, :naive_date_time}, "2024-01-31T10:30:00") ==
               {:ok, ~N[2024-01-31T10:30:00]}

      assert ok({:string, :date_time}, "2024-01-31T12:30:00+02:00") ==
               {:ok, ~U[2024-01-31T10:30:00Z]}

      assert ok({:string, :date_time}, ~U[2024-01-31T10:30:00Z]) ==
               {:ok, ~U[2024-01-31T10:30:00Z]}

      assert [{[], "must be a date-time" <> _}] = error({:string, :date_time}, 1)
      assert error({:string, :date}, "31/01/2024") == [{[], "must be a date (YYYY-MM-DD)"}]
      assert [{[], "must be a date-time" <> _}] = error({:string, :date_time}, "2024-01-31")
      assert [{[], "must be a time" <> _}] = error({:string, :time}, 10)
    end

    test "decimals" do
      assert ok({:string, :decimal}, "1.50") == {:ok, Decimal.new("1.50")}
      assert ok({:string, :decimal}, 2) == {:ok, Decimal.new(2)}
      assert error({:string, :decimal}, "abc") == [{[], "must be a decimal number"}]
    end
  end

  describe "numbers" do
    test "integers from integers and strings" do
      assert ok({:integer, nil, nil}, 5) == {:ok, 5}
      assert ok({:integer, nil, nil}, "-5") == {:ok, -5}
      assert error({:integer, nil, nil}, "5a") == [{[], "must be an integer"}]
      assert error({:integer, nil, nil}, 5.0) == [{[], "must be an integer"}]
    end

    test "integer bounds" do
      assert ok({:integer, 1, 10}, "10") == {:ok, 10}
      assert error({:integer, 1, nil}, 0) == [{[], "must be greater than or equal to 1"}]
      assert error({:integer, nil, 10}, 11) == [{[], "must be less than or equal to 10"}]
    end

    test "floats" do
      assert ok(:float, 1.5) == {:ok, 1.5}
      assert ok(:float, 2) == {:ok, 2.0}
      assert ok(:float, "2.5") == {:ok, 2.5}
      assert error(:float, "x") == [{[], "must be a number"}]
      assert error(:float, true) == [{[], "must be a number"}]
    end

    test "numbers keep integers and floats" do
      assert ok(:number, 2) == {:ok, 2}
      assert ok(:number, "2") == {:ok, 2}
      assert ok(:number, "2.5") == {:ok, 2.5}
      assert error(:number, true) == [{[], "must be a number"}]
    end
  end

  describe "booleans, null and literals" do
    test "booleans" do
      assert ok(:boolean, true) == {:ok, true}
      assert ok(:boolean, "true") == {:ok, true}
      assert ok(:boolean, "false") == {:ok, false}
      assert error(:boolean, "yes") == [{[], "must be a boolean"}]
    end

    test "null" do
      assert ok(:null, nil) == {:ok, nil}
      assert error(:null, "") == [{[], "must be null"}]
    end

    test "literals never create atoms" do
      assert ok({:literal, :active}, "active") == {:ok, :active}
      assert ok({:literal, :active}, :active) == {:ok, :active}
      assert ok({:literal, 3}, "3") == {:ok, 3}
      assert ok({:literal, true}, "true") == {:ok, true}
      assert error({:literal, :active}, "other") == [{[], ~s(must be "active")}]
      assert error({:literal, 3}, "4") == [{[], "must be 3"}]
    end
  end

  describe "unions" do
    test "the first matching type wins" do
      type = {:union, [{:integer, nil, nil}, {:string, nil}]}
      assert ok(type, "5") == {:ok, 5}
      assert ok(type, "five") == {:ok, "five"}
      assert error(type, true) == [{[], "does not match any of the allowed types"}]
    end

    test "enums list their values" do
      type = {:union, [{:literal, :a}, {:literal, :b}, :null]}
      assert ok(type, "b") == {:ok, :b}
      assert ok(type, nil) == {:ok, nil}
      assert error(type, "c") == [{[], ~s(must be one of "a", "b" or null)}]
    end
  end

  describe "lists" do
    test "casts every item and reports the index" do
      type = {:list, {:integer, nil, nil}, false}
      assert ok(type, ["1", 2]) == {:ok, [1, 2]}
      assert ok(type, []) == {:ok, []}

      assert error(type, ["1", "x", "y"]) == [
               {[1], "must be an integer"},
               {[2], "must be an integer"}
             ]

      assert error(type, "1") == [{[], "must be a list"}]
    end

    test "nonempty lists" do
      assert error({:list, :boolean, true}, []) == [{[], "must not be empty"}]
    end
  end

  describe "maps" do
    @params {:map, [{:id, true, {:integer, 1, nil}}, {:filter, false, {:string, nil}}], nil}

    test "converts known string keys into atoms" do
      assert ok(@params, %{"id" => "7", "filter" => "x"}) == {:ok, %{id: 7, filter: "x"}}
      assert ok(@params, %{id: 7}) == {:ok, %{id: 7}}
    end

    test "drops unknown keys" do
      assert ok(@params, %{"id" => "7", "unknown" => "x"}) == {:ok, %{id: 7}}
    end

    test "reports missing and invalid fields" do
      assert error(@params, %{"filter" => 1}) ==
               [{[:id], "is required"}, {[:filter], "must be a string"}]

      assert error(@params, "id=7") == [{[], "must be an object"}]
    end

    test "additional properties keep their string keys" do
      type = {:map, [{:name, true, {:string, nil}}], {:integer, nil, nil}}

      assert ok(type, %{"name" => "a", "x" => "1", "y" => 2}) ==
               {:ok, %{:name => "a", "x" => 1, "y" => 2}}

      assert error(type, %{"name" => "a", "x" => "z"}) == [{["x"], "must be an integer"}]
    end

    test "errors in nested values carry the full path" do
      type = {:map, [{:items, true, {:list, @params, false}}], nil}

      assert error(type, %{"items" => [%{"id" => 1}, %{"id" => 0}]}) ==
               [{[:items, 1, :id], "must be greater than or equal to 1"}]
    end
  end

  describe "structs and references" do
    @user_type {:struct, User,
                [
                  {:id, true, {:string, :uuid}},
                  {:name, true, {:string, nil}},
                  {:email, true, {:union, [{:string, nil}, :null]}},
                  {:status, true, {:ref, User, :status, []}},
                  {:tags, true, {:list, {:string, nil}, false}}
                ]}

    @page {:map,
           [{:items, true, {:list, {:var, :item}, false}}, {:total, true, {:integer, 0, nil}}],
           nil}

    @user %{
      "id" => @uuid,
      "name" => "Ada",
      "status" => "active",
      "tags" => ["admin"]
    }

    defp resolve(User, :t, []), do: @user_type
    defp resolve(User, :status, []), do: {:union, [{:literal, :active}, {:literal, :inactive}]}

    defp resolve(Page, :t, [item]) do
      {:map, [{:items, true, {:list, item, false}}, {:total, true, {:integer, 0, nil}}], nil}
    end

    defp cast_ref(type, value), do: Cast.cast(type, value, resolve: &resolve/3)

    test "structs are built and references resolved" do
      assert {:ok, %User{} = user} = cast_ref({:ref, User, :t, []}, @user)
      assert user.id == @uuid
      assert user.status == :active
      assert user.email == nil
    end

    test "nullable struct fields are optional, the rest are required" do
      assert cast_ref(@user_type, Map.delete(@user, "name")) ==
               {:error, [{[:name], "is required"}]}
    end

    test "parametric references" do
      type = {:ref, Page, :t, [{:ref, User, :t, []}]}

      assert {:ok, %{items: [%User{name: "Ada"}], total: 1}} =
               cast_ref(type, %{"items" => [@user], "total" => "1"})
    end

    test "references require a resolver" do
      assert_raise ArgumentError, ~r/User.t\/0/, fn -> Cast.cast({:ref, User, :t, []}, @user) end
    end

    test "unbound variables raise" do
      assert_raise ArgumentError, ~r/item/, fn ->
        Cast.cast(@page, %{"items" => [1], "total" => 1})
      end
    end
  end
end
