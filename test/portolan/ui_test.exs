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

  describe "render/2 with local assets" do
    test "points to the local copies, keeping their integrity" do
      html =
        UI.render(:swagger_ui, title: "API", url: "openapi.json", assets: {:local, "portolan"})

      assert html =~ ~s(src="portolan/swagger-ui-5.33.1.js" integrity="sha384-)
      assert html =~ ~s(href="portolan/swagger-ui-5.33.1.css" integrity="sha384-)
      refute html =~ "cdn.jsdelivr.net"
      refute html =~ "crossorigin"
    end
  end

  describe "assets/1" do
    test "describes the files of every interface" do
      assert [%{kind: :script, file: "scalar-1.73.0.js", url: "https://cdn.jsdelivr.net/" <> _}] =
               UI.assets(:scalar)

      assert [
               %{kind: :style, file: "swagger-ui-5.33.1.css"},
               %{kind: :script, file: "swagger-ui-5.33.1.js"}
             ] =
               UI.assets(:swagger_ui)
    end
  end

  describe "missing/2" do
    @tag :tmp_dir
    test "lists the files that are not installed", %{tmp_dir: tmp_dir} do
      assert UI.missing(:swagger_ui, tmp_dir) == ["swagger-ui-5.33.1.css", "swagger-ui-5.33.1.js"]

      File.write!(Path.join(tmp_dir, "swagger-ui-5.33.1.css"), "")
      assert UI.missing(:swagger_ui, tmp_dir) == ["swagger-ui-5.33.1.js"]
    end
  end

  describe "install_assets/3" do
    @describetag :tmp_dir

    defp asset(content) do
      %{
        kind: :script,
        name: "viewer",
        file: "viewer-2.0.0.js",
        url: "https://cdn.example.com/viewer@2.0.0.js",
        integrity: "sha384-" <> Base.encode64(:crypto.hash(:sha384, content))
      }
    end

    test "saves the files when their integrity matches", %{tmp_dir: tmp_dir} do
      fetch = fn "https://cdn.example.com/viewer@2.0.0.js" -> {:ok, "viewer"} end

      assert UI.install_assets([asset("viewer")], tmp_dir, fetch) ==
               {:ok, [Path.join(tmp_dir, "viewer-2.0.0.js")]}

      assert File.read!(Path.join(tmp_dir, "viewer-2.0.0.js")) == "viewer"
    end

    test "removes the files of other versions", %{tmp_dir: tmp_dir} do
      for file <- ["viewer-1.0.0.js", "viewer-1.0.0.css", "other-1.0.0.js"],
          do: File.write!(Path.join(tmp_dir, file), "")

      UI.install_assets([asset("viewer")], tmp_dir, fn _url -> {:ok, "viewer"} end)

      assert Enum.sort(File.ls!(tmp_dir)) == [
               "other-1.0.0.js",
               "viewer-1.0.0.css",
               "viewer-2.0.0.js"
             ]
    end

    test "refuses files whose integrity does not match", %{tmp_dir: tmp_dir} do
      assert {:error, message} =
               UI.install_assets([asset("viewer")], tmp_dir, fn _url -> {:ok, "tampered"} end)

      assert message =~ "integrity"
      assert message =~ "viewer@2.0.0.js"
      assert File.ls!(tmp_dir) == []
    end

    test "reports download errors", %{tmp_dir: tmp_dir} do
      assert {:error, message} =
               UI.install_assets([asset("viewer")], tmp_dir, fn _url -> {:error, "timeout"} end)

      assert message =~ "timeout"
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

  @tag :external
  @tag :tmp_dir
  test "installs every interface from the CDN", %{tmp_dir: tmp_dir} do
    for ui <- UI.uis() do
      fetch = fn url ->
        case System.cmd("curl", ["--silent", "--fail", "--location", url]) do
          {body, 0} -> {:ok, body}
          {_body, status} -> {:error, "curl exited with #{status}"}
        end
      end

      assert {:ok, [_ | _]} = UI.install(ui, tmp_dir, fetch)
      assert UI.missing(ui, tmp_dir) == []
    end
  end

  test "uis/0 lists the available interfaces" do
    assert UI.uis() == [:scalar, :swagger_ui]
  end
end
