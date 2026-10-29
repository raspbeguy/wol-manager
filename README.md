# wol-manager

Wake-on-LAN HTTP API for OpenWrt, with host lists per user.

The administrator defines hosts (MAC addresses), lists of hosts, and users. Each user gets one or more lists and a token. With this token, the user can wake the hosts of these lists, and no other host.

Only the administrator (root) changes the configuration. API users have no account on the router: they have a token and nothing else.

## Packages

| Package | Repository | Content |
|---|---|---|
| `wol-manager` | this one | API endpoint `/cgi-bin/wol`, CLI tool `wol-manager`, configuration `/etc/config/wol_manager` |
| `luci-app-wol-manager` | [raspbeguy/luci-app-wol-manager](https://github.com/raspbeguy/luci-app-wol-manager) | LuCI page `Services > WoL Manager` for root, with French translation |

The code is `ucode`. The packages are architecture-independent (`PKGARCH:=all`) and target OpenWrt 25.12 and later (apk).

## Install

1. Download the apk from the [latest release](https://github.com/raspbeguy/wol-manager/releases/latest) and copy it to the router, for example to `/tmp`.
2. Install it. The package manager also installs the dependencies (`etherwake`, `ucode-mod-digest`, and others):
   ```sh
   apk update
   apk add --allow-untrusted /tmp/wol-manager-*.apk
   ```

## Configuration

### Model

- `host`: one machine. Options: `mac` (required), `name`, `iface`.
- `hostlist`: a list of hosts. Options: `name`, `list host`.
- `user`: an API user. Options: `enabled`, `list allow` (the lists this user can wake), `token_hash`.
- `globals`: `enabled` turns the API on or off. `iface` is the default interface for the magic packets.

Each user has their own lists. A list can be shared by several users, and a host can be in several lists. Section names contain only letters, digits, and `_`.

### Example with `uci`

```sh
uci set wol_manager.nas=host
uci set wol_manager.nas.name='NAS'
uci set wol_manager.nas.mac='AA:BB:CC:DD:EE:01'
uci set wol_manager.pc_alice=host
uci set wol_manager.pc_alice.mac='AA:BB:CC:DD:EE:02'
uci set wol_manager.srv_lab=host
uci set wol_manager.srv_lab.mac='AA:BB:CC:DD:EE:03'
uci set wol_manager.srv_lab.iface='br-lab'

uci set wol_manager.office=hostlist
uci add_list wol_manager.office.host='nas'
uci add_list wol_manager.office.host='pc_alice'
uci set wol_manager.lab=hostlist
uci add_list wol_manager.lab.host='nas'
uci add_list wol_manager.lab.host='srv_lab'

uci set wol_manager.alice=user
uci add_list wol_manager.alice.allow='office'
uci set wol_manager.bob=user
uci add_list wol_manager.bob.allow='lab'

uci commit wol_manager
wol-manager token alice
```

### CLI

| Command | Action |
|---|---|
| `wol-manager token <user>` | Creates a new token and prints it once. The previous token of the user stops working. |
| `wol-manager revoke <user>` | Removes the token of the user. |
| `wol-manager show [<user>]` | Shows the users, their lists, and the hosts of each list. |
| `wol-manager wake <list> [<host>]` | Wakes the hosts of a list, or one host of the list. |
| `wol-manager check` | Reports configuration errors: invalid MAC or interface, reference to a missing host or list. |

The router stores only the SHA-256 hash of each token. If a user loses their token, create a new one.

## API

Each request must have the header `Authorization: Bearer <token>`.

| Method | Path | Action |
|---|---|---|
| `GET` | `/cgi-bin/wol/lists` | Returns the lists of the user, with their hosts. |
| `POST` | `/cgi-bin/wol/lists/<list>/wake` | Wakes all hosts of the list. |
| `POST` | `/cgi-bin/wol/lists/<list>/hosts/<host>/wake` | Wakes one host of the list. |

| Status | Cause |
|---|---|
| `200` | The request succeeded. |
| `401` | The token is missing or unknown, or the user is disabled. |
| `403` | The list is not allowed for this user. |
| `404` | Unknown path, list, or host, or the host is not in the list. |
| `405` | Wrong HTTP method. |
| `500` | `etherwake` failed for one host or more. `results` gives the result for each host. |
| `503` | The API is disabled (`globals.enabled` is `0`). |

```sh
TOKEN=...   # given by the administrator

curl -H "Authorization: Bearer $TOKEN" https://router/cgi-bin/wol/lists
curl -X POST -H "Authorization: Bearer $TOKEN" https://router/cgi-bin/wol/lists/office/wake
curl -X POST -H "Authorization: Bearer $TOKEN" https://router/cgi-bin/wol/lists/office/hosts/nas/wake
```

```json
{ "list": "office", "results": [ { "host": "nas", "mac": "AA:BB:CC:DD:EE:01", "ok": true } ] }
```

## Security

- Use HTTPS: each request carries the token. To see the `uhttpd` configuration, run `uci show uhttpd.main`.
- If the certificate is self-signed, give it to `curl` with `--cacert`. Do not use `-k` in production.
- Do not open the API to the WAN without a dedicated firewall rule. `uhttpd` also serves LuCI on the same port.
- Each wake writes a line to the system log with the user, the list, the host, and the result. To read these lines, run `logread -e wol-manager`.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Troubleshooting

- If the API returns `401` with a correct token, make sure that the user is enabled: `wol-manager show <user>`.
- If a host is missing from a list, run `wol-manager check`. A host with an invalid MAC or interface is left out.
- If the API returns `500`, make sure that the interface of the host exists: `ip link show <iface>`.

## Development

```sh
sh scripts/lint.sh          # house style, ucode and shell syntax, VERSION
sh tests/unit/run.sh        # CLI and CGI against mocks of uci, digest and etherwake
sh scripts/build-apk.sh     # needs SDK_URL and SDK_SHA256, see .github/workflows/ci.yml
```

The integration tests boot OpenWrt in QEMU, install the apk, and check the API through `uhttpd`, the magic packets on `br-lan`, and the syslog lines. `tests/vm/setup.sh` needs `sudo` for a loop mount.

```sh
tests/vm/setup.sh && tests/vm/start.sh && tests/vm/wait.sh
tests/integration/run.sh /path/to/wol-manager-*.apk
tests/vm/stop.sh
```

## Releases

A release is a signed tag `vX.Y.Z` that matches `VERSION`. CI verifies the signature against `.github/release-signers.asc`, runs all tests, and attaches the apk to the GitHub release. The release notes come from the `CHANGELOG.md` section of the version.

## License

[MIT](LICENSE)
