defmodule Portolan.Docs do
  @moduledoc """
  Reads the documentation of compiled modules.

  This is the information written with `@moduledoc`, `@doc`, `@typedoc`
  and `@deprecated`. Modules must be compiled with documentation, which
  is the default.
  """

  alias Portolan.Issue

  defmodule Entry do
    @moduledoc """
    The documentation of a module, function or type.

    * `text` - the documentation in Markdown, `:none` when it was not
      written and `:hidden` when it was set to `false`
    * `deprecated` - the deprecation message, if any
    * `line` - where the module, function or type is defined
    """

    @typedoc "A documentation entry."
    @type t :: %__MODULE__{
            text: String.t() | :none | :hidden,
            deprecated: String.t() | nil,
            line: non_neg_integer() | nil
          }

    defstruct [:text, :deprecated, :line]
  end

  @typedoc """
  The documentation of a module.

  * `file` - the source file of the module
  * `moduledoc` - the documentation of the module itself
  * `functions` - the documentation of public functions and macros
  * `types` - the documentation of public types
  """
  @type t :: %__MODULE__{
          file: String.t() | nil,
          moduledoc: Entry.t(),
          functions: %{{atom(), arity()} => Entry.t()},
          types: %{{atom(), arity()} => Entry.t()}
        }

  defstruct [:file, :moduledoc, functions: %{}, types: %{}]

  @doc """
  Fetches the documentation of `module`.

  ## Examples

      iex> {:ok, docs} = Portolan.Docs.fetch(Portolan.Docs)
      iex> docs.functions[{:fetch, 1}].text =~ "Fetches the documentation"
      true

  """
  @spec fetch(module()) :: {:ok, t()} | {:error, [Issue.t()]}
  def fetch(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, anno, _language, _format, moduledoc, metadata, docs} ->
        {:ok,
         %__MODULE__{
           file: metadata |> Map.get(:source_path) |> to_file(),
           moduledoc: entry(moduledoc, anno, metadata),
           functions: entries(docs, [:function, :macro]),
           types: entries(docs, [:type])
         }}

      {:error, _reason} ->
        message =
          "cannot read the documentation of #{inspect(module)}, " <>
            "make sure it exists and it is compiled with documentation"

        {:error, [Issue.error(message)]}
    end
  end

  @doc """
  Splits documentation into its summary, the first paragraph, and the
  description, the rest.

  ## Examples

      iex> Portolan.Docs.split("Fetches a user.\\n\\nReturns 404 when it does not exist.\\n")
      {"Fetches a user.", "Returns 404 when it does not exist."}

  """
  @spec split(String.t()) :: {String.t(), String.t() | nil}
  def split(text) do
    case text |> String.trim() |> String.split(~r/\n\s*\n/, parts: 2) do
      [summary, description] -> {summary, String.trim(description)}
      [summary] -> {summary, nil}
    end
  end

  defp entries(docs, kinds) do
    for {{kind, name, arity}, anno, _signature, doc, metadata} <- docs,
        kind in kinds,
        into: %{} do
      {{name, arity}, entry(doc, anno, metadata)}
    end
  end

  defp entry(doc, anno, metadata) do
    %Entry{
      text: text(doc),
      deprecated: Map.get(metadata, :deprecated),
      line: line(anno, metadata)
    }
  end

  defp text(%{"en" => text}), do: text
  defp text(doc) when doc in [:none, :hidden], do: doc

  # The annotation points to the documentation attribute, the definition
  # itself is in the source annotations.
  defp line(anno, metadata) do
    case Map.get(metadata, :source_annos) do
      [{line, _column} | _rest] when is_integer(line) ->
        line

      [line | _rest] when is_integer(line) ->
        line

      _other ->
        :erl_anno.line(anno)
    end
  end

  defp to_file(nil), do: nil
  defp to_file(path), do: to_string(path)
end
