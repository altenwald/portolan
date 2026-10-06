defmodule Portolan.Test.Source do
  @moduledoc false

  @doc false
  @spec line(String.t(), String.t()) :: pos_integer()
  def line(text, file \\ "test/support/api.ex") do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, text))
    |> Kernel.+(1)
  end
end
