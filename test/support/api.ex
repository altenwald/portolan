defmodule Portolan.Test.User do
  @moduledoc false
  defstruct [:id, :name, :email, :role]

  @typedoc """
  A user of the application.

  * `id` - unique identifier
  * `email` - contact address, when known
  """
  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          email: String.t() | nil,
          role: role()
        }

  @typedoc "What a user is allowed to do."
  @type role :: :admin | :member

  @typedoc deprecated: "Use role/0"
  @typedoc "Old roles."
  @type legacy_role :: :root
end

defmodule Portolan.Test.UserController do
  @moduledoc """
  Users of the application.

  Users can be listed, created and removed.
  """
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias Portolan.Test.User

  @typedoc """
  Filters for the list of users.

  * `role` - only users with this role
  * `page` - page number, starting at 1
  """
  @type index_params :: %{optional(:role) => User.role(), optional(:page) => pos_integer()}

  @typedoc """
  Identifies a user.

  * `id` - the user identifier
  """
  @type show_params :: %{required(:id) => Ecto.UUID.t()}

  @typedoc "Data to create a user."
  @type create_params :: %{required(:name) => String.t(), optional(:email) => String.t()}

  @typedoc "Data to update a user."
  @type update_params :: %{required(:id) => Ecto.UUID.t(), optional(:name) => String.t()}

  @doc """
  Lists users.

  Users are sorted by name.
  """
  @spec index(Plug.Conn.t(), index_params()) :: {:ok, [User.t()]}
  def index(_conn, _params), do: {:ok, []}

  @doc "Fetches a user."
  @spec show(Plug.Conn.t(), show_params()) :: {:ok, User.t()} | {:error, :not_found}
  def show(_conn, _params), do: {:error, :not_found}

  @doc "Creates a user."
  @spec create(Plug.Conn.t(), create_params()) ::
          {:created, User.t()} | {:error, Ecto.Changeset.t()}
  def create(_conn, _params), do: {:created, nil}

  @doc "Updates a user."
  @spec update(Plug.Conn.t(), update_params()) ::
          {:ok, User.t()} | {:error, :not_found | :forbidden}
  def update(_conn, _params), do: {:error, :forbidden}

  @doc "Removes a user."
  @deprecated "Users are deactivated instead"
  @spec delete(Plug.Conn.t(), show_params()) :: :no_content | {:error, :not_found}
  def delete(_conn, _params), do: :no_content

  @doc "Exports users the classic way."
  @spec export(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def export(conn, _params), do: conn

  @doc false
  @spec internal(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def internal(conn, _params), do: conn
end

defmodule Portolan.Test.PageController do
  @moduledoc "Not part of the API."
  use Phoenix.Controller, formats: [:html]

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params), do: conn
end

defmodule Portolan.Test.Router do
  @moduledoc """
  The example API.

  Used to test Portolan.
  """
  use Phoenix.Router

  alias Portolan.Test.PageController
  alias Portolan.Test.UserController

  get "/", PageController, :home

  scope "/api" do
    resources "/users", UserController, only: [:index, :show, :create, :update, :delete]
    get "/users/export", UserController, :export
    get "/internal", UserController, :internal
  end
end

defmodule Portolan.Test.BrokenController do
  @moduledoc """
  Actions with every kind of mistake.
  """
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  @type untyped_params :: %{required(:data) => term()}

  @typedoc """
  Parameters with an undocumented field.

  * `ghost` - does not exist
  """
  @type ghost_params :: %{required(:id) => pos_integer()}

  @typedoc "Identifies something."
  @type id_params :: %{required(:id) => pos_integer()}

  def no_docs(conn, _params), do: conn

  @doc "Has no spec."
  def no_spec(conn, _params), do: conn

  @doc "Uses term()."
  @spec untyped(Plug.Conn.t(), untyped_params()) :: {:ok, String.t()}
  def untyped(_conn, _params), do: {:ok, ""}

  @doc "Returns an unknown status."
  @spec unknown_status(Plug.Conn.t(), map()) :: {:error, :boom}
  def unknown_status(_conn, _params), do: {:error, :boom}

  @doc "Does not receive a conn."
  @spec no_conn(map(), map()) :: Plug.Conn.t()
  def no_conn(conn, _params), do: conn

  @doc "Uses a field documented for another one."
  @spec ghost(Plug.Conn.t(), ghost_params()) :: {:ok, String.t()}
  def ghost(_conn, _params), do: {:ok, ""}

  @doc "Mixes conn and data."
  @spec mixed_conn(Plug.Conn.t(), map()) :: {:ok, String.t()} | Plug.Conn.t()
  def mixed_conn(conn, _params), do: conn

  @doc "Returns a bare type."
  @spec bare_type(Plug.Conn.t(), map()) :: String.t()
  def bare_type(_conn, _params), do: ""

  @doc "Returns an unsupported error."
  @spec bad_error(Plug.Conn.t(), map()) :: {:error, String.t()}
  def bad_error(_conn, _params), do: {:error, ""}

  @doc "Returns data and no data for the same status."
  @spec mixed_bodies(Plug.Conn.t(), map()) :: {:ok, String.t()} | :ok
  def mixed_bodies(_conn, _params), do: :ok

  @doc "Uses guards."
  @spec guarded(Plug.Conn.t(), params) :: {:ok, String.t()} when params: map()
  def guarded(_conn, _params), do: {:ok, ""}

  @doc "Parameters are not a map."
  @spec scalar_params(Plug.Conn.t(), pos_integer()) :: {:ok, String.t()}
  def scalar_params(_conn, _params), do: {:ok, ""}

  @doc "Query parameter with a map."
  @spec map_query(Plug.Conn.t(), %{required(:filter) => %{name: String.t()}}) :: {:ok, String.t()}
  def map_query(_conn, _params), do: {:ok, ""}

  @doc "Returns a type that cannot be documented."
  @spec bad_ref(Plug.Conn.t(), map()) :: {:ok, Portolan.Fixtures.Types.any_term()}
  def bad_ref(_conn, _params), do: {:ok, nil}

  @doc "Path parameter missing in the params type."
  @spec missing_path(Plug.Conn.t(), id_params()) :: {:ok, String.t()}
  def missing_path(_conn, _params), do: {:ok, ""}
end

defmodule Portolan.Test.BrokenRouter do
  @moduledoc false
  use Phoenix.Router

  alias Portolan.Test.BrokenController

  get "/no_docs", BrokenController, :no_docs
  get "/no_spec", BrokenController, :no_spec
  get "/untyped", BrokenController, :untyped
  get "/unknown_status", BrokenController, :unknown_status
  get "/no_conn", BrokenController, :no_conn
  get "/ghost/:id", BrokenController, :ghost
  get "/missing/:slug", BrokenController, :missing_path
  get "/mixed_conn", BrokenController, :mixed_conn
  get "/bare_type", BrokenController, :bare_type
  get "/bad_error", BrokenController, :bad_error
  get "/mixed_bodies", BrokenController, :mixed_bodies
  get "/guarded", BrokenController, :guarded
  get "/scalar_params", BrokenController, :scalar_params
  get "/map_query", BrokenController, :map_query
  get "/bad_ref", BrokenController, :bad_ref
  get "/undocumented", Portolan.Test.UndocumentedController, :index
end

defmodule Portolan.Test.UndocumentedController do
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  @doc "Lists things."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: conn
end

defmodule Portolan.Test.Item do
  @moduledoc false

  @typedoc false
  @type t :: %{name: String.t()}
end

defmodule Portolan.Test.FileParams do
  @moduledoc false
  defstruct [:path]

  @typedoc """
  Identifies a file.

  * `path` - the segments of the file path
  """
  @type t :: %__MODULE__{path: [String.t()]}
end

defmodule Portolan.Test.EdgeController do
  @moduledoc "Edge cases."
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  alias Portolan.Test.FileParams
  alias Portolan.Test.Item

  @doc "Serves a file."
  @spec file(conn :: Plug.Conn.t(), params :: FileParams.t()) ::
          {:ok, Item.t()} | {:ok, [Item.t()]}
  def file(_conn, _params), do: {:ok, []}

  @doc "Searches."
  @spec search(Plug.Conn.t(), %{optional(:tags) => [String.t()], required(:limit) => 1..50}) ::
          {:ok, [String.t()]}
  def search(_conn, _params), do: {:ok, []}

  @doc "Uploads something."
  @spec upload(Plug.Conn.t(), %{optional(String.t()) => String.t()}) :: :accepted
  def upload(_conn, _params), do: :accepted

  @doc "The classic way, with a path parameter."
  @spec legacy(Plug.Conn.t(), Plug.Conn.params()) :: Plug.Conn.t()
  def legacy(conn, _params), do: conn
end

defmodule Portolan.Test.HiddenController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  use Portolan.Controller

  @doc "Hidden."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: conn
end

defmodule Portolan.Test.EdgeRouter do
  @moduledoc false
  use Phoenix.Router

  alias Portolan.Test.EdgeController

  get "/files/*path", EdgeController, :file
  get "/search", EdgeController, :search
  post "/upload", EdgeController, :upload
  get "/legacy/:id", EdgeController, :legacy
  get "/hidden", Portolan.Test.HiddenController, :index
end
