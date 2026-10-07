defmodule Mix.Tasks.Compile.Portolan do
  @shortdoc "Generates the OpenAPI document of the API"

  @moduledoc """
  Generates the OpenAPI document of a Phoenix API as part of the
  compilation.

  Add the compiler after the default ones in `mix.exs`:

      def project do
        [
          compilers: Mix.compilers() ++ [:portolan],
          # ...
        ]
      end

  And configure it in `config/config.exs`:

      config :my_app, Portolan,
        router: MyAppWeb.Router,
        pages: ["docs/authentication.md"]

  ## Options

  * `:router` - the Phoenix router of the API (required)
  * `:title` - the title of the API, by default the `:name` of the
    project or its application name
  * `:version` - the version of the API, by default the version of the
    project
  * `:openapi` - the OpenAPI version, `"3.1"` (default) or `"3.2"`
  * `:pages` - Markdown files added as documentation pages. Each page
    must start with a level one heading, used as its title
  * `:security_schemes` - the security schemes of the API, by name, with
    their OpenAPI fields, as `%{bearer: %{type: "http", scheme: "bearer"}}`.
    See `Portolan.Security`
  * `:security` - the security requirements of every operation, as
    `[bearer: []]`, or a `{module, function}` called with the controller
    and the action name that returns them. Actions can declare their own
    with `@doc security: ...`. See `Portolan.Security`
  * `:error_renderer` - the module rendering error responses, both at
    runtime and in the document, `Portolan.ErrorRenderer.Default` by
    default. See `Portolan.ErrorRenderer`
  * `:output` - where the document is written, by default
    `"priv/static/openapi.json"`
  * `:ui` - the interface generated to read the document: `:scalar`
    (default), `:swagger_ui` or `false` for none. See `Portolan.UI`
  * `:ui_output` - where the interface is written, by default next to the
    document with the `.html` extension, `"priv/static/openapi.html"`
  * `:ui_assets` - where the interface is loaded from: `:cdn` (default) or
    `:local`, to serve a copy installed with `mix portolan.ui.install` in a
    `portolan` directory next to the interface. Remember to add it to the
    `Plug.Static` of the endpoint

  The document and the interface are static files. Serve them adding them
  to the `Plug.Static` of the endpoint, for example:

      plug Plug.Static, at: "/", from: :my_app, only: ~w(assets openapi.json openapi.html)

  The contracts used at runtime to cast the parameters are written to
  `priv/portolan/contracts.etf`. It is generated on every compilation, so it
  can be ignored by version control.

  Every problem found is reported as a compiler diagnostic. Errors stop
  the compilation. Warnings do too when compiling with
  `--warnings-as-errors`.
  """

  use Mix.Task.Compiler

  alias Mix.Task.Compiler.Diagnostic
  alias Portolan.Contracts
  alias Portolan.Issue

  @default_output "priv/static/openapi.json"

  @impl Mix.Task.Compiler
  def run(args) do
    {opts, _args, _invalid} = OptionParser.parse(args, switches: [warnings_as_errors: :boolean])
    project = Mix.Project.config()

    case Application.get_env(project[:app], Portolan) do
      nil -> {:noop, []}
      config -> compile(config, project, opts)
    end
  end

  defp compile(config, project, opts) do
    output = Keyword.get(config, :output, @default_output)

    result =
      with {:ok, router} <- check_config(config) do
        Portolan.Compiler.build(router,
          title: Keyword.get_lazy(config, :title, fn -> title(project) end),
          version: Keyword.get(config, :version, project[:version]),
          openapi: Keyword.get(config, :openapi, "3.1"),
          pages: Keyword.get(config, :pages, []),
          security_schemes: Keyword.get(config, :security_schemes),
          security: Keyword.get(config, :security),
          error_renderer: Keyword.get(config, :error_renderer, Portolan.ErrorRenderer.Default)
        )
      end

    case result do
      {:ok, %{document: document, contracts: contracts}, warnings} ->
        diagnostics = report(warnings)
        status = write(output, Portolan.OpenAPI.encode(document))
        ui_status = write_ui(config, output, document)
        Contracts.save(contracts, Contracts.relative_path())
        # A running application, as with the Phoenix code reloader, reads
        # the new contracts on its next request.
        Contracts.forget(project[:app])

        if warnings != [] and opts[:warnings_as_errors],
          do: {:error, diagnostics},
          else: {if(:ok in [status, ui_status], do: :ok, else: :noop), diagnostics}

      {:error, issues} ->
        {:error, report(issues)}
    end
  end

  defp check_config(config) do
    ui = Keyword.get(config, :ui, :scalar)
    assets = Keyword.get(config, :ui_assets, :cdn)

    issues =
      [
        Keyword.has_key?(config, :router) or "the :router option of Portolan is required",
        ui in [false | Portolan.UI.uis()] or unsupported(:ui, ui, [false | Portolan.UI.uis()]),
        assets in [:cdn, :local] or unsupported(:ui_assets, assets, [:cdn, :local]),
        ui == false or assets != :local or missing_assets(ui, config)
      ]
      |> Enum.reject(&(&1 == true))
      |> Enum.map(&Issue.error/1)

    if issues == [], do: {:ok, Keyword.fetch!(config, :router)}, else: {:error, issues}
  end

  defp unsupported(option, value, supported) do
    "unsupported #{inspect(option)} #{inspect(value)}, use one of: " <>
      Enum.map_join(supported, ", ", &inspect/1)
  end

  defp missing_assets(ui, config) do
    case Portolan.UI.missing(ui, assets_dir(config)) do
      [] ->
        true

      missing ->
        "the local files of the interface are missing (#{Enum.join(missing, ", ")}), " <>
          "run: mix portolan.ui.install"
    end
  end

  @doc false
  @spec ui_output(keyword()) :: Path.t()
  def ui_output(config) do
    Keyword.get_lazy(config, :ui_output, fn ->
      config |> Keyword.get(:output, @default_output) |> Path.rootname() |> Kernel.<>(".html")
    end)
  end

  @doc false
  @spec assets_dir(keyword()) :: Path.t()
  def assets_dir(config), do: config |> ui_output() |> Path.dirname() |> Path.join("portolan")

  defp title(project) do
    project[:name] || project[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp write_ui(config, output, document) do
    case Keyword.get(config, :ui, :scalar) do
      false ->
        :noop

      ui ->
        ui_output = ui_output(config)

        assets =
          case Keyword.get(config, :ui_assets, :cdn) do
            :cdn -> :cdn
            :local -> {:local, "portolan"}
          end

        page =
          Portolan.UI.render(ui,
            title: document["info"]["title"],
            url: relative(output, Path.dirname(ui_output)),
            assets: assets
          )

        write(ui_output, page)
    end
  end

  defp relative(path, dir),
    do: Path.relative_to(Path.expand(path), Path.expand(dir), force: true)

  defp write(output, content) do
    if File.read(output) == {:ok, content} do
      :noop
    else
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, content)
      Mix.shell().info("Generated #{output}")
      :ok
    end
  end

  defp report(issues) do
    Enum.map(issues, fn issue ->
      print(issue)

      %Diagnostic{
        compiler_name: "Portolan",
        file: issue.file && Path.expand(issue.file),
        severity: issue.severity,
        message: issue.message,
        position: issue.line || 0
      }
    end)
  end

  defp print(issue) do
    location =
      case {issue.file, issue.line} do
        {nil, _line} -> ""
        {file, nil} -> "\n  #{Path.relative_to_cwd(file)}"
        {file, line} -> "\n  #{Path.relative_to_cwd(file)}:#{line}"
      end

    color = if issue.severity == :error, do: :red, else: :yellow
    Mix.shell().error([color, "#{issue.severity}: ", :reset, issue.message, location, "\n"])
  end
end
