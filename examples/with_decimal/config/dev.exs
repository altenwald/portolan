import Config

config :with_decimal, WithDecimalWeb.Endpoint,
  http: [port: 4000],
  server: true,
  code_reloader: true,
  reloadable_compilers: [:elixir, :app, :portolan]
