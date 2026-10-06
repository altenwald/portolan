defmodule Minimal.Notes do
  @moduledoc "Keeps the notes in memory."
  use Agent

  alias Minimal.Note

  @doc false
  def start_link(_opts), do: Agent.start_link(fn -> {1, %{}} end, name: __MODULE__)

  @doc "Lists the notes, pinned first."
  @spec list() :: [Note.t()]
  def list do
    Agent.get(__MODULE__, fn {_next, notes} ->
      notes |> Map.values() |> Enum.sort_by(&{not &1.pinned, &1.id})
    end)
  end

  @doc "Fetches a note."
  @spec fetch(pos_integer()) :: {:ok, Note.t()} | {:error, :not_found}
  def fetch(id) do
    Agent.get(__MODULE__, fn {_next, notes} ->
      case Map.fetch(notes, id) do
        {:ok, note} -> {:ok, note}
        :error -> {:error, :not_found}
      end
    end)
  end

  @doc "Creates a note."
  @spec create(map()) :: Note.t()
  def create(attrs) do
    Agent.get_and_update(__MODULE__, fn {next, notes} ->
      note = struct(Note, Map.put(attrs, :id, next))
      {note, {next + 1, Map.put(notes, next, note)}}
    end)
  end

  @doc "Deletes a note."
  @spec delete(pos_integer()) :: :ok | {:error, :not_found}
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn {next, notes} ->
      if Map.has_key?(notes, id),
        do: {:ok, {next, Map.delete(notes, id)}},
        else: {{:error, :not_found}, {next, notes}}
    end)
  end
end
