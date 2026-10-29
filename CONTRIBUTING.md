# Contributing to wol-manager

## What this is

A Wake-on-LAN HTTP API for OpenWrt with host lists per user: a `ucode` library, a CGI endpoint served by `uhttpd`, and a CLI. The LuCI page lives in [luci-app-wol-manager](https://github.com/raspbeguy/luci-app-wol-manager).

## Dev loop

```sh
sh scripts/lint.sh        # what CI gates on: house style, ucode and shell syntax, VERSION
sh tests/unit/run.sh      # CLI and CGI against mocks, runs anywhere with ucode
sh scripts/build-apk.sh   # builds the package against the OpenWrt SDK
```

The integration tests in `tests/integration` run against a QEMU VM (`tests/vm`). CI runs them on every pull request.

## What kinds of changes are welcome

- Anything that makes the access control easier to audit, or harder to get wrong.
- Fixes for the behaviour on real hardware: interfaces, bridges, VLANs, NICs that need broadcast frames.
- Tests that catch a defect the current ones miss.

## Style

No em-dashes anywhere. Comments explain why, not what.

## Commit and PR style

One-line subject in the imperative. Explain in the body why the change is needed rather than restating the diff. Every change lands via a pull request and adds an entry under `## [Unreleased]` in `CHANGELOG.md` when users can see it.
