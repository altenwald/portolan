defmodule Portolan.Controller do
  @moduledoc """
  Adds a Phoenix controller to the documented API.

  Only the controllers using this module are documented, so HTML
  controllers and internal endpoints stay out of the OpenAPI document.

      defmodule MyAppWeb.UserController do
        use MyAppWeb, :controller
        use Portolan.Controller
      end

  Every routed action of the controller must have a `@doc` and a `@spec`.
  Actions with `@doc false` are left out of the document.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @doc false
      @spec __portolan__() :: :controller
      def __portolan__, do: :controller
    end
  end

  @doc """
  Returns whether `module` is a controller documented by Portolan.

  ## Examples

      iex> Portolan.Controller.documented?(String)
      false

  """
  @spec documented?(module()) :: boolean()
  def documented?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__portolan__, 0)
  end
end
