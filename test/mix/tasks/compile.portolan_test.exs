defmodule Mix.Tasks.Compile.PortolanTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Task.Compiler.Diagnostic
  alias Mix.Tasks.Compile.Portolan, as: Task

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Application.delete_env(:portolan, Portolan) end)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{output: Path.join(tmp_dir, "openapi.json")}
  end

  defp configure(config), do: Application.put_env(:portolan, Portolan, config)

  test "does nothing without configuration" do
    assert Task.run([]) == {:noop, []}
  end

  test "writes the document", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, title: "Test")

    assert {:ok, diagnostics} = Task.run([])
    assert [%Diagnostic{severity: :warning, compiler_name: "Portolan"} | _] = diagnostics
    assert_received {:mix_shell, :info, ["Generated " <> _path]}

    document = output |> File.read!() |> JSON.decode!()

    assert document["info"] == %{
             "title" => "Test",
             "version" => "0.1.0",
             "description" => "The example API.\n\nUsed to test Portolan.\n"
           }

    assert {:ok, %Portolan.Contracts{}} = Portolan.Contracts.read("priv/portolan/contracts.etf")
    assert {:noop, _diagnostics} = Task.run([])
  end

  test "writes the Scalar interface next to the document by default", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, title: "Test")
    Task.run([])

    html = output |> Path.rootname() |> Kernel.<>(".html") |> File.read!()
    assert html =~ "<title>Test</title>"
    assert html =~ "@scalar/api-reference"
    assert html =~ ~s("url":"openapi.json")
  end

  test "writes Swagger UI where configured", %{output: output, tmp_dir: tmp_dir} do
    ui_output = Path.join(tmp_dir, "docs/index.html")
    configure(router: Portolan.Test.Router, output: output, ui: :swagger_ui, ui_output: ui_output)
    Task.run([])

    html = File.read!(ui_output)
    assert html =~ "swagger-ui-dist"
    assert html =~ ~s("url":"../openapi.json")
  end

  test "the interface can be disabled", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, ui: false)
    assert {:ok, _diagnostics} = Task.run([])
    refute File.exists?(Path.rootname(output) <> ".html")
  end

  test "unsupported interfaces", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, ui: :redoc)
    assert {:error, [%Diagnostic{message: message}]} = Task.run([])
    assert message =~ ":redoc"
    assert message =~ ":swagger_ui"
  end

  test "local assets must be installed", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, ui: :swagger_ui, ui_assets: :local)

    assert {:error, [%Diagnostic{message: message}]} = Task.run([])
    assert message =~ "swagger-ui-5.33.1.css, swagger-ui-5.33.1.js"
    assert message =~ "mix portolan.ui.install"
  end

  test "installed local assets are used", %{output: output, tmp_dir: tmp_dir} do
    configure(router: Portolan.Test.Router, output: output, ui_assets: :local)
    File.mkdir_p!(Path.join(tmp_dir, "portolan"))
    File.write!(Path.join(tmp_dir, "portolan/scalar-1.73.0.js"), "")

    assert {:ok, _diagnostics} = Task.run([])
    html = File.read!(Path.join(tmp_dir, "openapi.html"))
    assert html =~ ~s(src="portolan/scalar-1.73.0.js")
    refute html =~ "cdn.jsdelivr.net"
  end

  test "unsupported asset locations", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, ui_assets: :s3)
    assert {:error, [%Diagnostic{message: message}]} = Task.run([])
    assert message =~ ":ui_assets :s3"
  end

  test "uses the project name by default", %{output: output} do
    configure(router: Portolan.Test.Router, output: output)
    Task.run([])
    assert JSON.decode!(File.read!(output))["info"]["title"] == "Portolan"
  end

  test "warnings as errors", %{output: output} do
    configure(router: Portolan.Test.Router, output: output)
    assert {:error, [_ | _]} = Task.run(["--warnings-as-errors"])
  end

  test "reports errors as diagnostics", %{output: output} do
    configure(router: Portolan.Test.BrokenRouter, output: output)

    assert {:error, diagnostics} = Task.run([])
    refute File.exists?(output)

    assert Enum.all?(diagnostics, &(&1.file =~ "test/support/"))
    assert Enum.all?(diagnostics, &(&1.position > 0))

    assert_received {:mix_shell, :error, ["error: " <> message]}
    assert message =~ ~r/\n  test\/support\/\w+.ex:\d+\n$/
  end

  test "requires a router" do
    configure(output: "unused.json")
    assert {:error, [%Diagnostic{message: message, file: nil}]} = Task.run([])
    assert message =~ ":router"
    assert_received {:mix_shell, :error, ["error: the :router option of Portolan is required\n"]}
  end

  test "prints issues without line", %{output: output} do
    configure(router: Portolan.Test.Router, output: output, pages: ["missing.md"])
    assert {:error, _diagnostics} = Task.run([])

    assert_received {:mix_shell, :error, ["error: cannot read the page: " <> message]}
    assert String.ends_with?(message, "\n  missing.md\n")
  end

  test "is documented" do
    assert capture_io(fn -> Mix.Task.run("help", ["compile.portolan"]) end) =~ "OpenAPI"
  end
end
