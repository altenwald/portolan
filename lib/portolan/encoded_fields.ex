defmodule Portolan.EncodedFields do
  @moduledoc """
  Finds the fields of a struct that its JSON encoder sends.

  Structs leave fields out of their JSON with the options of `@derive`:

      @derive {Jason.Encoder, only: [:id, :name]}
      @derive {JSON.Encoder, except: [:password_hash]}

  Those fields are not in the responses, so they are not documented
  either. To know them, a struct with every field set to `nil` is encoded
  with the JSON library configured for Phoenix, and the keys of the result
  are the fields sent. This works the same with `only`, `except` or an
  encoder written by hand.

  When the struct cannot be encoded that way, as when its encoder needs
  values that are not `nil`, every field is kept.
  """

  @doc """
  Returns the fields of `module` sent by its JSON encoder, or `:all` when
  they cannot be found.

  ## Examples

      iex> Portolan.EncodedFields.fetch(Portolan.Test.User)
      {:ok, [:id, :name, :email, :role]}

      iex> Portolan.EncodedFields.fetch(URI)
      :all

  """
  @spec fetch(module()) :: {:ok, [atom()]} | :all
  def fetch(module) do
    fields = for %{field: field} <- module.__info__(:struct) || [], do: field
    sample = struct(module, Map.new(fields, &{&1, nil}))

    case encode(sample) do
      {:ok, %{} = encoded} ->
        {:ok, Enum.filter(fields, &Map.has_key?(encoded, Atom.to_string(&1)))}

      _error ->
        :all
    end
  end

  defp encode(sample) do
    {:ok,
     sample
     |> Phoenix.json_library().encode_to_iodata!()
     |> IO.iodata_to_binary()
     |> :json.decode()}
  rescue
    _error -> :error
  end
end
