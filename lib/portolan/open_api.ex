defmodule Portolan.OpenAPI do
  @moduledoc """
  Builds OpenAPI documents.

  This module only knows about OpenAPI. It receives the operations, tags
  and schemas already prepared, with their types described as
  `Portolan.Type`, and turns them into an OpenAPI 3.1 or 3.2 document.

  References between types become `$ref`s to the components section,
  named with `component_name/3`.
  """

  alias Plug.Conn.Status
  alias Portolan.JSONSchema
  alias Portolan.Type

  defmodule Tag do
    @moduledoc """
    A group of operations, or a page of documentation.

    * `name` - the tag name, used by operations to refer to it
    * `summary` - a short description, used by OpenAPI 3.2
    * `description` - the documentation in Markdown
    * `page` - whether the tag is a documentation page instead of a group
      of operations
    """

    @typedoc "A tag."
    @type t :: %__MODULE__{
            name: String.t(),
            summary: String.t() | nil,
            description: String.t() | nil,
            page: boolean()
          }

    @enforce_keys [:name]
    defstruct [:name, :summary, :description, page: false]
  end

  defmodule Parameter do
    @moduledoc """
    A path or query parameter.

    * `name` - the parameter name
    * `in` - where the parameter is, `:path` or `:query`
    * `required` - whether the parameter is required
    * `type` - the type of the parameter
    * `description` - the documentation of the parameter
    """

    @typedoc "A parameter."
    @type t :: %__MODULE__{
            name: String.t(),
            in: :path | :query,
            required: boolean(),
            type: Type.t(),
            description: String.t() | nil
          }

    @enforce_keys [:name, :in, :required, :type]
    defstruct [:name, :in, :required, :type, :description]
  end

  defmodule Response do
    @moduledoc """
    A response of an operation.

    * `status` - the HTTP status code
    * `body` - `{:type, type}` for a body described by a type,
      `{:component, name}` for a body described by a component schema,
      or `nil` for no body
    """

    @typedoc "A response."
    @type t :: %__MODULE__{
            status: 100..999,
            body: {:type, Type.t()} | {:component, String.t()} | nil
          }

    @enforce_keys [:status, :body]
    defstruct [:status, :body]
  end

  defmodule Operation do
    @moduledoc """
    An operation: a method on a path.

    * `method` - the HTTP method
    * `path` - the path, with parameters written as `{name}`
    * `operation_id` - a unique identifier of the operation
    * `tag` - the tag grouping the operation
    * `summary` and `description` - the documentation of the operation
    * `deprecated` - the deprecation message, if any
    * `parameters` - the path and query parameters
    * `request_body` - the type of the JSON body, if any
    * `responses` - the responses, or `:undocumented`
    """

    @typedoc "An operation."
    @type t :: %__MODULE__{
            method: atom(),
            path: String.t(),
            operation_id: String.t(),
            tag: String.t() | nil,
            summary: String.t() | nil,
            description: String.t() | nil,
            deprecated: String.t() | nil,
            parameters: [Parameter.t()],
            request_body: Type.t() | nil,
            responses: [Response.t()] | :undocumented
          }

    @enforce_keys [:method, :path, :operation_id, :responses]
    defstruct [
      :method,
      :path,
      :operation_id,
      :tag,
      :summary,
      :description,
      :deprecated,
      :request_body,
      :responses,
      parameters: []
    ]
  end

  defmodule Schema do
    @moduledoc """
    A schema of the components section.

    * `type` - the type described by the schema
    * `json` - a literal JSON Schema, used instead of `type`
    * `description` - the documentation of the schema
    * `fields` - the documentation of each field, by field name
    * `deprecated` - whether the schema is deprecated
    """

    @typedoc "A component schema."
    @type t :: %__MODULE__{
            type: Type.t() | nil,
            json: JSONSchema.t() | nil,
            description: String.t() | nil,
            fields: %{String.t() => String.t()},
            deprecated: boolean()
          }

    defstruct [:type, :json, :description, fields: %{}, deprecated: false]
  end

  @typedoc """
  The supported OpenAPI versions.
  """
  @type version :: String.t()

  @typedoc """
  The content of an OpenAPI document.

  * `version` - the OpenAPI version, `"3.1"` or `"3.2"`
  * `title`, `api_version` and `description` - the information about the API
  * `tags` - the tags, documentation pages first
  * `operations` - the operations
  * `schemas` - the component schemas, by name
  """
  @type t :: %__MODULE__{
          version: version(),
          title: String.t(),
          api_version: String.t(),
          description: String.t() | nil,
          tags: [Tag.t()],
          operations: [Operation.t()],
          schemas: %{String.t() => Schema.t()}
        }

  @enforce_keys [:version, :title, :api_version]
  defstruct [:version, :title, :api_version, :description, tags: [], operations: [], schemas: %{}]

  @versions %{"3.1" => "3.1.1", "3.2" => "3.2.0"}

  @doc """
  The OpenAPI versions that can be generated.

  ## Examples

      iex> Portolan.OpenAPI.versions()
      ["3.1", "3.2"]

  """
  @spec versions() :: [version()]
  def versions, do: @versions |> Map.keys() |> Enum.sort()

  @doc """
  Builds the OpenAPI document.

  The result uses string keys and can be encoded as JSON with `encode/1`.

  ## Examples

      iex> Portolan.OpenAPI.build(%Portolan.OpenAPI{version: "3.1", title: "Shop", api_version: "1.0.0"})
      %{"openapi" => "3.1.1", "info" => %{"title" => "Shop", "version" => "1.0.0"}, "paths" => %{}}

  """
  @spec build(t()) :: JSONSchema.t()
  def build(%__MODULE__{} = spec) do
    openapi = Map.fetch!(@versions, spec.version)

    %{
      "openapi" => openapi,
      "info" =>
        %{"title" => spec.title, "version" => spec.api_version}
        |> put_present("description", spec.description),
      "paths" => paths(spec.operations)
    }
    |> put_present("tags", tags(spec.tags, spec.version))
    |> put_present("components", components(spec.schemas))
  end

  @doc """
  Encodes a document as pretty printed JSON with sorted keys.

  The output is stable, so the generated file can be committed and its
  changes reviewed.
  """
  @spec encode(JSONSchema.t()) :: String.t()
  def encode(document) do
    document
    |> nulls()
    |> :json.format()
    |> IO.iodata_to_binary()
  end

  @doc """
  The name of the component schema of a referenced type.

  `t/0` types are named after their module, other types add their own name.
  The arguments of parametric types are appended, so every instance gets
  its own schema.

  ## Examples

      iex> Portolan.OpenAPI.component_name(MyApp.User, :t, [])
      "MyApp.User"

      iex> Portolan.OpenAPI.component_name(MyApp.User, :role, [])
      "MyApp.User.role"

  """
  @spec component_name(module(), atom(), [Type.t()]) :: String.t()
  def component_name(module, name, args) do
    base = if name == :t, do: inspect(module), else: "#{inspect(module)}.#{name}"
    Enum.join([base | Enum.map(args, &label/1)], "_")
  end

  # Paths

  defp paths(operations) do
    operations
    |> Enum.group_by(& &1.path)
    |> Map.new(fn {path, operations} ->
      {path, Map.new(operations, &{Atom.to_string(&1.method), operation(&1)})}
    end)
  end

  defp operation(operation) do
    %{
      "operationId" => operation.operation_id,
      "responses" => responses(operation.responses)
    }
    |> put_present("tags", operation.tag && [operation.tag])
    |> put_present("summary", operation.summary)
    |> put_present("description", description(operation))
    |> put_present("deprecated", operation.deprecated && true)
    |> put_present("parameters", parameters(operation.parameters))
    |> put_present("requestBody", request_body(operation.request_body))
  end

  defp description(%Operation{deprecated: nil, description: description}), do: description

  defp description(%Operation{deprecated: deprecated, description: description}) do
    Enum.join(["**Deprecated:** #{deprecated}" | List.wrap(description)], "\n\n")
  end

  defp parameters([]), do: nil

  defp parameters(parameters) do
    Enum.map(parameters, fn parameter ->
      %{
        "name" => parameter.name,
        "in" => Atom.to_string(parameter.in),
        "required" => parameter.required,
        "schema" => schema(parameter.type)
      }
      |> put_present("description", parameter.description)
    end)
  end

  defp request_body(nil), do: nil

  defp request_body(type) do
    %{"required" => required?(type), "content" => json_content(schema(type))}
  end

  defp required?({:map, fields, _additional}),
    do: Enum.any?(fields, fn {_name, required, _type} -> required end)

  defp required?(_type), do: true

  defp responses(:undocumented),
    do: %{"default" => %{"description" => "The response is not documented."}}

  defp responses(responses) do
    Map.new(responses, fn %Response{status: status, body: body} ->
      response =
        %{"description" => Status.reason_phrase(status)}
        |> put_present("content", body && json_content(body_schema(body)))

      {Integer.to_string(status), response}
    end)
  end

  defp body_schema({:type, type}), do: schema(type)
  defp body_schema({:component, name}), do: component_ref(name)

  defp json_content(schema), do: %{"application/json" => %{"schema" => schema}}

  # Tags

  defp tags([], _version), do: nil
  defp tags(tags, version), do: Enum.map(tags, &tag(&1, version))

  defp tag(tag, "3.1") do
    put_present(%{"name" => tag.name}, "description", tag.description)
  end

  defp tag(tag, "3.2") do
    %{"name" => tag.name}
    |> put_present("summary", tag.summary)
    |> put_present("description", tag.description)
    |> put_present("kind", if(tag.page, do: "nav"))
  end

  # Components

  defp components(schemas) when map_size(schemas) == 0, do: nil

  defp components(schemas) do
    %{"schemas" => Map.new(schemas, fn {name, schema} -> {name, component(schema)} end)}
  end

  defp component(%Schema{json: json}) when json != nil, do: json

  defp component(%Schema{} = component) do
    component.type
    |> schema()
    |> describe_fields(component.fields)
    |> put_present("description", component.description)
    |> put_present("deprecated", if(component.deprecated, do: true))
  end

  defp describe_fields(%{"properties" => properties} = schema, fields) do
    properties =
      Map.new(properties, fn {name, property} ->
        {name, put_present(property, "description", Map.get(fields, name))}
      end)

    %{schema | "properties" => properties}
  end

  defp describe_fields(schema, _fields), do: schema

  # Helpers

  defp schema(type) do
    JSONSchema.from_type(type,
      ref: fn module, name, args -> component_ref(component_name(module, name, args)) end
    )
  end

  defp component_ref(name), do: %{"$ref" => "#/components/schemas/" <> name}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp nulls(nil), do: :null
  defp nulls(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, nulls(value)} end)
  defp nulls(list) when is_list(list), do: Enum.map(list, &nulls/1)
  defp nulls(value), do: value

  defp label({:ref, module, name, args}), do: component_name(module, name, args)
  defp label({:string, nil}), do: "string"
  defp label({:string, format}), do: Atom.to_string(format)
  defp label({:integer, _min, _max}), do: "integer"
  defp label({:literal, value}), do: to_string(value)
  defp label({:list, item, _nonempty}), do: "list_" <> label(item)
  defp label({:map, _fields, _additional}), do: "map"
  defp label({:struct, module, _fields}), do: inspect(module)
  defp label({:union, types}), do: Enum.map_join(types, "_or_", &label/1)
  defp label({:var, name}), do: Atom.to_string(name)
  defp label(type) when is_atom(type), do: Atom.to_string(type)
end
