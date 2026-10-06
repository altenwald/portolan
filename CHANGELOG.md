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
