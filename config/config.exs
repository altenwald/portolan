import Config

if config_env() == :test do
  config :phoenix, :json_library, JSON
end

if config_env() == :test do
  config :logger, level: :warning
end
