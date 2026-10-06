import Config

config :with_ecto, WithEctoWeb.Endpoint,
  http: [port: 4000],
  server: true,
  code_reloader: true,
  reloadable_compilers: [:elixir, :app, :portolan]
