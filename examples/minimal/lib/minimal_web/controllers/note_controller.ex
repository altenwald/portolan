defmodule MinimalWeb.NoteController do
  @moduledoc """
  Notes.

  Notes have a title, an optional body and tags.
  """
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias Minimal.Note
  alias Minimal.Notes

  @typedoc """
  Filters for the list of notes.

  * `tag` - only notes with this tag
  * `pinned` - only pinned, or not pinned, notes
  """
  @type index_params :: %{optional(:tag) => String.t(), optional(:pinned) => boolean()}

  @typedoc """
  Identifies a note.

  * `id` - the note identifier
  """
  @type id_params :: %{required(:id) => pos_integer()}

  @typedoc """
  A new note.

  * `title` - a short title
  * `body` - the content, in Markdown
  * `tags` - labels to find the note
  * `pinned` - whether the note is listed first
  """
  @type create_params :: %{
          required(:title) => String.t(),
          optional(:body) => String.t(),
          optional(:tags) => [String.t()],
          optional(:pinned) => boolean()
        }

  @doc """
  Lists notes.

  Pinned notes come first.
  """
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [Note.t()]}
  def index(_conn, params) do
    notes =
      Enum.filter(Notes.list(), fn note ->
        (params[:tag] in [nil | note.tags]) and params[:pinned] in [nil, note.pinned]
      end)

    {:ok, notes}
  end

  @doc "Fetches a note."
  @spec show(Plug.Conn.t(), id_params()) :: {:ok, Note.t()} | {:error, :not_found}
  def show(_conn, %{id: id}), do: Notes.fetch(id)

  @doc "Creates a note."
  @spec create(Plug.Conn.t(), create_params()) :: {:created, Note.t()}
  def create(_conn, params), do: {:created, Notes.create(params)}

  @doc "Deletes a note."
  @spec delete(Plug.Conn.t(), id_params()) :: :no_content | {:error, :not_found}
  def delete(_conn, %{id: id}) do
    with :ok <- Notes.delete(id), do: :no_content
  end
end
