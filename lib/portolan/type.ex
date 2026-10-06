defmodule Portolan.Type do
  @moduledoc """
  The intermediate representation Portolan uses for types.

  Typespecs are converted into this representation by `Portolan.Typespec`.
  From here the same description is used to build JSON Schemas
  (`Portolan.JSONSchema`) and to cast incoming parameters (`Portolan.Cast`),
  so the documentation and the validation can never disagree.

  | Typespec                                   | Representation                       |
  | ------------------------------------------ | ------------------------------------ |
  | `String.t()`, `binary()`                   | `{:string, nil}`                     |
  | `Ecto.UUID.t()`                            | `{:string, :uuid}`                   |
  | `Date.t()`                                 | `{:string, :date}`                   |
  | `DateTime.t()`                             | `{:string, :date_time}`              |
  | `NaiveDateTime.t()`                        | `{:string, :naive_date_time}`        |
  | `Time.t()`                                 | `{:string, :time}`                   |
  | `Decimal.t()`                              | `{:string, :decimal}`                |
  | `integer()`                                | `{:integer, nil, nil}`               |
  | `pos_integer()`                            | `{:integer, 1, nil}`                 |
  | `non_neg_integer()`                        | `{:integer, 0, nil}`                 |
  | `neg_integer()`                            | `{:integer, nil, -1}`                |
  | `1..100`                                   | `{:integer, 1, 100}`                 |
  | `float()`                                  | `:float`                             |
  | `number()`                                 | `:number`                            |
  | `boolean()`                                | `:boolean`                           |
  | `nil`                                      | `:null`                              |
  | `:active`, `3`, `true`                     | `{:literal, value}`                  |
  | `a \\| b`                                   | `{:union, [a, b]}`                   |
  | `[t]`, `list(t)`                           | `{:list, t, false}`                  |
  | `nonempty_list(t)`                         | `{:list, t, true}`                   |
  | `%{required(:a) => t, optional(:b) => t}`  | `{:map, [{:a, true, t}, {:b, false, t}], nil}` |
  | `%{optional(String.t()) => t}`             | `{:map, [], t}`                      |
  | `%MyStruct{a: t}`                          | `{:struct, MyStruct, [{:a, true, t}]}` |
  | `my_type()`, `MyMod.my_type(arg)`          | `{:ref, module, name, args}`         |
  """

  @typedoc """
  Extra information about the content of a string.
  """
  @type format :: :uuid | :date | :date_time | :naive_date_time | :time | :decimal

  @typedoc """
  A map or struct field: its name, whether it is required and its type.
  """
  @type field :: {name :: atom(), required :: boolean(), t()}

  @typedoc """
  A type description.
  """
  @type t ::
          {:string, format() | nil}
          | {:integer, integer() | nil, integer() | nil}
          | :float
          | :number
          | :boolean
          | :null
          | {:literal, atom() | integer()}
          | {:list, t(), nonempty :: boolean()}
          | {:map, [field()], additional :: t() | nil}
          | {:struct, module(), [field()]}
          | {:union, [t(), ...]}
          | {:ref, module(), atom(), [t()]}
          | {:var, atom()}
end
