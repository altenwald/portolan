# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Portolan.Typespec` converts typespecs into `Portolan.Type` descriptions,
  reporting unsupported types as `Portolan.Issue`s with file and line.
- `Portolan.JSONSchema` builds JSON Schema 2020-12 from type descriptions.
- `Portolan.Cast` casts path, query and body parameters into the values
  described by a type, without creating atoms from user input.
- `Mix.Tasks.Compile.Portolan` generates the OpenAPI 3.1 or 3.2 document of
  a Phoenix router, reporting missing or invalid information as compiler
  diagnostics.
- `Portolan.Controller` adds a controller to the documented API, casts the
  parameters of its actions and renders their results.
- `Portolan.Contracts` keeps the parameter types needed at runtime in
  `priv/portolan/contracts.etf`.
- `Portolan.Response` turns `{:ok, data}`, `{status, data}`, statuses,
  `{:error, reason}` and changesets into responses.
- Markdown files can be added to the document as documentation pages.
- `Portolan.UI` generates a static page showing the document with Scalar or
  Swagger UI, loaded from jsDelivr with pinned versions and subresource
  integrity.
- `mix portolan.ui.install` installs a verified local copy of the interface,
  used with `ui_assets: :local`.
- The Scalar page disables the telemetry and AI features of Scalar, see
  `Portolan.UI.scalar_config/0`.
- Guides to get started, to adopt Portolan in an existing API, and to
  embed Scalar in a Phoenix page.
- Security schemes, with the `:security_schemes` option, and the security
  requirements of each operation, from `@doc security: ...`, the
  `:security` option or a `{module, function}` called with the controller
  and the action. See `Portolan.Security`.
- `Portolan.ErrorRenderer`, configured with `:error_renderer`, to answer
  errors with a format of your own, its schemas and the status of
  validation errors, both at runtime and in the document.
  `Portolan.ErrorRenderer.Default` keeps the format of Phoenix and `422`.
- `{:error, {:not_found, "Project not found"}}` sends a message with the
  error, given to the renderer.
- `Portolan.Text` answers plain text, documented as `text/plain`, also
  next to JSON for the same status.
- Responses sharing a status, such as an error and the validation errors,
  are documented as alternatives with `oneOf`.
- Struct fields left out of the JSON, as with
  `@derive {Jason.Encoder, only: [...]}` or `except: [...]`, are left out of
  the document and of the parameters too. See `Portolan.EncodedFields`.
- `use Portolan.Controller, tag: "Users"` sets the tag of the operations
  of a controller.
- `use Portolan.Controller, cast: false` validates the parameters but gives
  them to the actions as Phoenix does, with string keys.
