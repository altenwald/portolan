defmodule Portolan.Cast do
  @moduledoc """
  Casts external data into the values described by a `Portolan.Type`.

  Parameters reach a Phoenix controller as strings (path and query) or as
  decoded JSON (body), always with string keys. Casting turns them into
  the values the typespec promises:

  * map keys declared in the type become atoms, unknown keys are dropped,
    so no atom is ever created from user input
  * numbers, booleans and literals are parsed from strings
  * dates, times and UUIDs are validated and parsed
  * structs are built with `struct/2`, so missing nullable fields take
    their default value

  This module only knows about types and values. References
  (`{:ref, module, name, args}`) are resolved by the `:resolve` function
  given by the caller.

  All the errors are collected and returned together. Each error carries
  the path to the offending value, so `[:items, 1, :id]` means the `id`
  of the second element of `items`.
  """

  alias Portolan.Type

  @typedoc """
  The location of a value inside the data being cast.
  """
  @type path :: [atom() | String.t() | non_neg_integer()]

  @typedoc """
  A casting error: where it happened and what is wrong.
  """
  @type error :: {path(), String.t()}

  @typedoc """
  A function that returns the type a reference points to.
  """
  @type resolve_fun :: (module(), atom(), [Type.t()] -> Type.t())

  @typedoc """
  Options for `cast/3`.

  * `:resolve` - returns the type of references, required when the type
    contains any
  """
  @type option :: {:resolve, resolve_fun()}

  @compile {:no_warn_undefined, Decimal}

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  @doc """
  Casts `value` into `type`.

  ## Examples

      iex> type = {:map, [{:id, true, {:integer, 1, nil}}, {:tags, false, {:list, {:string, nil}, false}}], nil}
      iex> Portolan.Cast.cast(type, %{"id" => "42", "tags" => ["a"], "other" => "x"})
      {:ok, %{id: 42, tags: ["a"]}}
      iex> Portolan.Cast.cast(type, %{"tags" => ["a", 1]})
      {:error, [{[:id], "is required"}, {[:tags, 1], "must be a string"}]}

  """
  @spec cast(Type.t(), term(), [option()]) :: {:ok, term()} | {:error, [error()]}
  def cast(type, value, opts \\ []) do
    resolve = Keyword.get(opts, :resolve, &missing_resolve/3)

    do_cast(type, value, resolve)
  end

  defp do_cast({:string, nil}, value, _resolve) when is_binary(value), do: {:ok, value}
  defp do_cast({:string, nil}, _value, _resolve), do: fail("must be a string")

  defp do_cast({:string, format}, value, _resolve), do: format(format, value)

  defp do_cast({:integer, min, max}, value, _resolve) do
    with {:ok, integer} <- parse_integer(value) do
      cond do
        min && integer < min -> fail("must be greater than or equal to #{min}")
        max && integer > max -> fail("must be less than or equal to #{max}")
        true -> {:ok, integer}
      end
    end
  end

  defp do_cast(:float, value, _resolve) when is_float(value), do: {:ok, value}
  defp do_cast(:float, value, _resolve) when is_integer(value), do: {:ok, value * 1.0}

  defp do_cast(:float, value, _resolve) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _invalid -> fail("must be a number")
    end
  end

  defp do_cast(:float, _value, _resolve), do: fail("must be a number")

  defp do_cast(:number, value, _resolve) when is_number(value), do: {:ok, value}

  defp do_cast(:number, value, resolve) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _not_integer -> do_cast(:float, value, resolve)
    end
  end

  defp do_cast(:number, _value, _resolve), do: fail("must be a number")

  defp do_cast(:boolean, value, _resolve) when is_boolean(value), do: {:ok, value}
  defp do_cast(:boolean, "true", _resolve), do: {:ok, true}
  defp do_cast(:boolean, "false", _resolve), do: {:ok, false}
  defp do_cast(:boolean, _value, _resolve), do: fail("must be a boolean")

  defp do_cast(:null, nil, _resolve), do: {:ok, nil}
  defp do_cast(:null, _value, _resolve), do: fail("must be null")

  defp do_cast({:literal, literal}, value, _resolve) do
    if value === literal or value == to_string(literal),
      do: {:ok, literal},
      else: fail("must be #{describe(literal)}")
  end

  defp do_cast({:union, types}, value, resolve) do
    Enum.find_value(types, union_error(types), fn type ->
      case do_cast(type, value, resolve) do
        {:ok, value} -> {:ok, value}
        {:error, _errors} -> nil
      end
    end)
  end

  defp do_cast({:list, _item, true}, [], _resolve), do: fail("must not be empty")

  defp do_cast({:list, item, _nonempty}, values, resolve) when is_list(values) do
    values
    |> Enum.with_index()
    |> collect(fn {value, index} -> nest(do_cast(item, value, resolve), index) end)
  end

  defp do_cast({:list, _item, _nonempty}, _value, _resolve), do: fail("must be a list")

  defp do_cast({:map, fields, additional}, value, resolve) when is_map(value) do
    with {:ok, named} <- fields(fields, value, resolve, false),
         {:ok, extra} <- additional(additional, fields, value, resolve) do
      {:ok, Map.merge(extra, named)}
    end
  end

  defp do_cast({:struct, module, fields}, value, resolve) when is_map(value) do
    with {:ok, fields} <- fields(fields, value, resolve, true) do
      {:ok, struct(module, fields)}
    end
  end

  defp do_cast({kind, _, _}, _value, _resolve) when kind in [:map, :struct],
    do: fail("must be an object")

  defp do_cast({:ref, module, name, args}, value, resolve),
    do: do_cast(resolve.(module, name, args), value, resolve)

  defp do_cast({:var, name}, _value, _resolve),
    do: raise(ArgumentError, "the type variable #{name} is not bound to any type")

  @spec missing_resolve(module(), atom(), [Type.t()]) :: no_return()
  defp missing_resolve(module, name, args) do
    raise ArgumentError,
          "cannot cast the reference to #{inspect(module)}.#{name}/#{length(args)} " <>
            "without a :resolve function"
  end

  defp fields(fields, value, resolve, struct?) do
    fields
    |> Enum.flat_map(&field(&1, value, resolve, struct?))
    |> collect(fn {name, result} ->
      with {:ok, value} <- result, do: {:ok, {name, value}}
    end)
    |> case do
      {:ok, pairs} -> {:ok, Map.new(pairs)}
      error -> error
    end
  end

  defp field({name, required, type}, value, resolve, struct?) do
    case fetch(value, name) do
      {:ok, field_value} ->
        [{name, nest(do_cast(type, field_value, resolve), name)}]

      :error ->
        # Structs fill missing nullable fields with their defaults.
        if required and not (struct? and nullable?(type)),
          do: [{name, nest(fail("is required"), name)}],
          else: []
    end
  end

  defp additional(nil, _fields, _value, _resolve), do: {:ok, %{}}

  defp additional(type, fields, value, resolve) do
    known = MapSet.new(fields, fn {name, _required, _type} -> Atom.to_string(name) end)

    value
    |> Enum.filter(fn {key, _value} -> is_binary(key) and not MapSet.member?(known, key) end)
    |> collect(fn {key, field_value} ->
      with {:ok, cast} <- nest(do_cast(type, field_value, resolve), key), do: {:ok, {key, cast}}
    end)
    |> case do
      {:ok, pairs} -> {:ok, Map.new(pairs)}
      error -> error
    end
  end

  defp fetch(map, name) do
    case Map.fetch(map, Atom.to_string(name)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, name)
    end
  end

  defp nullable?(:null), do: true
  defp nullable?({:union, types}), do: Enum.any?(types, &nullable?/1)
  defp nullable?(_type), do: false

  defp format(:uuid, value) when is_binary(value) do
    if Regex.match?(@uuid, value), do: {:ok, String.downcase(value)}, else: fail("must be a UUID")
  end

  defp format(:uuid, _value), do: fail("must be a UUID")

  defp format(:date, value),
    do: iso8601(Date, value, "must be a date (YYYY-MM-DD)")

  defp format(:time, value),
    do: iso8601(Time, value, "must be a time (HH:MM:SS)")

  defp format(:naive_date_time, value),
    do: iso8601(NaiveDateTime, value, "must be a date-time (YYYY-MM-DDTHH:MM:SS)")

  defp format(:date_time, %DateTime{} = value), do: {:ok, value}

  defp format(:date_time, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> fail("must be a date-time with offset (YYYY-MM-DDTHH:MM:SSZ)")
    end
  end

  defp format(:date_time, _value),
    do: fail("must be a date-time with offset (YYYY-MM-DDTHH:MM:SSZ)")

  defp format(:decimal, value) do
    if not Code.ensure_loaded?(Decimal) do
      raise ArgumentError, "casting Decimal.t() requires the :decimal dependency"
    end

    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, decimal}
      :error -> fail("must be a decimal number")
    end
  end

  defp iso8601(module, %module{} = value, _message), do: {:ok, value}

  defp iso8601(module, value, message) when is_binary(value) do
    case module.from_iso8601(value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _reason} -> fail(message)
    end
  end

  defp iso8601(_module, _value, message), do: fail(message)

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> fail("must be an integer")
    end
  end

  defp parse_integer(_value), do: fail("must be an integer")

  defp union_error(types) do
    {nulls, others} = Enum.split_with(types, &(&1 == :null))

    if Enum.all?(others, &match?({:literal, _}, &1)) do
      values = Enum.map(others, fn {:literal, literal} -> describe(literal) end)
      values = if nulls == [], do: values, else: values ++ ["null"]
      {init, [last]} = Enum.split(values, -1)
      fail("must be one of #{Enum.join(init, ", ")} or #{last}")
    else
      fail("does not match any of the allowed types")
    end
  end

  defp describe(literal) when is_atom(literal) and not is_boolean(literal),
    do: inspect(Atom.to_string(literal))

  defp describe(literal), do: inspect(literal)

  defp fail(message), do: {:error, [{[], message}]}

  defp nest({:ok, value}, _key), do: {:ok, value}

  defp nest({:error, errors}, key),
    do: {:error, Enum.map(errors, fn {path, message} -> {[key | path], message} end)}

  defp collect(items, fun) do
    {values, errors} =
      Enum.reduce(items, {[], []}, fn item, {values, errors} ->
        case fun.(item) do
          {:ok, value} -> {[value | values], errors}
          {:error, new_errors} -> {values, [new_errors | errors]}
        end
      end)

    case errors do
      [] -> {:ok, Enum.reverse(values)}
      _errors -> {:error, errors |> Enum.reverse() |> Enum.concat()}
    end
  end
end
