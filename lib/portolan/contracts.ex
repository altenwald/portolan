defmodule Portolan.Contracts do
  @moduledoc """
  The contracts of the actions, used at runtime to cast parameters.

  Types cannot be read at runtime, because releases remove them from the
  compiled modules. The Portolan compiler resolves them while building the
  OpenAPI document and saves them in `priv/portolan/contracts.etf`, so the
  documentation and the validation always come from the same information.

  The contracts also keep the MD5 of every controller, to detect when a
  controller was recompiled without running the Portolan compiler, as it
  happens with the code reloader of Phoenix when `:portolan` is not one of
  its `:reloadable_compilers`.
  """

  alias Portolan.Type

  @relative_path "priv/portolan/contracts.etf"

  @typedoc """
  The contracts of an application.

  * `actions` - the parameters type of every documented action, or
    `:undocumented` for actions receiving `map()`
  * `types` - the resolved types of every reference in the parameters
  * `md5` - the MD5 of every documented controller
  """
  @type t :: %__MODULE__{
          actions: %{{module(), atom()} => Type.t() | :undocumented},
          types: %{{module(), atom(), [Type.t()]} => Type.t()},
          md5: %{module() => binary()}
        }

  defstruct actions: %{}, types: %{}, md5: %{}

  @doc """
  The path of the contracts, relative to the project root.

  ## Examples

      iex> Portolan.Contracts.relative_path()
      "priv/portolan/contracts.etf"

  """
  @spec relative_path() :: Path.t()
  def relative_path, do: @relative_path

  @doc """
  The path of the contracts of the application `app`.
  """
  @spec path(atom()) :: Path.t()
  def path(app), do: Application.app_dir(app, @relative_path)

  @doc """
  Returns the parameters type of an action.
  """
  @spec params(t(), module(), atom()) :: {:ok, Type.t() | :undocumented} | :error
  def params(%__MODULE__{actions: actions}, module, action),
    do: Map.fetch(actions, {module, action})

  @doc """
  Returns a function resolving references with the types of the contracts.

  The result can be given to `Portolan.Cast.cast/3` as `:resolve`.
  """
  @spec resolve(t()) :: Portolan.Cast.resolve_fun()
  def resolve(%__MODULE__{types: types}) do
    fn module, name, args -> Map.fetch!(types, {module, name, args}) end
  end

  @doc """
  Returns whether `module` changed since the contracts were built.

  Modules without contracts are never stale.
  """
  @spec stale?(t(), module()) :: boolean()
  def stale?(%__MODULE__{md5: md5}, module) do
    case Map.fetch(md5, module) do
      {:ok, md5} -> module.module_info(:md5) != md5
      :error -> false
    end
  end

  @doc """
  Saves the contracts in `path`, creating its directory.
  """
  @spec save(t(), Path.t()) :: :ok
  def save(%__MODULE__{} = contracts, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(contracts))
  end

  @doc """
  Reads the contracts saved in `path`.
  """
  @spec read(Path.t()) :: {:ok, t()} | {:error, File.posix() | :invalid}
  def read(path) do
    with {:ok, binary} <- File.read(path) do
      case safe_decode(binary) do
        %__MODULE__{} = contracts -> {:ok, contracts}
        _other -> {:error, :invalid}
      end
    end
  end

  @doc """
  Returns the contracts of the application `app`.

  Contracts are read once and cached. Use `reload/1` to read them again.
  """
  @spec fetch(atom()) :: {:ok, t()} | {:error, File.posix() | :invalid}
  def fetch(app) do
    case :persistent_term.get({__MODULE__, app}, nil) do
      nil -> reload(app)
      contracts -> {:ok, contracts}
    end
  end

  @doc """
  Reads the contracts of the application `app` again, replacing the
  cached ones.
  """
  @spec reload(atom()) :: {:ok, t()} | {:error, File.posix() | :invalid}
  def reload(app) do
    with {:ok, contracts} <- read(path(app)) do
      :persistent_term.put({__MODULE__, app}, contracts)
      {:ok, contracts}
    end
  end

  @doc """
  Removes the cached contracts of the application `app`.
  """
  @spec forget(atom()) :: :ok
  def forget(app) do
    :persistent_term.erase({__MODULE__, app})
    :ok
  end

  defp safe_decode(binary) do
    :erlang.binary_to_term(binary)
  rescue
    ArgumentError -> nil
  end
end
