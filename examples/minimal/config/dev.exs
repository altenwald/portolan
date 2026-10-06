import Config

config :minimal, MinimalWeb.Endpoint,
  http: [port: 4000],
  server: true,
  code_reloader: true,
  reloadable_compilers: [:elixir, :app, :portolan]
