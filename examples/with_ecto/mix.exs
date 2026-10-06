defmodule WithEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :with_ecto,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:portolan],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {WithEcto.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Ecto without a database: schemas and changesets only.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.5"},
      {:ecto, "~> 3.12"},
      {:portolan, path: "../.."}
    ]
  end
end
