# Phoenix 1.7 example

An application generated with `mix phx.new` 1.7 (without Ecto) that uses
Portolan, following the [getting started guide](../../guides/getting-started.md):

* `StoreWeb.ProductController` is a documented API
* `StoreWeb.ApiDocsController` embeds Scalar in a page of the application,
  following the [embedding guide](../../guides/embedding-scalar.md), with
  a link to download the OpenAPI document

Run it with:

```bash
mix setup
mix phx.server
```

And visit <http://localhost:4000/api-docs>.
