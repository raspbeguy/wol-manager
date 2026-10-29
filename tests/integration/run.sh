#!/bin/sh
# Installs the wol-manager apk in the QEMU VM of tests/vm, then checks the API
# through uhttpd, the frames on the wire and the syslog lines.
set -eu
cd "$(dirname "$0")/../.."

APK=${1:?usage: $0 <wol-manager apk>}
SSH=tests/vm/ssh.sh
BASE=http://127.0.0.1:8223/cgi-bin/wol
fail=0

expect() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$2" "$3"
		fail=1
	fi
}

# Arguments: method, path, optional token.
status() {
	if [ -n "${3:-}" ]; then
		curl -s -o /dev/null -w '%{http_code}' -X "$1" -H "Authorization: Bearer $3" "$BASE$2"
	else
		curl -s -o /dev/null -w '%{http_code}' -X "$1" "$BASE$2"
	fi
}

# A magic packet: 6 bytes of ff, then the target MAC 16 times.
magic() {
	p=ffffffffffff
	for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
		p=$p$1
	done
	echo "$p"
}

echo "--- install"
"$SSH" 'cat > /tmp/wol-manager.apk' < "$APK"
"$SSH" 'apk update >/dev/null && apk add --allow-untrusted /tmp/wol-manager.apk tcpdump' | tail -n 3
expect "the configuration file is readable by root only" "-rw-------" "$("$SSH" 'ls -l /etc/config/wol_manager' | cut -c1-10)"
expect "the default configuration passes the check" OK "$("$SSH" wol-manager check)"

# Written whole rather than with `uci add_list`, so a second run on the same VM
# starts from the same configuration instead of doubling every list.
"$SSH" 'cat > /etc/config/wol_manager' <<'EOF'
config globals 'globals'
	option enabled '1'
	option iface 'br-lan'

config host 'nas'
	option mac '02:00:00:00:00:01'

config host 'pc'
	option mac '02:00:00:00:00:02'

config host 'broken'
	option mac '02:00:00:00:00:03'
	option iface 'nosuchif0'

config hostlist 'bureau'
	list host 'nas'
	list host 'pc'

config hostlist 'labo'
	list host 'nas'
	list host 'broken'

config user 'alice'
	list allow 'bureau'

config user 'bob'
	list allow 'labo'
EOF
MARK="wol-manager-integration-$$"
"$SSH" "logger -t wol-manager-test $MARK"
ALICE=$("$SSH" wol-manager token alice 2>/dev/null)
BOB=$("$SSH" wol-manager token bob 2>/dev/null)

echo "--- API through uhttpd"
expect "no token: 401" 401 "$(status GET /lists)"
expect "unknown token: 401" 401 "$(status GET /lists 0000000000000000000000000000000000000000000000000000000000000000)"
expect "uhttpd passes the Authorization header to the CGI" 200 "$(status GET /lists "$ALICE")"
expect "alice sees her list" 1 "$(curl -s -H "Authorization: Bearer $ALICE" "$BASE/lists" | grep -c '"id": "bureau"')"
expect "list not allowed: 403" 403 "$(status POST /lists/labo/wake "$ALICE")"
expect "unknown list: 404" 404 "$(status POST /lists/nope/wake "$ALICE")"
expect "GET on a wake endpoint: 405" 405 "$(status GET /lists/bureau/wake "$ALICE")"
expect "etherwake failure on a missing interface: 500" 500 "$(status POST /lists/labo/wake "$BOB")"

echo "--- magic packets on br-lan"
# shellcheck disable=SC2016
"$SSH" 'tcpdump -i br-lan -c 2 -nn -x -U "ether proto 0x0842" </dev/null >/tmp/wol.txt 2>/dev/null & echo $! > /tmp/tcpdump.pid'
sleep 2
expect "wake a list: 200" 200 "$(status POST /lists/bureau/wake "$ALICE")"
sleep 1
# shellcheck disable=SC2016
"$SSH" 'kill "$(cat /tmp/tcpdump.pid)" 2>/dev/null; true'
frames=$("$SSH" 'cat /tmp/wol.txt' | awk '
	/^[^ \t]/ { if (f != "") print f; f = "" }
	/^[ \t]+0x/ { sub(/^[ \t]+0x[0-9a-f]+:[ \t]+/, ""); gsub(/ /, ""); f = f $0 }
	END { if (f != "") print f }')
expect "one magic packet per host of the list, in list order" \
"$(magic 020000000001)
$(magic 020000000002)" "$frames"

echo "--- syslog"
log=$("$SSH" logread | sed -n "/$MARK/,\$p")
expect "each wake is logged" 1 \
	"$(echo "$log" | grep -c 'wol-manager: user=alice list=bureau host=nas mac=02:00:00:00:00:01 iface=br-lan result=ok')"
expect "a failed wake is logged as an error" 1 \
	"$(echo "$log" | grep -c 'wol-manager: user=bob list=labo host=broken .* result=error')"

echo "--- upgrade keeps the configuration"
"$SSH" 'apk add --allow-untrusted --force-reinstall /tmp/wol-manager.apk' | tail -n 1
expect "token still valid after a reinstall" 200 "$(status GET /lists "$ALICE")"

exit "$fail"
