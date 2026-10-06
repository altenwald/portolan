defmodule Portolan.ContractsTest do
  use ExUnit.Case, async: false

  alias Portolan.Contracts

  @moduletag :tmp_dir

  @params {:ref, MyApp.UserController, :show_params, []}
  @show_params {:map, [{:id, true, {:integer, 1, nil}}], nil}

  defp contracts do
    %Contracts{
      actions: %{
        {MyApp.UserController, :show} => @params,
        {MyApp.UserController, :export} => :undocumented
      },
      types: %{{MyApp.UserController, :show_params, []} => @show_params},
      md5: %{MyApp.UserController => <<1, 2, 3>>}
    }
  end

  test "params/3 returns the parameters of an action" do
    assert Contracts.params(contracts(), MyApp.UserController, :show) == {:ok, @params}
    assert Contracts.params(contracts(), MyApp.UserController, :export) == {:ok, :undocumented}
    assert Contracts.params(contracts(), MyApp.UserController, :other) == :error
  end

  test "resolve/1 returns the types of references" do
    resolve = Contracts.resolve(contracts())
    assert resolve.(MyApp.UserController, :show_params, []) == @show_params
  end

  test "save/2 and read/1", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "nested/contracts.etf")
    assert Contracts.save(contracts(), path) == :ok
    assert Contracts.read(path) == {:ok, contracts()}
    assert Contracts.read(Path.join(tmp_dir, "missing")) == {:error, :enoent}
  end

  test "read/1 rejects files that are not contracts", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "other")
    File.write!(path, :erlang.term_to_binary(%{other: true}))
    assert Contracts.read(path) == {:error, :invalid}

    File.write!(path, "not a term")
    assert Contracts.read(path) == {:error, :invalid}
  end

  test "stale?/2 compares the code of the controller" do
    refute Contracts.stale?(%Contracts{md5: %{String => String.module_info(:md5)}}, String)
    assert Contracts.stale?(%Contracts{md5: %{String => <<1, 2, 3>>}}, String)
    refute Contracts.stale?(contracts(), NotDocumented)
  end

  test "path/1 is inside the priv directory of the application" do
    assert Contracts.path(:portolan) ==
             Application.app_dir(:portolan, "priv/portolan/contracts.etf")
  end

  describe "fetch/1" do
    setup do
      path = Contracts.path(:portolan)
      backup = File.read(path)
      Contracts.forget(:portolan)

      on_exit(fn ->
        case backup do
          {:ok, content} -> File.write!(path, content)
          {:error, _reason} -> File.rm(path)
        end

        Contracts.forget(:portolan)
      end)

      %{path: path}
    end

    test "loads and caches the contracts of an application", %{path: path} do
      Contracts.save(contracts(), path)
      assert Contracts.fetch(:portolan) == {:ok, contracts()}

      File.rm!(path)
      assert Contracts.fetch(:portolan) == {:ok, contracts()}
      assert Contracts.reload(:portolan) == {:error, :enoent}
    end

    test "missing contracts", %{path: path} do
      File.rm(path)
      assert Contracts.fetch(:portolan) == {:error, :enoent}
    end
  end
end
