defmodule Portolan.Text do
  @moduledoc """
  A plain text response.

  Actions answering text instead of JSON return it as their data:

      @spec export(Plug.Conn.t(), export_params()) :: {:ok, Portolan.Text.t()}
      def export(_conn, params), do: {:ok, Portolan.Text.new(Exports.dotenv(params))}

  It is sent with the `text/plain` content type, and documented as a
  string. An action can answer JSON or text with the same status, as
  `{:ok, [Entry.t()]} | {:ok, Portolan.Text.t()}`, and both are documented
  for it.
  """

  @typedoc "A plain text response."
  @type t :: %__MODULE__{body: iodata()}

  @enforce_keys [:body]
  defstruct [:body]

  @doc """
  Wraps `body` as a plain text response.

  ## Examples

      iex> Portolan.Text.new("KEY=value")
      %Portolan.Text{body: "KEY=value"}

  """
  @spec new(iodata()) :: t()
  def new(body), do: %__MODULE__{body: body}
end
