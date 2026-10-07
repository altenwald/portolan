defmodule Portolan.SharedResponsesTest do
  use ExUnit.Case, async: true

  alias Portolan.Compiler
  alias Portolan.Test.AccountRouter
  alias Portolan.Test.AccountSecurity

  doctest Portolan.SharedResponses

  @opts [
    title: "Accounts",
    version: "1.0.0",
    security_schemes: %{bearer: %{type: "http", scheme: "bearer"}, api_key: %{type: "apiKey"}}
  ]

  defp build!(opts) do
    assert {:ok, %{document: document}, _warnings} =
             Compiler.build(AccountRouter, Keyword.merge(@opts, opts))

    document
  end

  defp responses(document, path, method), do: document["paths"][path][method]["responses"]

  test "static responses are added to every operation" do
    document = build!(responses: [:service_unavailable, unauthorized: :text])

    for {path, method} <- [{"/login", "post"}, {"/accounts/{id}", "get"}] do
      responses = responses(document, path, method)

      assert responses["503"]["content"]["application/json"]["schema"] ==
               %{"$ref" => "#/components/schemas/Portolan.Error"}

      assert responses["401"]["content"] == %{
               "text/plain" => %{"schema" => %{"type" => "string"}}
             }
    end
  end

  test "a callback decides the responses of each action" do
    document = build!(responses: {AccountSecurity, :responses})

    refute responses(document, "/login", "post")["401"]
    assert responses(document, "/accounts/{id}", "get")["401"]
  end

  test "controllers add the responses of their plugs" do
    document = build!([])

    assert responses(document, "/echo", "get")["429"]
    refute responses(document, "/accounts/{id}", "get")["429"]
  end

  test "a status already in the spec keeps its body" do
    document = build!(responses: [:not_found])

    assert responses(document, "/accounts/{id}", "get")["404"]["content"]["application/json"] ==
             %{"schema" => %{"$ref" => "#/components/schemas/Portolan.Error"}}
  end

  test "responses without body" do
    document = build!(responses: [not_modified: nil])
    assert responses(document, "/login", "post")["304"] == %{"description" => "Not Modified"}
  end

  test "invalid options are reported" do
    assert {:error, [issue]} =
             Compiler.build(AccountRouter, Keyword.put(@opts, :responses, [:nope]))

    assert issue.message =~ "unknown status :nope"

    assert {:error, [issue]} =
             Compiler.build(
               AccountRouter,
               Keyword.put(@opts, :responses, {AccountSecurity, :nope})
             )

    assert issue.message =~ "AccountSecurity.nope/2 does not exist"
  end
end
