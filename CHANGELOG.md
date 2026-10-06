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
- Guides to get started and to embed Scalar in a Phoenix page.
