defmodule Portolan.UITest do
  use ExUnit.Case, async: true

  alias Portolan.UI

  doctest Portolan.UI

  describe "render/2 with Scalar" do
    setup do
      %{html: UI.render(:scalar, title: "Shop API", url: "openapi.json")}
    end

    test "loads a pinned version with integrity", %{html: html} do
      assert html =~
               ~s(src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.73.0/dist/browser/standalone.js")

      assert html =~ ~s(integrity="sha384-)
      assert html =~ ~s(crossorigin="anonymous")
    end

    test "points to the document", %{html: html} do
      assert html =~ ~s[Scalar.createApiReference("#app", {"url":"openapi.json"})]
    end

    test "is a complete page", %{html: html} do
      assert html =~ "<!DOCTYPE html>"
      assert html =~ "<title>Shop API</title>"
      assert html =~ ~s(<meta charset="utf-8">)
    end
  end

  describe "render/2 with Swagger UI" do
    setup do
      %{html: UI.render(:swagger_ui, title: "Shop API", url: "openapi.json")}
    end

    test "loads a pinned version of the script and the styles with integrity", %{html: html} do
      assert html =~
               ~s(src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.33.1/swagger-ui-bundle.js")

      assert html =~ ~s(href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.33.1/swagger-ui.css")
      assert length(Regex.scan(~r/integrity="sha384-/, html)) == 2
    end

    test "points to the document", %{html: html} do
      assert html =~ ~s[SwaggerUIBundle({"dom_id":"#swagger-ui","url":"openapi.json"})]
    end
  end

  test "titles and URLs are escaped" do
    html = UI.render(:scalar, title: "<b>API</b> & co", url: "docs/</script>.json")
    assert html =~ "<title>&lt;b&gt;API&lt;/b&gt; &amp; co</title>"
    refute html =~ "</script>.json"
  end

  # Run with `mix test --include external` after changing the versions.
  @tag :external
  test "the integrity of every file matches the CDN" do
    for ui <- UI.uis(),
        html = UI.render(ui, title: "API", url: "openapi.json"),
        [_tag, url, integrity] <-
          Regex.scan(~r/(?:src|href)="(https:[^"]+)" integrity="([^"]+)"/, html) do
      {body, 0} = System.cmd("curl", ["--silent", "--fail", "--location", url])

      assert "sha384-" <> Base.encode64(:crypto.hash(:sha384, body)) == integrity, url
    end
  end

  test "uis/0 lists the available interfaces" do
    assert UI.uis() == [:scalar, :swagger_ui]
  end
end
