defmodule Portolan.FieldDocs do
  @moduledoc """
  Extracts the documentation of fields from a `@typedoc`.

  Fields are documented with a Markdown list where each item starts with
  the field name between backticks:

      @typedoc \"""
      A user of the application.

      * `id` - unique identifier
      * `email` - contact address, when known
      \"""

  Documenting fields is optional. The items are removed from the
  description, so the field documentation is not repeated.
  """

  @item ~r/^[*-]\s+`([^`]+)`\s*(?:-|–|—|:)\s*(.*)$/u
  @continuation ~r/^\s+\S/

  @doc """
  Parses a type documentation.

  Returns the description without the field items, `nil` when nothing
  else is left, and the documentation of each field. Field names are
  returned as strings, so no atoms are created.

  ## Examples

      iex> Portolan.FieldDocs.parse("A user.\\n\\n* `id` - unique identifier\\n")
      {"A user.", %{"id" => "unique identifier"}}

  """
  @spec parse(String.t()) :: {String.t() | nil, %{String.t() => String.t()}}
  def parse(text) do
    {lines, fields, _current} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], [], nil}, &line/2)

    description =
      case lines
           |> Enum.reverse()
           |> Enum.join("\n")
           |> String.replace(~r/\n{3,}/, "\n\n")
           |> String.trim() do
        "" -> nil
        description -> description
      end

    {description,
     fields |> Enum.reverse() |> Map.new(fn {name, doc} -> {name, Enum.join(doc, " ")} end)}
  end

  defp line(line, {lines, fields, current}) do
    cond do
      match = Regex.run(@item, line) ->
        [_line, name, doc] = match
        {lines, [{name, [String.trim(doc)]} | fields], name}

      current != nil and Regex.match?(@continuation, line) ->
        [{name, doc} | rest] = fields
        {lines, [{name, doc ++ [String.trim(line)]} | rest], current}

      true ->
        {[line | lines], fields, nil}
    end
  end
end
