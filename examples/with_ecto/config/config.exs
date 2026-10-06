import Config

config :phoenix, :json_library, JSON

config :with_ecto, WithEctoWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: WithEctoWeb.ErrorJSON], layout: false],
  secret_key_base: String.duplicate("with_ecto", 8)

config :with_ecto, Portolan,
  router: WithEctoWeb.Router,
  title: "Accounts API",
  openapi: "3.2",
  ui: :swagger_ui,
  pages: ["docs/validation.md"]

import_config "#{config_env()}.exs"
