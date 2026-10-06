defmodule Mix.Tasks.Portolan.Ui.Install do
  @shortdoc "Installs a local copy of the documentation interface"

  @moduledoc """
  Installs a local copy of the files of the documentation interface, so it
  is served by the application instead of loaded from the CDN.

      mix portolan.ui.install

  The interface is the one configured with the `:ui` option of Portolan,
  see `Mix.Tasks.Compile.Portolan`. Its files are downloaded from the CDN,
  checked against the integrity Portolan was released with, and saved in a
  `portolan` directory next to the interface page, by default
  `priv/static/portolan`. Files of other versions are removed.

  Then use them with the `:ui_assets` option:

      config :my_app, Portolan,
        router: MyAppWeb.Router,
        ui_assets: :local

  Commit the installed files, so neither compiling nor showing the
  documentation needs the network. Run this task again after updating
  Portolan, the compiler reports when the installed files are not the
  expected ones.
  """

  use Mix.Task

  alias Mix.Tasks.Compile.Portolan, as: Compiler

  @compile {:no_warn_undefined, [:httpc, :public_key]}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadconfig")
    config = Application.get_env(Mix.Project.config()[:app], Portolan, [])

    case Keyword.get(config, :ui, :scalar) do
      false ->
        Mix.raise(
          "The documentation interface is disabled with ui: false, there is nothing to install"
        )

      ui ->
        install(ui, Compiler.assets_dir(config))
    end
  end

  defp install(ui, dir) do
    Mix.ensure_application!(:inets)
    Mix.ensure_application!(:ssl)
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    case Portolan.UI.install(ui, dir, &download/1) do
      {:ok, paths} -> Enum.each(paths, &Mix.shell().info("Installed #{Path.relative_to_cwd(&1)}"))
      {:error, message} -> Mix.raise(message)
    end
  end

  defp download(url) do
    request = {String.to_charlist(url), []}

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      # Accepts wildcard certificates, as *.jsdelivr.net.
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, request, [ssl: ssl, timeout: 60_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
