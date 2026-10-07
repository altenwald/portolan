# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0 - 2026-10-07

### Added

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
- Shared responses, sent by plugs before the actions: for every operation
  with the `:responses` option, a list or a `{module, function}`, and for
  the operations of a controller with
  `use Portolan.Controller, responses: [...]`. See
  `Portolan.SharedResponses`.
- `use Portolan.Controller, tag: "Users"` sets the tag of the operations
  of a controller.
- `use Portolan.Controller, cast: false` validates the parameters but gives
  them to the actions as Phoenix does, with string keys.
- A guide to adopt Portolan in an existing API, keeping what its clients
  receive.

### Changed

- `Portolan.Response.render/3` and `Portolan.Response.invalid_params/3`
  take the error renderer, `Portolan.ErrorRenderer.Default` by default.
- Operation ids are the name of the controller module and the action, as
  `UserController.show`, also for modules not ending in `Controller`.

### Fixed

- Struct fields with types that cannot be documented, as the associations
  of an Ecto schema, no longer fail when the JSON encoder leaves them out.

## 0.1.0 - 2026-10-06

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
- Guides to get started and to embed Scalar in a Phoenix page.
