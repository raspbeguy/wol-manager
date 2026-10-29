# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/). The API (paths, status codes, JSON
fields) and the UCI options are the public surface.

## [Unreleased]

### Added

- HTTP API at `/cgi-bin/wol`: list the allowed host lists, wake a list, wake one host of a list.
- Bearer token per user. Only the SHA-256 hash of a token is stored.
- UCI configuration `wol_manager`: hosts, host lists, users and the lists each user can wake.
- CLI `wol-manager`: `token`, `revoke`, `show`, `wake`, `check`.
- One syslog line per wake, with the user, the list, the host and the result.
