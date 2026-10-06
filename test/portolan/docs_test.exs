defmodule Portolan.DocsTest do
  use ExUnit.Case, async: true

  alias Portolan.Docs
  alias Portolan.Issue
  alias Portolan.Test.BrokenController
  alias Portolan.Test.User
  alias Portolan.Test.UserController

  import Portolan.Test.Source, only: [line: 1]

  doctest Portolan.Docs

  describe "fetch/1" do
    test "reads the module documentation" do
      assert {:ok, docs} = Docs.fetch(UserController)

      assert docs.moduledoc.text ==
               "Users of the application.\n\nUsers can be listed, created and removed.\n"

      assert docs.moduledoc.line == line("defmodule Portolan.Test.UserController")
      assert docs.file =~ "test/support/api.ex"
    end

    test "reads function documentation with the line of the definition" do
      {:ok, docs} = Docs.fetch(UserController)

      assert %Docs.Entry{text: "Fetches a user.", deprecated: nil} = docs.functions[{:show, 2}]
      assert docs.functions[{:show, 2}].line == line("def show(_conn, %{id: id})")

      assert docs.functions[{:delete, 2}].deprecated == "Users are deactivated instead"
      assert docs.functions[{:internal, 2}].text == :hidden
    end

    test "functions without docs" do
      {:ok, docs} = Docs.fetch(BrokenController)
      assert docs.functions[{:no_docs, 2}].text == :none
    end

    test "reads type documentation" do
      {:ok, docs} = Docs.fetch(User)
      assert docs.types[{:role, 0}].text == "What a user is allowed to do."
      assert docs.types[{:role, 0}].line == line("@type role ::")
      assert docs.types[{:legacy_role, 0}].deprecated == "Use role/0"
    end

    test "types without docs" do
      {:ok, docs} = Docs.fetch(BrokenController)
      assert docs.types[{:untyped_params, 0}].text == :none
    end

    test "modules without docs" do
      assert {:error, [%Issue{message: message}]} = Docs.fetch(NotAModule)
      assert message =~ "NotAModule"
    end
  end

  describe "split/1" do
    test "the first paragraph is the summary" do
      assert Docs.split("Lists users.\n\nSorted by name.\n\nPaginated.\n") ==
               {"Lists users.", "Sorted by name.\n\nPaginated."}
    end

    test "single paragraphs have no description" do
      assert Docs.split("Lists users.\n") == {"Lists users.", nil}
      assert Docs.split("Lists\nusers.") == {"Lists\nusers.", nil}
    end
  end
end
