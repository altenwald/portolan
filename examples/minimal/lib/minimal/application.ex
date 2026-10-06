defmodule Minimal.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [Minimal.Notes, MinimalWeb.Endpoint]
    Supervisor.start_link(children, strategy: :one_for_one, name: Minimal.Supervisor)
  end
end
