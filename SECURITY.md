# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: **[Report a vulnerability](https://github.com/raspbeguy/wol-manager/security/advisories/new)**.

Expect a first response within a week. That is a rough figure rather than an SLA.

## What counts as a vulnerability here

wol-manager runs as root under `uhttpd` and sends raw Ethernet frames. The boundary is the token: a token holder must be able to wake the hosts of their lists, and do nothing else.

- Waking a host, or reading a list, that the token does not allow.
- A request that succeeds without a valid token, with the token of a disabled user, or with a revoked or replaced token.
- A way to recover a token from what the router stores or logs.
- Command or argument injection into `etherwake`, `logger`, or any other process the endpoint starts.

## Out of scope

- Tokens sent over plain HTTP. Serving the API over HTTPS is the operator's job, and the README says so.
- `uhttpd`, LuCI, and rpcd themselves.
- An operator with root on the router doing something destructive on purpose.

## Supported versions

The current release only. Fixes ship as a new version rather than as backports.
