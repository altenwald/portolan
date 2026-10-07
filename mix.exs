defmodule Portolan.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/altenwald/portolan"

  def project do
    [
      app: :portolan,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [
        summary: [threshold: 95],
        ignore_modules: [~r/^Portolan\.(Fixtures|Test)\./]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:decimal, "~> 3.0", optional: true},
      {:ecto, "~> 3.10", optional: true},
      {:ex_check, "~> 0.17", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "OpenAPI documentation for Phoenix built from what your code already says: " <>
      "typespecs, docs and routes."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib assets mix.exs README* CHANGELOG* LICENSE* .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      assets: %{"assets" => "assets"},
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/existing-api.md",
        "guides/embedding-scalar.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [Guides: ~r{guides/}],
      groups_for_modules: [
        "Phoenix integration": [
          Portolan.Controller,
          Portolan.Response,
          Portolan.Text,
          Portolan.ErrorRenderer,
          Portolan.ErrorRenderer.Default,
          Portolan.Security,
          Portolan.SharedResponses,
          Portolan.Contracts
        ],
        Compiler: [
          Portolan.Compiler,
          Portolan.Action,
          Portolan.Action.Response,
          Portolan.Docs,
          Portolan.Docs.Entry,
          Portolan.FieldDocs
        ],
        "OpenAPI document": [Portolan.OpenAPI, ~r/^Portolan.OpenAPI./, Portolan.UI],
        "Type conversion": [
          Portolan.Type,
          Portolan.Typespec,
          Portolan.EncodedFields,
          Portolan.JSONSchema,
          Portolan.Cast
        ],
        Diagnostics: [Portolan.Issue]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit, :decimal, :ecto, :inets, :ssl, :public_key],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [:error_handling, :extra_return, :missing_return, :underspecs, :unmatched_returns]
    ]
  end
end
