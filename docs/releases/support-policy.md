# Support Policy

This document defines the minimum supported language/runtime versions for
`jido_skill_graph`.

## Minimum Supported Versions

- Elixir: `1.17`
- Erlang/OTP: `27`

## Development Toolchain

The repository pins a local development toolchain in `.tool-versions`:

- `erlang 27.3`
- `elixir 1.17.3-otp-27`

Using `asdf install` in the project root will provision the pinned versions.

## Upgrade Cadence

- Patch-level upgrades on supported majors may be adopted at any time.
- Minimum supported Elixir/OTP versions may be raised only in a `MINOR` or
  `MAJOR` release, with an explicit note in `CHANGELOG.md`.
