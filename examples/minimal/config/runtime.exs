import Config

if config_env() == :prod do
  config :minimal, MinimalWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))],
    server: true
end
