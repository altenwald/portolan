import Config

# The JSON module of Elixir, so not even Jason is needed.
config :phoenix, :json_library, JSON

config :minimal, MinimalWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: MinimalWeb.ErrorJSON], layout: false],
  secret_key_base: String.duplicate("minimal", 10)

config :minimal, Portolan,
  router: MinimalWeb.Router,
  pages: ["docs/getting-started.md"]

import_config "#{config_env()}.exs"
