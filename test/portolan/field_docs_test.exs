defmodule Portolan.FieldDocsTest do
  use ExUnit.Case, async: true

  alias Portolan.FieldDocs

  doctest Portolan.FieldDocs

  test "extracts field items and removes them from the description" do
    text = """
    A user of the application.

    * `id` - unique identifier
    * `email` - contact address,
      when known

    Users are created on sign up.
    """

    assert FieldDocs.parse(text) ==
             {"A user of the application.\n\nUsers are created on sign up.",
              %{"id" => "unique identifier", "email" => "contact address, when known"}}
  end

  test "accepts dashes as bullets and colons as separators" do
    assert FieldDocs.parse("- `id`: the identifier\n- `name` – the name") ==
             {nil, %{"id" => "the identifier", "name" => "the name"}}
  end

  test "keeps other list items" do
    text = "Roles:\n\n* admin can do everything\n* `id` - identifier"

    assert FieldDocs.parse(text) ==
             {"Roles:\n\n* admin can do everything", %{"id" => "identifier"}}
  end

  test "text without fields" do
    assert FieldDocs.parse("Just a description.") == {"Just a description.", %{}}
  end
end
