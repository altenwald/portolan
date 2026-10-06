defmodule Minimal.MixProject do
  use Mix.Project

  def project do
    [
      app: :minimal,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:portolan],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Minimal.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Only Phoenix and a web server: neither Ecto nor Decimal.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.5"},
      {:portolan, path: "../.."}
    ]
  end
end
