defmodule WithDecimal.MixProject do
  use Mix.Project

  def project do
    [
      app: :with_decimal,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:portolan],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {WithDecimal.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.5"},
      {:ecto, "~> 3.12"},
      {:decimal, "~> 3.0"},
      {:portolan, path: "../.."}
    ]
  end
end
