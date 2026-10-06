defmodule Portolan.ActionTest do
  use ExUnit.Case, async: true

  alias Portolan.Action
  alias Portolan.Action.Response
  alias Portolan.Docs
  alias Portolan.Issue
  alias Portolan.Test.BrokenController
  alias Portolan.Test.User
  alias Portolan.Test.UserController

  setup_all do
    {:ok, user_docs} = Docs.fetch(UserController)
    {:ok, broken_docs} = Docs.fetch(BrokenController)
    %{user_docs: user_docs, broken_docs: broken_docs}
  end

  defp action!(name, docs) do
    assert {:ok, %Action{} = action, []} = Action.fetch(UserController, name, docs)
    action
  end

  defp issues(name, docs) do
    assert {:error, issues} = Action.fetch(BrokenController, name, docs)
    issues
  end

  describe "fetch/3 documentation" do
    test "splits the summary and the description", %{user_docs: docs} do
      action = action!(:index, docs)
      assert action.summary == "Lists users."
      assert action.description == "Users are sorted by name."
      assert action.deprecated == nil
      assert action.line == 64
      assert action.file =~ "test/support/api.ex"
    end

    test "reads deprecations", %{user_docs: docs} do
      assert action!(:delete, docs).deprecated == "Users are deactivated instead"
    end

    test "hidden actions", %{user_docs: docs} do
      assert Action.fetch(UserController, :internal, docs) == :hidden
    end
  end

  describe "fetch/3 parameters" do
    test "the second argument of the spec", %{user_docs: docs} do
      assert action!(:show, docs).params == {:ref, UserController, :show_params, []}
    end

    test "map() parameters are not documented, with a warning", %{user_docs: docs} do
      assert {:ok, action, [warning, _response]} = Action.fetch(UserController, :export, docs)
      assert action.params == :undocumented
      assert %Issue{severity: :warning, line: 86} = warning
      assert warning.message =~ "export/2"
      assert warning.message =~ "parameters"
    end
  end

  describe "fetch/3 responses" do
    test "{:ok, type} answers 200", %{user_docs: docs} do
      assert action!(:index, docs).responses == [
               %Response{status: 200, body: {:data, {:list, {:ref, User, :t, []}, false}}}
             ]
    end

    test "errors use the status of their reason", %{user_docs: docs} do
      assert action!(:show, docs).responses == [
               %Response{status: 200, body: {:data, {:ref, User, :t, []}}},
               %Response{status: 404, body: :error}
             ]

      assert action!(:update, docs).responses == [
               %Response{status: 200, body: {:data, {:ref, User, :t, []}}},
               %Response{status: 403, body: :error},
               %Response{status: 404, body: :error}
             ]
    end

    test "any status can tag the data and changesets are validation errors", %{user_docs: docs} do
      assert action!(:create, docs).responses == [
               %Response{status: 201, body: {:data, {:ref, User, :t, []}}},
               %Response{status: 422, body: :validation}
             ]
    end

    test "bare statuses have no body", %{user_docs: docs} do
      assert action!(:delete, docs).responses == [
               %Response{status: 204, body: nil},
               %Response{status: 404, body: :error}
             ]
    end

    test "Plug.Conn.t() responses are not documented, with a warning", %{user_docs: docs} do
      assert {:ok, action, warnings} = Action.fetch(UserController, :export, docs)
      assert action.responses == :undocumented
      assert Enum.any?(warnings, &(&1.message =~ "response"))
    end
  end

  describe "fetch/3 errors" do
    test "missing @doc", %{broken_docs: docs} do
      assert [%Issue{severity: :error, message: message, line: line}] = issues(:no_docs, docs)
      assert message =~ "no_docs/2"
      assert message =~ "@doc"
      assert is_integer(line)
    end

    test "missing @spec", %{broken_docs: docs} do
      assert [%Issue{message: message}] = issues(:no_spec, docs)
      assert message =~ "@spec"
    end

    test "unknown statuses", %{broken_docs: docs} do
      assert [%Issue{message: message}] =
               Enum.filter(issues(:unknown_status, docs), &(&1.severity == :error))

      assert message =~ ":boom"
    end

    test "the first argument must be a conn", %{broken_docs: docs} do
      assert [%Issue{message: message} | _] = issues(:no_conn, docs)
      assert message =~ "Plug.Conn.t()"
    end

    test "undefined actions", %{broken_docs: docs} do
      assert {:error, [%Issue{message: message}]} = Action.fetch(BrokenController, :nope, docs)
      assert message =~ "nope/2"
    end
  end
end
