defmodule WithEcto.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [WithEcto.Accounts, WithEctoWeb.Endpoint]
    Supervisor.start_link(children, strategy: :one_for_one, name: WithEcto.Supervisor)
  end
end
