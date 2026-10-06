import Config

config :phoenix, :json_library, JSON

config :with_decimal, WithDecimalWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: WithDecimalWeb.ErrorJSON], layout: false],
  secret_key_base: String.duplicate("with_decimal", 6)

config :with_decimal, Portolan, router: WithDecimalWeb.Router

import_config "#{config_env()}.exs"
