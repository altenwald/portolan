defmodule Portolan.Compiler do
  @moduledoc """
  Builds the OpenAPI document of a Phoenix router.

  This is where the pieces meet:

  1. the routes of the controllers using `Portolan.Controller` are read
     from the router
  2. every action is read with `Portolan.Action`
  3. the parameters are split into path, query and body parameters
  4. every referenced type is resolved with `Portolan.Typespec` and
     documented with its `@typedoc` (see `Portolan.FieldDocs`)
  5. the Markdown pages are read
  6. the document is built with `Portolan.OpenAPI`
  7. the contracts used at runtime to cast parameters are built with the
     same information, see `Portolan.Contracts`

  All the issues found are returned together.
  """

  alias Portolan.Action
  alias Portolan.Contracts
  alias Portolan.Docs
  alias Portolan.ErrorRenderer
  alias Portolan.FieldDocs
  alias Portolan.Issue
  alias Portolan.OpenAPI
  alias Portolan.OpenAPI.Operation
  alias Portolan.OpenAPI.Parameter
  alias Portolan.OpenAPI.Schema
  alias Portolan.OpenAPI.Tag
  alias Portolan.Security
  alias Portolan.SharedResponses
  alias Portolan.Type
  alias Portolan.Typespec

  @query_verbs [:get, :head, :delete, :options]

  @typedoc """
  Options for `build/2`.

  * `:title` - the title of the API (required)
  * `:version` - the version of the API (required)
  * `:openapi` - the OpenAPI version, `"3.1"` (default) or `"3.2"`
  * `:pages` - Markdown files added as documentation pages
  * `:security_schemes` - the security schemes of the API, see
    `Portolan.Security`
  * `:security` - the security requirements of the operations, or a
    `{module, function}` returning them, see `Portolan.Security`
  * `:responses` - responses shared by every operation, or a
    `{module, function}` returning them, see `Portolan.SharedResponses`
  * `:error_renderer` - the module rendering errors, whose schemas and
    validation status are documented, see `Portolan.ErrorRenderer`
  """
  @type option ::
          {:title, String.t()}
          | {:version, String.t()}
          | {:openapi, OpenAPI.version()}
          | {:pages, [Path.t()]}
          | {:security_schemes, map()}
          | {:security, Security.source()}
          | {:responses, Portolan.SharedResponses.source()}
          | {:error_renderer, module()}

  @typedoc """
  The result of a build.

  * `document` - the OpenAPI document, see `Portolan.OpenAPI.encode/1`
  * `contracts` - the contracts of the documented actions
  """
  @type result :: %{document: Portolan.JSONSchema.t(), contracts: Contracts.t()}

  @doc """
  Builds the OpenAPI document and the contracts of `router`.

  Returns them with the warnings found, or every issue found when there
  are errors.
  """
  @spec build(module(), [option()]) :: {:ok, result(), [Issue.t()]} | {:error, [Issue.t()]}
  def build(router, opts) do
    with :ok <- check_version(opts),
         {:ok, settings} <- check_settings(opts),
         {:ok, router_docs} <- router_docs(router) do
      {operations, actions, tags, operation_issues} = operations(router, settings)
      {schemas, schema_issues} = schemas(operations, settings.renderer)
      {pages, page_issues} = pages(Keyword.get(opts, :pages, []))

      spec = %OpenAPI{
        version: Keyword.get(opts, :openapi, "3.1"),
        title: Keyword.fetch!(opts, :title),
        api_version: Keyword.fetch!(opts, :version),
        description: text(router_docs.moduledoc),
        tags: pages ++ tags,
        operations: operations,
        schemas: schemas,
        security_schemes: settings.schemes
      }

      issues = Enum.uniq(operation_issues ++ schema_issues ++ page_issues)

      if Enum.any?(issues, &(&1.severity == :error)),
        do: {:error, issues},
        else: {:ok, %{document: OpenAPI.build(spec), contracts: contracts(actions)}, issues}
    end
  end

  defp check_version(opts) do
    version = Keyword.get(opts, :openapi, "3.1")

    if version in OpenAPI.versions() do
      :ok
    else
      message =
        "unsupported OpenAPI version #{inspect(version)}, " <>
          "use one of: #{Enum.join(OpenAPI.versions(), ", ")}"

      {:error, [Issue.error(message)]}
    end
  end

  defp check_settings(opts) do
    renderer = Keyword.get(opts, :error_renderer, Portolan.ErrorRenderer.Default)

    renderer_check =
      if ErrorRenderer.renderer?(renderer),
        do: :ok,
        else:
          {:error,
           "the :error_renderer #{inspect(renderer)} does not implement Portolan.ErrorRenderer"}

    responses = Keyword.get(opts, :responses)

    checks = [renderer_check, check_responses(responses)]

    case {check_security(opts), Enum.flat_map(checks, &option_issue/1)} do
      {{:ok, security}, []} ->
        {:ok, Map.merge(security, %{renderer: renderer, responses: responses})}

      {{:ok, _security}, issues} ->
        {:error, issues}

      {{:error, security_issues}, issues} ->
        {:error, security_issues ++ issues}
    end
  end

  defp check_responses({module, function}) when is_atom(module) and is_atom(function) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 2),
      do: :ok,
      else: {:error, "the :responses function #{inspect(module)}.#{function}/2 does not exist"}
  end

  defp check_responses(responses) do
    case SharedResponses.normalize(responses) do
      {:ok, _responses} -> :ok
      {:error, message} -> {:error, "the :responses option is not valid: " <> message}
    end
  end

  defp check_security(opts) do
    source = Keyword.get(opts, :security)

    case {check_schemes(Keyword.get(opts, :security_schemes)), check_source(source)} do
      {{:ok, schemes}, :ok} -> {:ok, %{schemes: schemes, source: source}}
      {schemes, requirements} -> {:error, Enum.flat_map([schemes, requirements], &option_issue/1)}
    end
  end

  defp check_schemes(schemes) do
    case Security.schemes(schemes) do
      {:ok, schemes} ->
        {:ok, schemes}

      :error ->
        {:error,
         "the :security_schemes option must map each scheme name to its OpenAPI fields, " <>
           "as %{bearer: %{type: \"http\", scheme: \"bearer\"}}"}
    end
  end

  defp check_source({module, function}) when is_atom(module) and is_atom(function) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 2),
      do: :ok,
      else: {:error, "the :security function #{inspect(module)}.#{function}/2 does not exist"}
  end

  defp check_source(requirements) do
    if Security.normalize(requirements) == :error,
      do:
        {:error,
         "the :security option must be requirements, as [bearer: []], or {module, function}"},
      else: :ok
  end

  defp option_issue({:error, message}), do: [Issue.error(message)]
  defp option_issue(_ok), do: []

  defp router_docs(router) do
    if Code.ensure_loaded?(router) and function_exported?(router, :__routes__, 0) do
      Docs.fetch(router)
    else
      {:error, [Issue.error("#{inspect(router)} is not a Phoenix router")]}
    end
  end

  # Operations

  defp operations(router, settings) do
    routes =
      for route <- Phoenix.Router.routes(router),
          is_atom(route.plug_opts),
          Portolan.Controller.documented?(route.plug),
          do: route

    {controllers, controller_issues} = controllers(routes)

    {operations, issues} =
      routes
      |> Enum.filter(&Map.has_key?(controllers, &1.plug))
      |> Enum.map(&operation(&1, Map.fetch!(controllers, &1.plug), settings))
      |> Enum.reduce({[], controller_issues}, fn
        {nil, issues}, {operations, all} -> {operations, all ++ issues}
        {built, issues}, {operations, all} -> {[built | operations], all ++ issues}
      end)

    {operations, actions} = operations |> Enum.reverse() |> Enum.unzip()

    tags =
      routes
      |> Enum.map(& &1.plug)
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(controllers, &1))
      |> Enum.map(&tag(&1, Map.fetch!(controllers, &1)))

    {unique_ids(operations), actions, tags, issues}
  end

  defp controllers(routes) do
    routes
    |> Enum.map(& &1.plug)
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn controller, {controllers, issues} ->
      case Docs.fetch(controller) do
        {:ok, %Docs{moduledoc: %Docs.Entry{text: :hidden}}} ->
          {controllers, issues}

        {:ok, %Docs{moduledoc: %Docs.Entry{text: :none} = entry} = docs} ->
          message = "#{inspect(controller)} needs a @moduledoc, or @moduledoc false to hide it"
          issue = %{Issue.error(message, entry.line) | file: docs.file}
          {Map.put(controllers, controller, docs), [issue | issues]}

        {:ok, docs} ->
          {Map.put(controllers, controller, docs), issues}

        {:error, new_issues} ->
          {controllers, issues ++ new_issues}
      end
    end)
  end

  defp tag(controller, docs) do
    {summary, _description} = Docs.split(text(docs.moduledoc) || "")

    %Tag{
      name: tag_name(controller),
      summary: if(summary != "", do: summary),
      description: docs.moduledoc |> text() |> trim()
    }
  end

  defp tag_name(controller) do
    case controller.__portolan__(:tag) do
      nil -> default_tag(controller)
      tag -> tag
    end
  end

  defp default_tag(controller) do
    controller |> Module.split() |> List.last() |> String.replace_suffix("Controller", "")
  end

  defp operation(route, docs, settings) do
    case Action.fetch(route.plug, route.plug_opts, docs) do
      :hidden ->
        {nil, []}

      {:error, issues} ->
        {nil, issues}

      {:ok, action, warnings} ->
        {path, path_names} = path(route.path)

        with {:ok, requirements} <- requirements(action, settings),
             {:ok, shared} <- shared_responses(action, settings),
             {:ok, parameters, body} <- parameters(action, route.verb, path_names) do
          operation =
            build_operation(route, action, path, parameters, body, {settings.renderer, shared})

          {{%{operation | security: requirements}, action}, warnings}
        else
          {:error, issues} -> {nil, warnings ++ Issue.put_file(issues, action.file)}
        end
    end
  end

  defp shared_responses(action, settings) do
    case SharedResponses.resolve(settings.responses, action.module, action.name) do
      {:ok, responses} ->
        {:ok, responses}

      {:error, message} ->
        {:error, [Issue.error("#{signature(action)}: #{message}", action.line)]}
    end
  end

  defp requirements(action, security) do
    case Security.resolve(action.security, security.source, action.module, action.name) do
      {:ok, requirements} ->
        case Security.unknown(requirements, security.schemes) do
          [] ->
            {:ok, requirements}

          unknown ->
            message =
              "#{signature(action)} requires the security schemes #{Enum.join(unknown, ", ")}, " <>
                "which are not declared in :security_schemes"

            {:error, [Issue.error(message, action.line)]}
        end

      :error ->
        message =
          "the security of #{signature(action)} must be requirements, as [bearer: [\"scope\"]]"

        {:error, [Issue.error(message, action.line)]}
    end
  end

  defp build_operation(route, action, path, parameters, body, {renderer, shared}) do
    %Operation{
      method: route.verb,
      path: path,
      operation_id: "#{route.plug |> Module.split() |> List.last()}.#{action.name}",
      tag: tag_name(route.plug),
      summary: action.summary,
      description: action.description,
      deprecated: action.deprecated,
      parameters: parameters,
      request_body: body,
      responses: responses(action, renderer, shared)
    }
  end

  defp unique_ids(operations) do
    {operations, _seen} =
      Enum.map_reduce(operations, MapSet.new(), fn operation, seen ->
        id =
          if MapSet.member?(seen, operation.operation_id),
            do: "#{operation.operation_id}_#{operation.method}",
            else: operation.operation_id

        {%{operation | operation_id: id}, MapSet.put(seen, id)}
      end)

    operations
  end

  defp path(path) do
    {segments, names} =
      path
      |> String.split("/")
      |> Enum.map_reduce([], fn
        ":" <> name, names -> {"{#{name}}", [name | names]}
        "*" <> name, names -> {"{#{name}}", [name | names]}
        segment, names -> {segment, names}
      end)

    {Enum.join(segments, "/"), Enum.reverse(names)}
  end

  # Parameters

  defp parameters(%Action{params: :undocumented}, _verb, path_names) do
    parameters =
      Enum.map(path_names, &%Parameter{name: &1, in: :path, required: true, type: {:string, nil}})

    {:ok, parameters, nil}
  end

  defp parameters(%Action{} = action, verb, path_names) do
    with {:ok, fields, additional, docs} <- params_fields(action),
         {:ok, path_params, rest} <- path_params(action, fields, docs, path_names) do
      other_params(action, verb, path_params, rest, additional, docs)
    end
  end

  defp other_params(action, verb, path_params, fields, _additional, docs)
       when verb in @query_verbs do
    with {:ok, query} <- query_params(action, fields, docs), do: {:ok, path_params ++ query, nil}
  end

  defp other_params(_action, _verb, path_params, [], nil, _docs), do: {:ok, path_params, nil}

  defp other_params(_action, _verb, path_params, fields, additional, _docs),
    do: {:ok, path_params, {:map, fields, additional}}

  defp params_fields(action) do
    {type, docs} =
      case action.params do
        {:ref, module, name, args} ->
          case describe(module, name, args) do
            {:ok, schema} -> {schema.type, schema.fields}
            {:error, issues} -> {{:error, issues}, %{}}
          end

        type ->
          {type, %{}}
      end

    case type do
      {:error, issues} ->
        {:error, issues}

      {:map, fields, additional} ->
        {:ok, fields, additional, docs}

      {:struct, _module, fields} ->
        {:ok, fields, nil, docs}

      _other ->
        {:error,
         [Issue.error("the parameters of #{signature(action)} must be a map", action.line)]}
    end
  end

  defp path_params(action, fields, docs, path_names) do
    Enum.reduce_while(path_names, {:ok, [], fields}, fn name, {:ok, params, rest} ->
      case path_param(action, name, rest, docs) do
        {:ok, param, rest} -> {:cont, {:ok, params ++ [param], rest}}
        {:error, issues} -> {:halt, {:error, issues}}
      end
    end)
  end

  defp path_param(action, name, fields, docs) do
    case Enum.split_with(fields, fn {field, _required, _type} -> Atom.to_string(field) == name end) do
      {[{_field, _required, type}], rest} ->
        param = %Parameter{
          name: name,
          in: :path,
          required: true,
          type: type,
          description: docs[name]
        }

        {:ok, param, rest}

      {[], _rest} ->
        message =
          "the path parameter #{name} is not declared in the parameters of #{signature(action)}"

        {:error, [Issue.error(message, action.line)]}
    end
  end

  defp query_params(action, fields, docs) do
    Issue.collect(fields, fn {field, required, type} ->
      name = Atom.to_string(field)

      if queryable?(type) do
        {:ok,
         %Parameter{
           name: name,
           in: :query,
           required: required,
           type: type,
           description: docs[name]
         }}
      else
        message =
          "the query parameter #{name} of #{signature(action)} must be a scalar or a list of scalars"

        {:error, [Issue.error(message, action.line)]}
      end
    end)
  end

  defp queryable?({:list, item, _nonempty}), do: scalar?(item)
  defp queryable?(type), do: scalar?(type)

  defp scalar?({:union, types}), do: Enum.all?(types, &scalar?/1)
  defp scalar?({:map, _fields, _additional}), do: false
  defp scalar?({:struct, _module, _fields}), do: false
  defp scalar?({:list, _item, _nonempty}), do: false

  defp scalar?({:ref, module, name, args}) do
    case Typespec.fetch(module, name, args) do
      {:ok, type} -> scalar?(type)
      {:error, _issues} -> true
    end
  end

  defp scalar?(_type), do: true

  defp responses(%Action{responses: :undocumented}, _renderer, _shared), do: :undocumented

  # Validation errors answer the status of the renderer, which may be the
  # status of other responses too. Their bodies are then alternatives.
  defp responses(%Action{} = action, renderer, shared) do
    validation = renderer.validation_status()

    responses =
      Enum.map(action.responses, fn
        %Action.Response{body: :validation} -> {validation, :validation}
        %Action.Response{status: status, body: body} -> {status, body}
      end) ++ shared

    # Parameters are validated, so documented parameters can be rejected.
    responses =
      if action.params != :undocumented and
           not Enum.any?(responses, &match?({_, :validation}, &1)),
         do: responses ++ [{validation, :validation}],
         else: responses

    responses
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {status, bodies} ->
      %OpenAPI.Response{status: status, body: response_body(bodies)}
    end)
  end

  defp response_body(bodies) when is_list(bodies) do
    case bodies |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> nil
      [body] -> response_body(body)
      bodies -> {:one_of, Enum.map(bodies, &response_body/1)}
    end
  end

  defp response_body({:data, type}), do: {:type, type}
  defp response_body(:text), do: :text
  defp response_body(:error), do: {:component, "Portolan.Error"}
  defp response_body(:validation), do: {:component, "Portolan.ValidationError"}

  # Schemas

  defp schemas(operations, renderer) do
    types = operations |> Enum.flat_map(&operation_types/1) |> Enum.flat_map(&alternatives/1)

    builtin =
      for {:component, name} <- types,
          into: %{},
          do: {name, %Schema{json: builtin_schema(renderer, name)}}

    refs =
      types
      |> Enum.flat_map(fn
        {:type, type} -> refs(type)
        _other -> []
      end)

    resolve(refs, builtin, [])
  end

  defp builtin_schema(renderer, "Portolan.Error"), do: renderer.error_schema()
  defp builtin_schema(renderer, "Portolan.ValidationError"), do: renderer.validation_schema()

  defp alternatives({:one_of, bodies}), do: bodies
  defp alternatives(body), do: [body]

  defp operation_types(operation) do
    params = Enum.map(operation.parameters, &{:type, &1.type})
    body = if operation.request_body, do: [{:type, operation.request_body}], else: []

    responses =
      case operation.responses do
        :undocumented -> []
        responses -> for %{body: body} <- responses, body != nil, do: body
      end

    params ++ body ++ responses
  end

  defp resolve([], schemas, issues), do: {schemas, issues}

  defp resolve([{module, name, args} | rest], schemas, issues) do
    component = OpenAPI.component_name(module, name, args)

    if Map.has_key?(schemas, component) do
      resolve(rest, schemas, issues)
    else
      case describe(module, name, args) do
        {:ok, schema} ->
          resolve(refs(schema.type) ++ rest, Map.put(schemas, component, schema), issues)

        {:error, new_issues} ->
          # Keep a placeholder, so the same type is not reported again.
          resolve(rest, Map.put(schemas, component, %Schema{}), issues ++ new_issues)
      end
    end
  end

  defp describe(module, name, args) do
    with {:ok, docs} <- Docs.fetch(module) do
      entry = Map.get(docs.types, {name, length(args)}, %Docs.Entry{text: :hidden})
      signature = "#{inspect(module)}.#{name}/#{length(args)}"

      # Both the type and its documentation are checked, so every problem
      # is reported at once.
      case {Typespec.fetch(module, name, args), check_typedoc(entry, signature)} do
        {{:ok, type}, :ok} -> describe_entry(entry, type, signature)
        {type, typedoc} -> {:error, error_issues(type) ++ error_issues(typedoc)}
      end
      |> Issue.put_file_result(docs.file)
    end
  end

  defp check_typedoc(%Docs.Entry{text: :none} = entry, signature) do
    message = "#{signature} needs a @typedoc to be documented"
    {:error, [Issue.error(message, entry.line)]}
  end

  defp check_typedoc(_entry, _signature), do: :ok

  defp error_issues({:error, issues}), do: issues
  defp error_issues(_ok), do: []

  defp describe_entry(%Docs.Entry{text: :hidden} = entry, type, _signature) do
    {:ok, %Schema{type: type, deprecated: entry.deprecated != nil}}
  end

  defp describe_entry(%Docs.Entry{text: text} = entry, type, signature) do
    {description, fields} = FieldDocs.parse(text)
    names = type |> field_names() |> MapSet.new()

    case Enum.reject(Map.keys(fields), &MapSet.member?(names, &1)) do
      [] ->
        {:ok,
         %Schema{
           type: type,
           description: description,
           fields: fields,
           deprecated: entry.deprecated != nil
         }}

      unknown ->
        {:error,
         Enum.map(unknown, fn name ->
           Issue.error(
             "the @typedoc of #{signature} documents the field #{name}, which does not exist",
             entry.line
           )
         end)}
    end
  end

  defp field_names({:map, fields, _additional}), do: Enum.map(fields, &field_name/1)
  defp field_names({:struct, _module, fields}), do: Enum.map(fields, &field_name/1)

  defp field_names(_type), do: []

  defp field_name({name, _required, _type}), do: Atom.to_string(name)

  @spec refs(Type.t()) :: [{module(), atom(), [Type.t()]}]
  defp refs({:ref, module, name, args}), do: [{module, name, args} | Enum.flat_map(args, &refs/1)]
  defp refs({:list, item, _nonempty}), do: refs(item)
  defp refs({:union, types}), do: Enum.flat_map(types, &refs/1)
  defp refs({:struct, _module, fields}), do: fields_refs(fields, nil)
  defp refs({:map, fields, additional}), do: fields_refs(fields, additional)
  defp refs(_type), do: []

  defp fields_refs(fields, additional) do
    Enum.flat_map(fields, fn {_name, _required, type} -> refs(type) end) ++
      if(additional, do: refs(additional), else: [])
  end

  # Contracts

  defp contracts(actions) do
    params = Enum.reject(Enum.map(actions, & &1.params), &(&1 == :undocumented))

    %Contracts{
      actions: Map.new(actions, &{{&1.module, &1.name}, &1.params}),
      types: resolve_types(Enum.flat_map(params, &refs/1), %{}),
      md5: Map.new(actions, &{&1.module, &1.module.module_info(:md5)})
    }
  end

  # Every type was already fetched and checked while building the document.
  defp resolve_types([], types), do: types

  defp resolve_types([{module, name, args} = ref | rest], types) do
    if Map.has_key?(types, ref) do
      resolve_types(rest, types)
    else
      {:ok, type} = Typespec.fetch(module, name, args)
      resolve_types(refs(type) ++ rest, Map.put(types, ref, type))
    end
  end

  # Pages

  defp pages(paths) do
    paths
    |> Enum.map(&page/1)
    |> Enum.reduce({[], []}, fn
      {:ok, tag}, {tags, issues} -> {tags ++ [tag], issues}
      {:error, issue}, {tags, issues} -> {tags, issues ++ [issue]}
    end)
  end

  defp page(path) do
    case File.read(path) do
      {:ok, content} ->
        case Regex.run(~r/\A\s*#\s+(.+?)\s*\n(.*)\z/s, content) do
          [_content, title, body] ->
            {:ok, %Tag{name: title, description: trim(body), page: true}}

          nil ->
            {:error,
             %{Issue.error("pages must start with a level one heading (# Title)", 1) | file: path}}
        end

      {:error, reason} ->
        {:error,
         %{Issue.error("cannot read the page: #{:file.format_error(reason)}") | file: path}}
    end
  end

  # Helpers

  defp text(%Docs.Entry{text: text}) when is_binary(text), do: text
  defp text(_entry), do: nil

  defp trim(nil), do: nil

  defp trim(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  defp signature(action), do: "#{inspect(action.module)}.#{action.name}/2"
end
