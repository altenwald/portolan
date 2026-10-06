defmodule Portolan.JSONSchema do
  @moduledoc """
  Builds JSON Schemas from `Portolan.Type` descriptions.

  The schemas follow JSON Schema 2020-12, the dialect used by OpenAPI 3.1
  and 3.2. Keys are strings, so the result can be encoded as is.

  This module only knows about types and schemas. References
  (`{:ref, module, name, args}`) are handed to the `:ref` function given by
  the caller, who decides whether they become a `$ref`, an inlined schema
  or anything else.
  """

  alias Portolan.Type

  @typedoc """
  A JSON Schema.
  """
  @type t :: %{optional(String.t()) => term()}

  @typedoc """
  A function that builds the schema of a reference.
  """
  @type ref_fun :: (module(), atom(), [Type.t()] -> t())

  @typedoc """
  Options for `from_type/2`.

  * `:ref` - builds the schema of references, required when the type
    contains any
  """
  @type option :: {:ref, ref_fun()}

  @formats %{
    uuid: %{"format" => "uuid"},
    date: %{"format" => "date"},
    date_time: %{"format" => "date-time"},
    decimal: %{"format" => "decimal"},
    naive_date_time: %{"examples" => ["2024-01-31T10:30:00"]},
    time: %{"examples" => ["10:30:00"]}
  }

  @doc """
  Builds the JSON Schema of a type.

  ## Examples

      iex> Portolan.JSONSchema.from_type({:list, {:integer, 1, nil}, false})
      %{"type" => "array", "items" => %{"type" => "integer", "minimum" => 1}}

      iex> Portolan.JSONSchema.from_type({:union, [{:literal, :active}, {:literal, :inactive}]})
      %{"enum" => ["active", "inactive"]}

      iex> ref = fn MyApp.User, :t, [] -> %{"$ref" => "#/$defs/user"} end
      iex> Portolan.JSONSchema.from_type({:list, {:ref, MyApp.User, :t, []}, false}, ref: ref)
      %{"type" => "array", "items" => %{"$ref" => "#/$defs/user"}}

  """
  @spec from_type(Type.t(), [option()]) :: t()
  def from_type(type, opts \\ []) do
    convert(type, Keyword.get(opts, :ref, &missing_ref/3))
  end

  @spec missing_ref(module(), atom(), [Type.t()]) :: no_return()
  defp missing_ref(module, name, args) do
    raise ArgumentError,
          "cannot convert the reference to #{inspect(module)}.#{name}/#{length(args)} " <>
            "without a :ref function"
  end

  defp convert({:string, nil}, _ref), do: %{"type" => "string"}

  defp convert({:string, format}, _ref),
    do: Map.merge(%{"type" => "string"}, Map.fetch!(@formats, format))

  defp convert({:integer, min, max}, _ref) do
    %{"type" => "integer"}
    |> put_present("minimum", min)
    |> put_present("maximum", max)
  end

  defp convert(:float, _ref), do: %{"type" => "number", "format" => "double"}
  defp convert(:number, _ref), do: %{"type" => "number"}
  defp convert(:boolean, _ref), do: %{"type" => "boolean"}
  defp convert(:null, _ref), do: %{"type" => "null"}
  defp convert({:literal, value}, _ref), do: %{"const" => json_value(value)}

  defp convert({:list, item, nonempty?}, ref) do
    schema = %{"type" => "array", "items" => convert(item, ref)}
    if nonempty?, do: Map.put(schema, "minItems", 1), else: schema
  end

  defp convert({:map, fields, additional}, ref) do
    object(fields, ref)
    |> put_present("additionalProperties", additional && convert(additional, ref))
  end

  defp convert({:struct, _module, fields}, ref), do: object(fields, ref)
  defp convert({:union, types}, ref), do: union(types, ref)
  defp convert({:ref, module, name, args}, ref), do: ref.(module, name, args)

  defp convert({:var, name}, _ref),
    do: raise(ArgumentError, "the type variable #{name} is not bound to any type")

  defp object(fields, ref) do
    properties =
      Map.new(fields, fn {name, _required, type} -> {Atom.to_string(name), convert(type, ref)} end)

    required = for {name, true, _type} <- fields, do: Atom.to_string(name)

    %{"type" => "object"}
    |> put_present("properties", if(properties != %{}, do: properties))
    |> put_present("required", if(required != [], do: required))
  end

  defp union(types, ref) do
    types = flatten(types)
    {nulls, others} = Enum.split_with(types, &(&1 == :null))
    nullable? = nulls != []

    cond do
      others != [] and Enum.all?(others, &match?({:literal, _value}, &1)) ->
        values = Enum.map(others, fn {:literal, value} -> json_value(value) end)
        %{"enum" => if(nullable?, do: values ++ [nil], else: values)}

      nullable? and match?([_single], others) and simple?(convert(hd(others), ref)) ->
        schema = convert(hd(others), ref)
        %{schema | "type" => [schema["type"], "null"]}

      true ->
        %{"anyOf" => Enum.map(types, &convert(&1, ref))}
    end
  end

  defp flatten(types) do
    Enum.flat_map(types, fn
      {:union, nested} -> flatten(nested)
      type -> [type]
    end)
  end

  defp simple?(%{"type" => type}) when is_binary(type), do: true
  defp simple?(_schema), do: false

  defp json_value(value) when is_boolean(value) or is_integer(value), do: value
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
