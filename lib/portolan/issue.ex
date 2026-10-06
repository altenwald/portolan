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

  The line is `nil` or `0` when unknown.

  ## Examples

      iex> Portolan.Issue.error("unsupported type", 12)
      %Portolan.Issue{severity: :error, message: "unsupported type", line: 12}

  """
  @spec error(String.t(), non_neg_integer() | nil) :: t()
  def error(message, line \\ nil) do
    %__MODULE__{severity: :error, message: message, line: line(line)}
  end

  @doc """
  Builds a warning issue.

  ## Examples

      iex> Portolan.Issue.warning("response is not documented", 7)
      %Portolan.Issue{severity: :warning, message: "response is not documented", line: 7}

  """
  @spec warning(String.t(), non_neg_integer() | nil) :: t()
  def warning(message, line \\ nil) do
    %__MODULE__{severity: :warning, message: message, line: line(line)}
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

  @doc """
  Sets the file of the issues in an error result.

  Other results are returned unchanged.

  ## Examples

      iex> Portolan.Issue.put_file_result({:error, [Portolan.Issue.error("boom")]}, "a.ex")
      {:error, [%Portolan.Issue{severity: :error, message: "boom", file: "a.ex"}]}

      iex> Portolan.Issue.put_file_result({:ok, 1}, "a.ex")
      {:ok, 1}

  """
  @spec put_file_result(result, String.t() | nil) :: result when result: term()
  def put_file_result({:error, issues}, file) when is_list(issues),
    do: {:error, put_file(issues, file)}

  def put_file_result({:ok, value, issues}, file) when is_list(issues),
    do: {:ok, value, put_file(issues, file)}

  def put_file_result(result, _file), do: result

  @doc """
  Applies `fun` to every element, collecting the issues of all of them.

  `fun` returns `{:ok, value}` or `{:error, issues}`. The result is
  `{:ok, values}` when every element succeeds, or `{:error, issues}` with
  the issues of every failing element.

  ## Examples

      iex> Portolan.Issue.collect([1, 2], &{:ok, &1 * 2})
      {:ok, [2, 4]}

      iex> Portolan.Issue.collect([1, 2, 3], fn
      ...>   2 -> {:ok, 2}
      ...>   n -> {:error, [Portolan.Issue.error("bad \#{n}")]}
      ...> end)
      {:error, [Portolan.Issue.error("bad 1"), Portolan.Issue.error("bad 3")]}

  """
  @spec collect([element], (element -> {:ok, value} | {:error, [t()]})) ::
          {:ok, [value]} | {:error, [t()]}
        when element: term(), value: term()
  def collect(elements, fun) do
    {values, issues} =
      Enum.reduce(elements, {[], []}, fn element, {values, issues} ->
        case fun.(element) do
          {:ok, value} -> {[value | values], issues}
          {:error, new_issues} -> {values, [new_issues | issues]}
        end
      end)

    case issues do
      [] -> {:ok, Enum.reverse(values)}
      _issues -> {:error, issues |> Enum.reverse() |> Enum.concat()}
    end
  end

  defp line(0), do: nil
  defp line(line), do: line
end
