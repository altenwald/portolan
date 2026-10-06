import Config

if config_env() == :prod do
  config :with_decimal, WithDecimalWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))],
    server: true
end
