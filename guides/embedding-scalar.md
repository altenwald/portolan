# Embedding Scalar

Portolan generates `priv/static/openapi.html`, a page showing the
documentation with [Scalar](https://scalar.com). It is a page of its own,
without the layout of your application.

This guide shows the documentation inside a page of your application
instead, with its layout, navigation and, if you want, its
authentication, and keeps the OpenAPI document available to download.

It assumes Portolan is already set up, see
[Getting started](getting-started.md). The steps work for Phoenix 1.7 and
1.8, and the templates of both versions are shown.

## 1. Stop generating the standalone page

The page of the application replaces `openapi.html`, so disable it in
`config/config.exs`:

```elixir
config :my_app, Portolan, router: MyAppWeb.Router, ui: false
```

`priv/static/openapi.json` is still generated on every compilation.

## 2. Serve the document

Scalar loads the document from the browser, so it must be served. Keep it
in `static_paths/0`, in `lib/my_app_web.ex`:

```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt openapi.json)
```

## 3. Add the routes

In the router, in a scope using the `:browser` pipeline:

```elixir
scope "/", MyAppWeb do
  pipe_through :browser

  get "/", PageController, :home
  get "/api-docs", ApiDocsController, :show
  get "/api-docs/openapi.json", ApiDocsController, :download
end
```

The second route is optional, see [step 6](#6-download-the-document).

## 4. Write the controller

```elixir
defmodule MyAppWeb.ApiDocsController do
  use MyAppWeb, :controller

  def show(conn, _params) do
    render(conn, :show,
      page_title: "API",
      scalar_assets: Portolan.UI.assets(:scalar),
      scalar_config: Portolan.UI.scalar_config()
    )
  end

  def download(conn, _params) do
    send_download(conn, {:file, Application.app_dir(:my_app, "priv/static/openapi.json")},
      filename: "my-app-openapi.json",
      content_type: "application/json"
    )
  end
end
```

This is a regular HTML controller, it does not use
`Portolan.Controller`, so it stays out of the OpenAPI document.

The page gets two things from Portolan:

* `Portolan.UI.assets/1` - the files of Scalar: the URL of the version
  Portolan was released with and its
  [subresource integrity](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity).
  Updating Portolan updates them, always with a version that was checked.
* `Portolan.UI.scalar_config/0` - the configuration Portolan uses for its
  own page. It disables the telemetry and the AI features of Scalar,
  which send data to its services. Merge your own options to change it,
  see the [Scalar configuration](https://github.com/scalar/scalar/blob/main/documentation/configuration.md).

## 5. Write the template

Add the HTML module next to the controller,
`lib/my_app_web/controllers/api_docs_html.ex`:

```elixir
defmodule MyAppWeb.ApiDocsHTML do
  use MyAppWeb, :html

  embed_templates "api_docs_html/*"
end
```

And the template, `lib/my_app_web/controllers/api_docs_html/show.html.heex`.

**Phoenix 1.8** wraps the content of every page in the `Layouts.app`
component:

```heex
<Layouts.app flash={@flash}>
  <div class="mb-6 flex items-center justify-between">
    <h1 class="text-2xl font-semibold">API</h1>
    <.link href={~p"/api-docs/openapi.json"}>Download the OpenAPI document</.link>
  </div>

  <div id="api-docs" data-document={~p"/openapi.json"} data-options={JSON.encode!(@scalar_config)}>
  </div>

  <script
    :for={asset <- @scalar_assets}
    src={asset.url}
    integrity={asset.integrity}
    crossorigin="anonymous"
  >
  </script>
  <script>
    const docs = document.getElementById("api-docs");

    Scalar.createApiReference("#api-docs", {
      ...JSON.parse(docs.dataset.options),
      url: docs.dataset.document
    });
  </script>
</Layouts.app>
```

**Phoenix 1.7** applies the layout from the controller, so the template
has the content only:

```heex
<div class="mb-6 flex items-center justify-between">
  <h1 class="text-2xl font-semibold">API</h1>
  <.link href={~p"/api-docs/openapi.json"}>Download the OpenAPI document</.link>
</div>

<div id="api-docs" data-document={~p"/openapi.json"} data-options={JSON.encode!(@scalar_config)}>
</div>

<script
  :for={asset <- @scalar_assets}
  src={asset.url}
  integrity={asset.integrity}
  crossorigin="anonymous"
>
</script>
<script>
  const docs = document.getElementById("api-docs");

  Scalar.createApiReference("#api-docs", {
    ...JSON.parse(docs.dataset.options),
    url: docs.dataset.document
  });
</script>
```

The URL of the document and the configuration are given as `data-`
attributes, so `~p` checks the path and HEEx escapes the values. Two
details matter:

* **Do not use `api-reference` as the id of the element.** Scalar mounts
  itself, without any configuration, on an element with that id as soon
  as it loads, and you would end up with two instances.
* **Give `createApiReference` a selector, not the element.** When it gets
  an element, Scalar reads its configuration from the `data-` attributes
  of the element instead of from the second argument.

Visit <http://localhost:4000/api-docs> to see the documentation inside
your layout.

## 6. Download the document

The document is a static file, so there are three ways to download it,
from simpler to more control:

* **The button of Scalar.** `Portolan.UI.scalar_config/0` sets
  `documentDownloadType` to `"json"`, so Scalar offers the document as it
  is generated.
* **A link with the `download` attribute.** The browser saves the file
  instead of opening it:

  ```heex
  <a href={~p"/openapi.json"} download="my-app-openapi.json">Download the OpenAPI document</a>
  ```

* **The controller action of step 4.** It sends the file with a
  `content-disposition: attachment` header, so it is saved even by clients
  that ignore the `download` attribute, and it can go through the
  pipelines of the router, for example to require authentication.

## Without the CDN

Scalar is loaded from the jsDelivr CDN by default. To serve it from your
application, install a copy of its files:

```bash
mix portolan.ui.install scalar
```

The interface is given as argument because `ui: false` disables the one
of Portolan. The files are saved in `priv/static/portolan`, after checking
their integrity. Commit them, add `portolan` to `static_paths/0` and load
them from there:

```heex
<script
  :for={asset <- @scalar_assets}
  src={~p"/portolan/#{asset.file}"}
  integrity={asset.integrity}
>
</script>
```

Run the task again after updating Portolan: the names of the files include
their version, so a missing install is a missing file, never a different
one. A test catches it before deploying:

```elixir
test "the files of Scalar are installed" do
  assert Portolan.UI.missing(:scalar, "priv/static/portolan") == []
end
```

## Content Security Policy

The `put_secure_browser_headers` plug of new Phoenix applications sends
`content-security-policy: base-uri 'self'; frame-ancestors 'self';`, which
does not restrict scripts, so Scalar works as it is. If your policy
restricts scripts or connections, the page needs:

* `script-src` to allow `https://cdn.jsdelivr.net`, unless the files are
  served from the application
* the inline script to be allowed, for example with a nonce
* `connect-src` to allow the servers of the API, to try requests from
  the documentation
