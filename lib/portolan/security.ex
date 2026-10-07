defmodule Portolan.Security do
  @moduledoc """
  The security schemes of the API and the requirements of its operations.

  Schemes are declared once, in the configuration, with the fields of an
  OpenAPI security scheme:

      config :my_app, Portolan,
        router: MyAppWeb.Router,
        security_schemes: %{
          bearer: %{type: "http", scheme: "bearer", description: "An API token."}
        },
        security: [bearer: []]

  The requirements of an operation come, in this order, from:

  1. the `@doc security: ...` of its action
  2. the `:security` option, either the requirements themselves or a
     `{module, function}` called with the controller and the action name,
     which returns the requirements or `nil`

  Requirements are written as:

  * a keyword list or a map, a single requirement: every scheme listed is
    needed, with its scopes. `[bearer: ["users:read"]]`
  * a list of keyword lists or maps, alternatives: any of them is enough.
    `[[bearer: []], [api_key: []]]`
  * `[]`, the operation needs no authentication

  An operation without requirements, `nil`, says nothing about its
  security in the document.
  """

  @typedoc "A requirement: every scheme named, with the scopes needed."
  @type requirement :: %{String.t() => [String.t()]}

  @typedoc "The requirements of an operation: any of them is enough."
  @type t :: [requirement()]

  @typedoc "Where the requirements come from, as written in the configuration."
  @type source :: t() | keyword() | map() | {module(), atom()} | nil

  @doc """
  Normalizes requirements as written by the user.

  ## Examples

      iex> Portolan.Security.normalize([bearer: ["users:read"]])
      {:ok, [%{"bearer" => ["users:read"]}]}

      iex> Portolan.Security.normalize([[bearer: []], %{api_key: []}])
      {:ok, [%{"bearer" => []}, %{"api_key" => []}]}

      iex> Portolan.Security.normalize([])
      {:ok, []}

      iex> Portolan.Security.normalize(nil)
      {:ok, nil}

      iex> Portolan.Security.normalize(:bearer)
      :error

  """
  @spec normalize(term()) :: {:ok, t() | nil} | :error
  def normalize(nil), do: {:ok, nil}
  def normalize([]), do: {:ok, []}
  def normalize(%{} = requirement), do: wrap(requirement(requirement))

  def normalize(list) when is_list(list) do
    if Keyword.keyword?(list),
      do: wrap(requirement(list)),
      else: collect(list, &requirement/1, [])
  end

  def normalize(_other), do: :error

  defp wrap({:ok, requirement}), do: {:ok, [requirement]}
  defp wrap(:error), do: :error

  defp collect([], _fun, acc), do: {:ok, Enum.reverse(acc)}

  defp collect([item | rest], fun, acc) do
    case fun.(item) do
      {:ok, value} -> collect(rest, fun, [value | acc])
      :error -> :error
    end
  end

  defp requirement(requirement) when is_map(requirement),
    do: requirement |> Map.to_list() |> requirement_entries()

  defp requirement(requirement) when is_list(requirement) do
    if Keyword.keyword?(requirement), do: requirement_entries(requirement), else: :error
  end

  defp requirement(_other), do: :error

  defp requirement_entries(entries) do
    with {:ok, entries} <- collect(entries, &requirement_entry/1, []) do
      {:ok, Map.new(entries)}
    end
  end

  defp requirement_entry({name, scopes}) when is_atom(name) or is_binary(name) do
    with {:ok, scopes} <- scopes(scopes), do: {:ok, {to_string(name), scopes}}
  end

  defp requirement_entry(_other), do: :error

  defp scopes(scopes) when is_list(scopes) do
    if Enum.all?(scopes, &(is_binary(&1) or is_atom(&1))),
      do: {:ok, Enum.map(scopes, &to_string/1)},
      else: :error
  end

  defp scopes(_other), do: :error

  @doc """
  Normalizes the security schemes of the configuration: names and fields
  become strings, so they can be written to the document as they are.

  ## Examples

      iex> Portolan.Security.schemes(%{bearer: %{type: "http", scheme: "bearer"}})
      {:ok, %{"bearer" => %{"type" => "http", "scheme" => "bearer"}}}

      iex> Portolan.Security.schemes(%{bearer: "http"})
      :error

  """
  @spec schemes(term()) :: {:ok, %{String.t() => map()}} | :error
  def schemes(nil), do: {:ok, %{}}

  def schemes(schemes) when is_map(schemes) or is_list(schemes) do
    Enum.reduce_while(schemes, {:ok, %{}}, fn
      {name, %{} = scheme}, {:ok, acc} when is_atom(name) or is_binary(name) ->
        {:cont, {:ok, Map.put(acc, to_string(name), stringify(scheme))}}

      _other, _acc ->
        {:halt, :error}
    end)
  end

  def schemes(_other), do: :error

  defp stringify(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  @doc """
  The requirements of an action, from its `@doc security: ...` or the
  `source` of the configuration.

  `written` is what the action declared with `@doc`, `nil` when nothing.
  """
  @spec resolve(term(), source(), module(), atom()) :: {:ok, t() | nil} | :error
  def resolve(written, source, controller, action)

  def resolve(nil, {module, function}, controller, action)
      when is_atom(module) and is_atom(function),
      do: normalize(apply(module, function, [controller, action]))

  def resolve(nil, source, _controller, _action), do: normalize(source)
  def resolve(written, _source, _controller, _action), do: normalize(written)

  @doc """
  The schemes used by `requirements` that are not declared in `schemes`.

  ## Examples

      iex> Portolan.Security.unknown([%{"bearer" => [], "oauth" => ["read"]}], %{"bearer" => %{}})
      ["oauth"]

  """
  @spec unknown(t() | nil, %{String.t() => map()}) :: [String.t()]
  def unknown(nil, _schemes), do: []

  def unknown(requirements, schemes) do
    requirements
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(schemes, &1))
    |> Enum.sort()
  end
end
