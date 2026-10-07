defmodule Portolan.Action do
  @moduledoc """
  Reads the contract of a controller action from its `@doc` and `@spec`.

  An action is documented with a spec like this one:

      @spec show(Plug.Conn.t(), show_params()) :: {:ok, User.t()} | {:error, :not_found}

  * the first argument must be `Plug.Conn.t()`
  * the second argument describes the parameters, usually with a map type
  * the return type lists the responses:
    * `{:ok, data}` answers `200` with `data`
    * `{status, data}` answers `status` with `data`, as in `{:created, data}`
    * `status` answers `status` without a body, as in `:no_content`
    * `{:error, reason}` answers the status of `reason`, as in
      `{:error, :not_found}`, with an error body
    * `{:error, Ecto.Changeset.t()}` answers the validation errors, with the
      status of the error renderer, `422` by default, see
      `Portolan.ErrorRenderer`

  Statuses are the atoms known by `Plug.Conn.Status`, including the
  custom statuses configured for Plug.

  Actions returning `Plug.Conn.t()` or receiving `map()` keep working, but
  their responses or parameters cannot be documented, so a warning is
  reported.
  """

  alias Plug.Conn.Status
  alias Portolan.Docs
  alias Portolan.Issue
  alias Portolan.Type
  alias Portolan.Typespec

  defmodule Response do
    @moduledoc """
    A response of an action.

    * `status` - the HTTP status code
    * `body` - `{:data, type}` for data, `:error` for an error body,
      `:validation` for validation errors and `nil` for no body
    """

    @typedoc "A response."
    @type t :: %__MODULE__{
            status: 100..999,
            body: {:data, Type.t()} | :error | :validation | nil
          }

    @enforce_keys [:status, :body]
    defstruct [:status, :body]
  end

  @typedoc """
  The contract of an action.

  * `module` and `name` - the action function
  * `file` and `line` - where the action is defined
  * `summary` and `description` - from the `@doc`
  * `deprecated` - from `@deprecated` or `@doc deprecated: ...`
  * `security` - from `@doc security: ...`, as written, or `nil` to use
    the security configured for the API
  * `params` - the type of the parameters, or `:undocumented`
  * `responses` - the responses sorted by status, or `:undocumented`
  """
  @type t :: %__MODULE__{
          module: module(),
          name: atom(),
          file: String.t() | nil,
          line: non_neg_integer() | nil,
          summary: String.t(),
          description: String.t() | nil,
          deprecated: String.t() | nil,
          security: term(),
          params: Type.t() | :undocumented,
          responses: [Response.t()] | :undocumented
        }

  @enforce_keys [:module, :name, :summary, :params, :responses]
  defstruct [
    :module,
    :name,
    :file,
    :line,
    :summary,
    :description,
    :deprecated,
    :security,
    :params,
    :responses
  ]

  @doc """
  Reads the contract of the action `name` of `module`.

  `docs` is the documentation of `module`, see `Portolan.Docs.fetch/1`.

  Returns `:hidden` for actions documented with `@doc false`. Otherwise the
  action is returned with the warnings found, or all the errors when the
  action cannot be documented.
  """
  @spec fetch(module(), atom(), Docs.t()) ::
          {:ok, t(), [Issue.t()]} | :hidden | {:error, [Issue.t()]}
  def fetch(module, name, %Docs{} = docs) do
    case Map.fetch(docs.functions, {name, 2}) do
      {:ok, %Docs.Entry{text: :hidden}} ->
        :hidden

      {:ok, entry} ->
        case read(module, name, entry) do
          {:ok, action, warnings} -> {:ok, %{action | file: docs.file}, warnings}
          error -> error
        end
        |> Issue.put_file_result(docs.file)

      :error ->
        message = "#{signature(module, name)} is routed but it is not a public function"
        {:error, Issue.put_file([Issue.error(message, docs.moduledoc.line)], docs.file)}
    end
  end

  defp read(module, name, entry) do
    with {:ok, text} <- doc(module, name, entry),
         {:ok, line, params_form, return_form} <- spec(module, name, entry) do
      context = %{module: module, name: name, line: line}

      case {params(params_form, context), responses(return_form, context)} do
        {{:ok, params, params_warnings}, {:ok, responses, responses_warnings}} ->
          {summary, description} = Docs.split(text)

          action = %__MODULE__{
            module: module,
            name: name,
            line: entry.line,
            summary: summary,
            description: description,
            deprecated: entry.deprecated,
            security: entry.security,
            params: params,
            responses: responses
          }

          {:ok, action, params_warnings ++ responses_warnings}

        {params, responses} ->
          {:error, issues(params) ++ issues(responses)}
      end
    end
  end

  defp issues({:ok, _value, warnings}), do: warnings
  defp issues({:error, issues}), do: issues

  defp doc(module, name, %Docs.Entry{text: :none, line: line}) do
    message = "#{signature(module, name)} needs a @doc to be documented, or @doc false to hide it"
    {:error, [Issue.error(message, line)]}
  end

  defp doc(_module, _name, %Docs.Entry{text: text}), do: {:ok, text}

  defp spec(module, name, entry) do
    specs =
      case Code.Typespec.fetch_specs(module) do
        {:ok, specs} -> specs
        :error -> []
      end

    case List.keyfind(specs, {name, 2}, 0) do
      {_key, [{:type, anno, :fun, [{:type, _, :product, [conn, params]}, return]}]} ->
        line = :erl_anno.line(anno)

        if conn?(conn) do
          {:ok, line, params, return}
        else
          message = "the first argument of #{signature(module, name)} must be Plug.Conn.t()"
          {:error, [Issue.error(message, line)]}
        end

      {_key, [_bounded_or_several | _rest]} ->
        message =
          "#{signature(module, name)} must have a single @spec clause without guards (when)"

        {:error, [Issue.error(message, entry.line)]}

      nil ->
        message = "#{signature(module, name)} needs a @spec to be documented"
        {:error, [Issue.error(message, entry.line)]}
    end
  end

  # Parameters

  defp params(form, context) do
    if untyped_params?(form) do
      message =
        "the parameters of #{signature(context.module, context.name)} are not documented, " <>
          "use a map type to describe them"

      {:ok, :undocumented, [Issue.warning(message, context.line)]}
    else
      with {:ok, type} <- to_type(form, context), do: {:ok, type, []}
    end
  end

  defp untyped_params?({:ann_type, _anno, [_var, form]}), do: untyped_params?(form)
  defp untyped_params?({:type, _anno, :map, :any}), do: true
  defp untyped_params?(form), do: remote?(form, Plug.Conn, :params)

  # Responses

  defp responses(form, context) do
    members = members(form)

    cond do
      Enum.all?(members, &conn?/1) ->
        message =
          "the response of #{signature(context.module, context.name)} is not documented, " <>
            "return {:ok, data} or {:error, reason} instead of Plug.Conn.t()"

        {:ok, :undocumented, [Issue.warning(message, context.line)]}

      Enum.any?(members, &conn?/1) ->
        message =
          "#{signature(context.module, context.name)} cannot mix Plug.Conn.t() with other responses"

        {:error, [Issue.error(message, context.line)]}

      true ->
        with {:ok, responses} <- Issue.collect(members, &response(&1, context)) do
          merge(List.flatten(responses), context)
        end
    end
  end

  defp response({:atom, anno, status}, context) do
    with {:ok, code} <- status(status, anno, context) do
      {:ok, [%Response{status: code, body: nil}]}
    end
  end

  defp response({:type, _anno, :tuple, [{:atom, _, :error}, reasons]}, context) do
    Issue.collect(members(reasons), &error_response(&1, context))
  end

  defp response({:type, _anno, :tuple, [{:atom, anno, status}, data]}, context) do
    with {:ok, code} <- status(status, anno, context),
         {:ok, type} <- to_type(data, context) do
      {:ok, [%Response{status: code, body: {:data, type}}]}
    end
  end

  defp response(form, context) do
    message =
      "unsupported response in #{signature(context.module, context.name)}, " <>
        "use {:ok, data}, {status, data}, status or {:error, reason}"

    {:error, [Issue.error(message, line(form, context))]}
  end

  defp error_response({:atom, anno, reason}, context) do
    with {:ok, code} <- status(reason, anno, context) do
      {:ok, %Response{status: code, body: :error}}
    end
  end

  defp error_response(form, context) do
    if remote?(form, Ecto.Changeset, :t) do
      {:ok, %Response{status: 422, body: :validation}}
    else
      message =
        "unsupported error in #{signature(context.module, context.name)}, " <>
          "use a status such as :not_found or Ecto.Changeset.t()"

      {:error, [Issue.error(message, line(form, context))]}
    end
  end

  defp status(status, anno, context) do
    {:ok, Status.code(status)}
  rescue
    FunctionClauseError ->
      message =
        "#{inspect(status)} in #{signature(context.module, context.name)} is not an HTTP status, " <>
          "see Plug.Conn.Status for the known ones"

      {:error, [Issue.error(message, anno_line(anno, context))]}
  end

  defp merge(responses, context) do
    responses
    |> Enum.group_by(& &1.status)
    |> Enum.sort()
    |> Issue.collect(fn {status, group} -> merge_group(status, group, context) end)
    |> case do
      {:ok, responses} -> {:ok, responses, []}
      error -> error
    end
  end

  defp merge_group(_status, [response], _context), do: {:ok, response}

  defp merge_group(status, group, context) do
    bodies = group |> Enum.map(& &1.body) |> Enum.uniq()

    cond do
      match?([_body], bodies) ->
        {:ok, %Response{status: status, body: hd(bodies)}}

      Enum.all?(bodies, &match?({:data, _type}, &1)) ->
        types = Enum.map(bodies, fn {:data, type} -> type end)
        {:ok, %Response{status: status, body: {:data, {:union, types}}}}

      true ->
        message =
          "#{signature(context.module, context.name)} returns different kinds of bodies " <>
            "for the status #{status}"

        {:error, [Issue.error(message, context.line)]}
    end
  end

  # Helpers

  defp to_type(form, context),
    do: Typespec.to_type(form, module: context.module, line: context.line)

  defp members({:type, _anno, :union, forms}), do: Enum.flat_map(forms, &members/1)
  defp members({:ann_type, _anno, [_var, form]}), do: members(form)
  defp members(form), do: [form]

  defp conn?({:ann_type, _anno, [_var, form]}), do: conn?(form)
  defp conn?(form), do: remote?(form, Plug.Conn, :t)

  defp remote?({:remote_type, _anno, [{:atom, _, module}, {:atom, _, name}, []]}, module, name),
    do: true

  defp remote?(_form, _module, _name), do: false

  defp line(form, context) when elem(form, 0) in [:atom, :type, :remote_type, :user_type],
    do: anno_line(elem(form, 1), context)

  defp line(form, context), do: anno_line(elem(form, 1), context)

  defp anno_line(anno, context) do
    case :erl_anno.line(anno) do
      0 -> context.line
      line -> line
    end
  end

  defp signature(module, name), do: "#{inspect(module)}.#{name}/2"
end
