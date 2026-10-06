defmodule Mix.Tasks.Portolan.Ui.InstallTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Portolan.Ui.Install

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Application.delete_env(:portolan, Portolan) end)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "there is nothing to install without interface" do
    Application.put_env(:portolan, Portolan, ui: false)
    assert_raise Mix.Error, ~r/ui: false/, fn -> Install.run([]) end
  end

  @tag :external
  test "installs the configured interface next to it", %{tmp_dir: tmp_dir} do
    ui_output = Path.join(tmp_dir, "docs/index.html")
    Application.put_env(:portolan, Portolan, ui: :swagger_ui, ui_output: ui_output)

    Install.run([])

    assert Enum.sort(File.ls!(Path.join(tmp_dir, "docs/portolan"))) ==
             ["swagger-ui-5.33.1.css", "swagger-ui-5.33.1.js"]

    assert_received {:mix_shell, :info, ["Installed " <> _path]}
  end
end
