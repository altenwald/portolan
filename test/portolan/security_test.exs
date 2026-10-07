defmodule Portolan.SecurityTest do
  use ExUnit.Case, async: true

  alias Portolan.Compiler
  alias Portolan.Test.AccountRouter
  alias Portolan.Test.AccountSecurity

  doctest Portolan.Security

  @schemes %{
    bearer: %{type: "http", scheme: "bearer"},
    api_key: %{type: "apiKey", in: "header", name: "x-api-key"}
  }

  @opts [title: "Accounts", version: "1.0.0", security_schemes: @schemes]

  defp build!(opts) do
    assert {:ok, %{document: document}, _warnings} =
             Compiler.build(AccountRouter, Keyword.merge(@opts, opts))

    document
  end

  defp errors(opts) do
    assert {:error, issues} = Compiler.build(AccountRouter, Keyword.merge(@opts, opts))
    Enum.map(issues, & &1.message)
  end

  test "the schemes are components of the document" do
    document = build!([])

    assert document["components"]["securitySchemes"] == %{
             "bearer" => %{"type" => "http", "scheme" => "bearer"},
             "api_key" => %{"type" => "apiKey", "in" => "header", "name" => "x-api-key"}
           }
  end

  test "without requirements, operations say nothing about security" do
    document = build!([])
    refute Map.has_key?(document["paths"]["/accounts/{id}"]["get"], "security")
  end

  test "static requirements apply to every operation" do
    document = build!(security: [bearer: []])

    assert document["paths"]["/accounts/{id}"]["get"]["security"] == [%{"bearer" => []}]
    assert document["paths"]["/login"]["post"]["security"] == [%{"bearer" => []}]
  end

  test "a callback gives the requirements of each action" do
    document = build!(security: {AccountSecurity, :requirements})

    assert document["paths"]["/accounts/{id}"]["get"]["security"] == [%{"bearer" => []}]
    assert document["paths"]["/login"]["post"]["security"] == []
  end

  test "the @doc of an action wins over the configuration" do
    document = build!(security: {AccountSecurity, :requirements})

    assert document["paths"]["/accounts/{id}"]["delete"]["security"] ==
             [%{"bearer" => ["admin"]}, %{"api_key" => []}]
  end

  test "requirements need declared schemes" do
    assert [message] = errors(security_schemes: %{bearer: %{type: "http", scheme: "bearer"}})
    assert message =~ "AccountController.delete/2 requires the security schemes api_key"
  end

  test "invalid options are reported" do
    assert [schemes, security] = errors(security_schemes: %{bearer: "http"}, security: :bearer)
    assert schemes =~ ":security_schemes"
    assert security =~ ":security option"

    assert [missing] = errors(security: {AccountSecurity, :missing})
    assert missing =~ "AccountSecurity.missing/2 does not exist"
  end
end
