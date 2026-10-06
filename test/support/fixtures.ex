defmodule Portolan.Fixtures.User do
  @moduledoc false
  defstruct [:id, :name, :email, :status, :tags]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          email: String.t() | nil,
          status: status(),
          tags: [String.t()]
        }

  @type status :: :active | :inactive
end

defmodule Portolan.Fixtures.Types do
  @moduledoc false

  @type text :: String.t()
  @type binary_string :: binary()
  @type integer_any :: integer()
  @type positive :: pos_integer()
  @type non_negative :: non_neg_integer()
  @type negative :: neg_integer()
  @type range :: 1..100
  @type negative_range :: -5..5
  @type float_value :: float()
  @type number_value :: number()
  @type boolean_value :: boolean()
  @type literal_atom :: :ok
  @type literal_integer :: 3
  @type literal_true :: true
  @type null :: nil
  @type nullable :: integer() | nil
  @type enum :: :a | :b | :c
  @type list_of :: [integer()]
  @type list_call :: list(boolean())
  @type nonempty :: nonempty_list(String.t())
  @type uuid :: Ecto.UUID.t()
  @type date :: Date.t()
  @type datetime :: DateTime.t()
  @type naive_datetime :: NaiveDateTime.t()
  @type time :: Time.t()
  @type decimal :: Decimal.t()
  @type local_ref :: text()
  @type remote_ref :: Portolan.Fixtures.User.t()
  @type params :: %{required(:id) => pos_integer(), optional(:filter) => String.t()}
  @type keyword_map :: %{name: String.t(), age: non_neg_integer()}
  @type string_map :: %{optional(String.t()) => integer()}
  @type page(item) :: %{items: [item], total: non_neg_integer()}
  @type user_page :: page(Portolan.Fixtures.User.t())

  @type any_term :: term()
  @type any_value :: any()
  @type any_atom :: atom()
  @type any_map :: map()
  @type tuple_value :: {integer(), integer()}
  @type pid_value :: pid()
  @type empty_list :: []
  @type integer_keys :: %{required(1) => String.t()}
  @type many_errors :: %{a: term(), b: pid()}
  @type two_string_keys :: %{optional(String.t()) => integer(), optional(binary()) => float()}
  @type invalid_key :: %{optional(term()) => integer()}

  @opaque secret :: String.t()
end
