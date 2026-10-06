defmodule Portolan.Typespec do
  @moduledoc """
  Converts typespecs into `Portolan.Type` descriptions.

  Typespecs are read from compiled modules, so the modules must be compiled
  with debug information (the default in development and test).

  Every type that cannot be represented in OpenAPI produces a
  `Portolan.Issue` pointing to the line where it was written. All the issues
  of a type are collected, instead of stopping at the first one, so they can
  be fixed together.

  References to other types (`my_type()` or `MyApp.User.t()`) are not
  expanded; they become `{:ref, module, name, args}` and are resolved by
  whoever needs them. This keeps recursive types finite and lets the
  document reuse schemas. The exception are the well-known types listed in
  `Portolan.Type`, such as `String.t()` or `Date.t()`, which are translated
  directly.
  """

  alias Portolan.Issue
  alias Portolan.Type

  @known %{
    {String, :t} => {:string, nil},
    {Ecto.UUID, :t} => {:string, :uuid},
    {Date, :t} => {:string, :date},
    {DateTime, :t} => {:string, :date_time},
    {NaiveDateTime, :t} => {:string, :naive_date_time},
    {Time, :t} => {:string, :time},
    {Decimal, :t} => {:string, :decimal}
  }

  @integers %{
    integer: {:integer, nil, nil},
    pos_integer: {:integer, 1, nil},
    non_neg_integer: {:integer, 0, nil},
    neg_integer: {:integer, nil, -1}
  }

  @typedoc """
  Options for `to_type/2`.

  * `:module` - the module local types (`my_type()`) belong to
  * `:vars` - the types bound to the type variables
  * `:line` - the line reported when a form does not carry one
  """
  @type option ::
          {:module, module()}
          | {:vars, %{atom() => Type.t()}}
          | {:line, non_neg_integer() | nil}

  @typedoc """
  The result of a conversion.
  """
  @type result :: {:ok, Type.t()} | {:error, [Issue.t()]}

  @doc """
  Fetches the type `name` from `module` and converts it.

  `args` are the types bound to the parameters of parametric types, such as
  `page(item)`.

  ## Examples

      iex> Portolan.Typespec.fetch(Calendar, :hour)
      {:ok, {:integer, 0, nil}}

      iex> {:error, [issue]} = Portolan.Typespec.fetch(Calendar, :unknown)
      iex> issue.message
      "unknown type Calendar.unknown/0"

  """
  @spec fetch(module(), atom(), [Type.t()]) :: result()
  def fetch(module, name, args \\ []) do
    arity = length(args)

    with {:ok, types} <- fetch_types(module),
         {:ok, kind, form, vars} <- find(types, module, name, arity) do
      definition(kind, module, name, form, vars, args)
    end
    |> put_file(module)
  end

  @doc """
  Converts a type in Erlang abstract format into a `Portolan.Type`.

  This is how types and specs are stored in compiled modules, see the
  [Erlang abstract format](https://www.erlang.org/doc/apps/erts/absform.html#types).

  ## Examples

      iex> Portolan.Typespec.to_type({:type, 1, :range, [{:integer, 1, 1}, {:integer, 1, 10}]})
      {:ok, {:integer, 1, 10}}

      iex> {:error, [issue]} = Portolan.Typespec.to_type({:type, 4, :term, []})
      iex> {issue.line, issue.message}
      {4, "term() accepts any value and cannot be documented, use a more specific type"}

  """
  @spec to_type(tuple(), [option()]) :: result()
  def to_type(form, opts \\ []) do
    context = %{
      module: Keyword.get(opts, :module),
      vars: Keyword.get(opts, :vars, %{}),
      line: Keyword.get(opts, :line)
    }

    convert(form, context)
  end

  defp fetch_types(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        {:ok, types}

      :error ->
        message =
          "cannot read the types of #{inspect(module)}, " <>
            "make sure it exists and it is compiled with debug information"

        {:error, [Issue.error(message)]}
    end
  end

  defp find(types, module, name, arity) do
    Enum.find_value(
      types,
      {:error, [Issue.error("unknown type #{signature(module, name, arity)}")]},
      fn
        {kind, {^name, form, vars}} when length(vars) == arity -> {:ok, kind, form, vars}
        _other -> nil
      end
    )
  end

  defp definition(:opaque, module, name, _form, vars, _args) do
    arity = length(vars)
    line = definition_line(module, name, arity)
    {:error, [Issue.error("#{signature(module, name, arity)} is opaque", line)]}
  end

  defp definition(_visible, module, name, form, vars, args) do
    bindings = vars |> Enum.map(fn {:var, _anno, var} -> var end) |> Enum.zip(args)
    line = definition_line(module, name, length(vars))
    to_type(form, module: module, vars: Map.new(bindings), line: line)
  end

  defp definition_line(module, name, arity) do
    with {:docs_v1, _anno, _language, _format, _moduledoc, _metadata, docs} <-
           Code.fetch_docs(module),
         {_kind, anno, _signature, _doc, _meta} <-
           List.keyfind(docs, {:type, name, arity}, 0) do
      :erl_anno.line(anno)
    else
      _no_docs -> nil
    end
  end

  defp put_file({:error, issues}, module) do
    file =
      if Code.ensure_loaded?(module) do
        module.module_info(:compile) |> Keyword.get(:source) |> to_string()
      end

    {:error, Issue.put_file(issues, file)}
  end

  defp put_file(result, _module), do: result

  defp signature(module, name, arity), do: "#{inspect(module)}.#{name}/#{arity}"

  # Conversion

  defp convert({:ann_type, _anno, [_var, form]}, context), do: convert(form, context)

  defp convert({:var, _anno, name}, context) do
    case context.vars do
      %{^name => type} -> {:ok, type}
      _unbound -> {:ok, {:var, name}}
    end
  end

  defp convert({:atom, _anno, nil}, _context), do: {:ok, :null}
  defp convert({:atom, _anno, atom}, _context), do: {:ok, {:literal, atom}}
  defp convert({:integer, _anno, integer}, _context), do: {:ok, {:literal, integer}}

  defp convert({:op, _anno, :-, {:integer, _int_anno, integer}}, _context),
    do: {:ok, {:literal, -integer}}

  defp convert({:type, _anno, :range, [low, high]}, _context),
    do: {:ok, {:integer, integer(low), integer(high)}}

  defp convert({:type, _anno, name, []}, _context) when is_map_key(@integers, name),
    do: {:ok, Map.fetch!(@integers, name)}

  defp convert({:type, _anno, :binary, []}, _context), do: {:ok, {:string, nil}}
  defp convert({:type, _anno, :float, []}, _context), do: {:ok, :float}
  defp convert({:type, _anno, :number, []}, _context), do: {:ok, :number}
  defp convert({:type, _anno, :boolean, []}, _context), do: {:ok, :boolean}

  defp convert({:type, anno, :list, [item]}, context), do: list(item, false, anno, context)

  defp convert({:type, anno, :nonempty_list, [item]}, context),
    do: list(item, true, anno, context)

  defp convert({:type, anno, :union, forms}, context) do
    context = at(context, anno)

    with {:ok, types} <- collect(forms, &convert(&1, context)) do
      {:ok, {:union, types}}
    end
  end

  defp convert({:type, anno, :map, fields}, context) when is_list(fields) do
    context = at(context, anno)

    case struct_module(fields) do
      nil -> map(fields, context)
      module -> struct(module, fields, context)
    end
  end

  defp convert({:user_type, anno, name, args} = form, context) do
    context = at(context, anno)

    case context.module do
      nil ->
        {:error, [error("cannot resolve the local type #{name}/#{length(args)}", form, context)]}

      module ->
        ref(module, name, args, context)
    end
  end

  defp convert({:remote_type, _anno, [{:atom, _, module}, {:atom, _, name}, []]}, _context)
       when is_map_key(@known, {module, name}),
       do: {:ok, Map.fetch!(@known, {module, name})}

  defp convert({:remote_type, anno, [{:atom, _, module}, {:atom, _, name}, args]}, context),
    do: ref(module, name, args, at(context, anno))

  defp convert(form, context), do: unsupported(form, describe(form), context)

  defp integer({:integer, _anno, integer}), do: integer
  defp integer({:op, _anno, :-, {:integer, _int_anno, integer}}), do: -integer

  defp list(item, nonempty?, anno, context) do
    with {:ok, type} <- convert(item, at(context, anno)) do
      {:ok, {:list, type, nonempty?}}
    end
  end

  defp ref(module, name, args, context) do
    with {:ok, args} <- collect(args, &convert(&1, context)) do
      {:ok, {:ref, module, name, args}}
    end
  end

  defp struct_module(fields) do
    Enum.find_value(fields, fn
      {:type, _anno, :map_field_exact, [{:atom, _, :__struct__}, {:atom, _, module}]} -> module
      _other -> nil
    end)
  end

  defp struct(module, fields, context) do
    fields =
      Enum.reject(fields, &match?({:type, _, _, [{:atom, _, :__struct__}, _value]}, &1))

    with {:ok, {:map, fields, nil}} <- map(fields, context) do
      fields = Enum.map(fields, fn {name, _required, type} -> {name, true, type} end)
      {:ok, {:struct, module, definition_order(module, fields)}}
    end
  end

  # The compiler sorts struct fields, the struct definition keeps the
  # order chosen by the author.
  defp definition_order(module, fields) do
    order =
      module.__info__(:struct)
      |> Enum.with_index(fn %{field: field}, index -> {field, index} end)
      |> Map.new()

    Enum.sort_by(fields, fn {name, _required, _type} -> Map.fetch!(order, name) end)
  end

  defp map(fields, context) do
    with {:ok, fields} <- collect(fields, &map_field(&1, context)) do
      {additional, named} = Enum.split_with(fields, &match?({:additional, _type}, &1))

      case additional do
        [] -> {:ok, {:map, named, nil}}
        [{:additional, type}] -> {:ok, {:map, named, type}}
        _many -> {:error, [error("maps can only have one kind of string keys", nil, context)]}
      end
    end
  end

  defp map_field({:type, anno, kind, [key, value]}, context)
       when kind in [:map_field_exact, :map_field_assoc] do
    context = at(context, anno)

    case key do
      {:atom, _anno, name} ->
        with {:ok, type} <- convert(value, context) do
          {:ok, {name, kind == :map_field_exact, type}}
        end

      _other ->
        with {:ok, {:string, nil}} <- convert(key, context),
             {:ok, type} <- convert(value, context) do
          {:ok, {:additional, type}}
        else
          {:error, issues} -> {:error, issues}
          {:ok, _type} -> unsupported(key, "this map key", context)
        end
    end
  end

  defp collect(forms, fun) do
    {oks, errors} =
      forms
      |> Enum.map(fun)
      |> Enum.split_with(&match?({:ok, _}, &1))

    case errors do
      [] -> {:ok, Enum.map(oks, fn {:ok, value} -> value end)}
      _errors -> {:error, Enum.flat_map(errors, fn {:error, issues} -> issues end)}
    end
  end

  defp at(context, anno) do
    case :erl_anno.line(anno) do
      0 -> context
      line -> %{context | line: line}
    end
  end

  defp unsupported(form, description, context) do
    reason =
      case form do
        {:type, _anno, name, _args} when name in [:term, :any] ->
          "accepts any value and cannot be documented, use a more specific type"

        {:type, _anno, :tuple, _args} ->
          "cannot be represented in JSON, use a map or a struct"

        _other ->
          "cannot be represented in OpenAPI, use a more specific type"
      end

    {:error, [error("#{description} #{reason}", form, context)]}
  end

  defp error(message, form, context) do
    context = if is_tuple(form), do: at(context, elem(form, 1)), else: context
    Issue.error(message, context.line)
  end

  defp describe({:type, _anno, :tuple, _args}), do: "tuple"
  defp describe({:type, _anno, nil, []}), do: "[]"
  defp describe({:type, _anno, :map, :any}), do: "map()"
  defp describe({:type, _anno, name, _args}) when is_atom(name), do: "#{name}()"
  defp describe(form), do: inspect(form)
end
