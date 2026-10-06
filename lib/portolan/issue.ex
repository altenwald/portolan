defmodule Portolan.Issue do
  @moduledoc """
  A problem found while reading the information Portolan builds the
  OpenAPI document from.

  Issues carry enough information to be reported as compiler diagnostics:
  a severity, a human readable message and, when known, the file and line
  where the problem lives.
  """

  @typedoc """
  An issue found while building the documentation.

  * `severity` - `:error` stops the build, `:warning` is only reported
  * `message` - what is wrong and, when possible, how to fix it
  * `file` - the source file, when known
  * `line` - the line in the source file, when known
  """
  @type t :: %__MODULE__{
          severity: :error | :warning,
          message: String.t(),
          file: String.t() | nil,
          line: non_neg_integer() | nil
        }

  @enforce_keys [:severity, :message]
  defstruct [:severity, :message, :file, :line]

  @doc """
  Builds an error issue.

  The position accepts the annotations found in Erlang abstract forms:
  a line, a `{line, column}` tuple or `0` for unknown.

  ## Examples

      iex> Portolan.Issue.error("unsupported type", {12, 5})
      %Portolan.Issue{severity: :error, message: "unsupported type", line: 12}

  """
  @spec error(String.t(), :erl_anno.anno() | nil) :: t()
  def error(message, anno \\ nil) do
    %__MODULE__{severity: :error, message: message, line: line(anno)}
  end

  @doc """
  Builds a warning issue.

  ## Examples

      iex> Portolan.Issue.warning("response is not documented", 7)
      %Portolan.Issue{severity: :warning, message: "response is not documented", line: 7}

  """
  @spec warning(String.t(), :erl_anno.anno() | nil) :: t()
  def warning(message, anno \\ nil) do
    %__MODULE__{severity: :warning, message: message, line: line(anno)}
  end

  @doc """
  Sets the file of every issue that does not have one yet.

  ## Examples

      iex> [Portolan.Issue.error("boom")]
      ...> |> Portolan.Issue.put_file("lib/my_app.ex")
      [%Portolan.Issue{severity: :error, message: "boom", file: "lib/my_app.ex"}]

  """
  @spec put_file([t()], String.t() | nil) :: [t()]
  def put_file(issues, file) do
    Enum.map(issues, fn
      %__MODULE__{file: nil} = issue -> %{issue | file: file}
      issue -> issue
    end)
  end

  defp line(nil), do: nil

  defp line(anno) do
    case :erl_anno.line(anno) do
      0 -> nil
      line -> line
    end
  end
end
