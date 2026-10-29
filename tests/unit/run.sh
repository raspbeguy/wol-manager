#!/bin/sh
# CLI and CGI tests against the mocks in tests/mock: runs on any host with ucode.
set -eu
cd "$(dirname "$0")/../.."

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir "$T/lib"
cp tests/mock/uci.uc tests/mock/digest.uc "$T/lib/"
sed "s#'/usr/bin/etherwake'#'$PWD/tests/mock/bin/etherwake'#" files/wol_manager.uc > "$T/lib/wol_manager.uc"
cp tests/unit/config.json "$T/config.json"

export MOCK_UCI="$T/config.json" MOCK_LOG="$T/calls.log"
PATH="$PWD/tests/mock/bin:$PATH"

fail=0

expect() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$2" "$3"
		fail=1
	fi
}

cli() { ucode -L "$T/lib" files/wol-manager.cli "$@"; }
rc() { "$@" >/dev/null 2>&1 && echo 0 || echo $?; }

# Arguments: method, path, optional token.
cgi() {
	env REQUEST_METHOD="$1" PATH_INFO="$2" HTTP_AUTHORIZATION="${3:+Bearer $3}" \
		ucode -L "$T/lib" files/wol.cgi | tr -d '\r'
}
status() { cgi "$@" | sed -n '1s/^Status: \([0-9]*\).*/\1/p'; }

# Prints a ucode expression evaluated on the JSON body of the response, bound to `r`.
field() {
	expr=$1
	shift
	cgi "$@" | tail -n 1 | ucode -e "import { stdin } from 'fs'; let r = json(stdin.read('all')); print($expr, '\n');"
}

echo "--- configuration check"
expect "check lists every invalid entry" \
"host 'bad': invalid MAC address '02:00:00:00:00'
host 'badif': invalid interface 'br-lan; reboot'
hostlist 'labo': unknown or invalid host 'ghost'
user 'eve': unknown hostlist 'missing'" "$(cli check || true)"
expect "check exits 1 when the configuration has errors" 1 "$(rc cli check)"

echo "--- tokens"
ALICE=$(cli token alice 2>/dev/null)
BOB=$(cli token bob 2>/dev/null)
DAVE=$(cli token dave 2>/dev/null)
EVE=$(cli token eve 2>/dev/null)
expect "a token is 64 lowercase hex digits" 1 "$(echo "$ALICE" | grep -cE '^[0-9a-f]{64}$')"
expect "two tokens differ" 1 "$([ "$ALICE" != "$BOB" ] && echo 1)"
expect "the clear token is not stored" 0 "$(grep -c "$ALICE" "$T/config.json" || true)"
expect "token for an unknown user fails" 1 "$(rc cli token nobody)"
expect "token for a section of another type fails" 1 "$(rc cli token nas)"
expect "token for an invalid section name fails" 1 "$(rc cli token 'a.b')"

echo "--- authentication"
expect "no token: 401" 401 "$(status GET /lists)"
expect "unknown token: 401" 401 "$(status GET /lists 0000000000000000000000000000000000000000000000000000000000000000)"
expect "malformed token: 401" 401 "$(status GET /lists "x'; rm -rf /")"
expect "disabled user: 401" 401 "$(status GET /lists "$DAVE")"
expect "401 names the Bearer scheme" 1 "$(cgi GET /lists | grep -c '^WWW-Authenticate: Bearer')"
expect "the scheme is case-insensitive" 200 "$(env REQUEST_METHOD=GET PATH_INFO=/lists HTTP_AUTHORIZATION="bearer $ALICE" \
	ucode -L "$T/lib" files/wol.cgi | tr -d '\r' | sed -n '1s/^Status: \([0-9]*\).*/\1/p')"

echo "--- authorization"
expect "alice sees only her list" bureau "$(field "join(',', map(r.lists, (l) => l.id))" GET /lists "$ALICE")"
expect "hosts and MACs of the list, MAC in upper case" "nas=AA:BB:CC:DD:EE:01,pc_alice=AA:BB:CC:DD:EE:02" \
	"$(field "join(',', map(r.lists[0].hosts, (h) => h.id + '=' + h.mac))" GET /lists "$ALICE")"
expect "invalid hosts are left out of a list" "nas,srv_labo" "$(field "join(',', map(r.lists[0].hosts, (h) => h.id))" GET /lists "$BOB")"
expect "a user whose only list is missing sees no list" 0 "$(field "length(r.lists)" GET /lists "$EVE")"
expect "list not allowed: 403" 403 "$(status POST /lists/labo/wake "$ALICE")"
expect "unknown list: 404" 404 "$(status POST /lists/nope/wake "$ALICE")"
expect "host not in the list: 404" 404 "$(status POST /lists/bureau/hosts/srv_labo/wake "$ALICE")"
expect "unknown endpoint: 404" 404 "$(status POST /lists/bureau "$ALICE")"
expect "GET on a wake endpoint: 405" 405 "$(status GET /lists/bureau/wake "$ALICE")"
expect "405 names the allowed method" 1 "$(cgi GET /lists/bureau/wake "$ALICE" | grep -c '^Allow: POST')"
expect "POST on /lists: 405" 405 "$(status POST /lists "$ALICE")"

echo "--- wake"
: > "$MOCK_LOG"
expect "wake a list: 200" 200 "$(status POST /lists/bureau/wake "$ALICE")"
expect "etherwake gets the interface and the MAC of each host" \
"etherwake -i br-lan AA:BB:CC:DD:EE:01
etherwake -i lan2 AA:BB:CC:DD:EE:02" "$(grep '^etherwake' "$MOCK_LOG")"
expect "each wake is logged with the user and the list" 2 "$(grep -c '^logger -t wol-manager user=alice list=bureau host=.* result=ok$' "$MOCK_LOG")"
: > "$MOCK_LOG"
expect "wake one host of a list" "pc_alice" "$(field "join(',', map(r.results, (x) => x.host))" POST /lists/bureau/hosts/pc_alice/wake "$ALICE")"
expect "only that host is woken" 1 "$(grep -c '^etherwake' "$MOCK_LOG")"
expect "a failed etherwake gives 500" 500 "$(status POST /lists/labo/wake "$BOB")"
expect "the 500 body gives the result of each host" "nas=true,srv_labo=false" \
	"$(field "join(',', map(r.results, (x) => x.host + '=' + x.ok))" POST /lists/labo/wake "$BOB")"

echo "--- token lifecycle"
OLD=$ALICE
ALICE=$(cli token alice 2>/dev/null)
expect "a new token replaces the old one" 401 "$(status GET /lists "$OLD")"
expect "the new token works" 200 "$(status GET /lists "$ALICE")"
cli revoke bob
expect "a revoked token is refused" 401 "$(status GET /lists "$BOB")"
expect "revoke of an unknown user fails" 1 "$(rc cli revoke nobody)"

echo "--- CLI"
expect "wake from the CLI exits 1 if a host fails" 1 "$(rc cli wake labo)"
expect "wake of one host from the CLI" 0 "$(rc cli wake bureau nas)"
expect "wake of a host outside the list fails" 1 "$(rc cli wake bureau srv_labo)"
expect "show prints each user" "alice bob dave eve" "$(cli show | grep -v '^ ' | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
expect "show of an unknown user fails" 1 "$(rc cli show nobody)"
expect "no command prints the usage and fails" 1 "$(rc cli)"

echo "--- global switch"
sed -i 's/"enabled": "1", "iface"/"enabled": "0", "iface"/' "$T/config.json"
expect "disabled API: 503" 503 "$(status GET /lists "$ALICE")"

exit "$fail"
