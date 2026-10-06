defmodule Minimal.Note do
  @moduledoc "A note."

  @derive JSON.Encoder
  defstruct [:id, :title, :body, tags: [], pinned: false]

  @typedoc """
  A note.

  * `id` - unique identifier
  * `title` - a short title
  * `body` - the content, in Markdown
  * `tags` - labels to find the note
  * `pinned` - whether the note is listed first
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          title: String.t(),
          body: String.t() | nil,
          tags: [String.t()],
          pinned: boolean()
        }
end
