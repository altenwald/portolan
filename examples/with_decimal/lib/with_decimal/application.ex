defmodule WithDecimal.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [WithDecimal.Catalog, WithDecimalWeb.Endpoint]
    Supervisor.start_link(children, strategy: :one_for_one, name: WithDecimal.Supervisor)
  end
end
