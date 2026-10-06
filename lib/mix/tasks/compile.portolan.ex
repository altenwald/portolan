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
  * `:output` - where the document is written, by default
    `"priv/static/openapi.json"`
  * `:ui` - the interface generated to read the document: `:scalar`
    (default), `:swagger_ui` or `false` for none. See `Portolan.UI`
  * `:ui_output` - where the interface is written, by default next to the
    document with the `.html` extension, `"priv/static/openapi.html"`

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
    ui = Keyword.get(config, :ui, :scalar)

    result =
      case {Keyword.fetch(config, :router), ui in [false | Portolan.UI.uis()]} do
        {_router, false} ->
          message =
            "unsupported :ui #{inspect(ui)}, use one of: " <>
              Enum.map_join([false | Portolan.UI.uis()], ", ", &inspect/1)

          {:error, [Issue.error(message)]}

        {{:ok, router}, true} ->
          Portolan.Compiler.build(router,
            title: Keyword.get_lazy(config, :title, fn -> title(project) end),
            version: Keyword.get(config, :version, project[:version]),
            openapi: Keyword.get(config, :openapi, "3.1"),
            pages: Keyword.get(config, :pages, [])
          )

        {:error, true} ->
          {:error, [Issue.error("the :router option of Portolan is required")]}
      end

    case result do
      {:ok, %{document: document, contracts: contracts}, warnings} ->
        diagnostics = report(warnings)
        status = write(output, Portolan.OpenAPI.encode(document))
        ui_status = write_ui(ui, config, output, document)
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

  defp title(project) do
    project[:name] || project[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp write_ui(false, _config, _output, _document), do: :noop

  defp write_ui(ui, config, output, document) do
    ui_output = Keyword.get(config, :ui_output, Path.rootname(output) <> ".html")
    url = Path.relative_to(Path.expand(output), Path.expand(Path.dirname(ui_output)), force: true)
    write(ui_output, Portolan.UI.render(ui, title: document["info"]["title"], url: url))
  end

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
