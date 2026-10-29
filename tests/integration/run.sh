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

"$SSH" 'uci batch' <<'EOF'
set wol_manager.nas=host
set wol_manager.nas.mac=02:00:00:00:00:01
set wol_manager.pc=host
set wol_manager.pc.mac=02:00:00:00:00:02
set wol_manager.broken=host
set wol_manager.broken.mac=02:00:00:00:00:03
set wol_manager.broken.iface=nosuchif0
set wol_manager.bureau=hostlist
add_list wol_manager.bureau.host=nas
add_list wol_manager.bureau.host=pc
set wol_manager.labo=hostlist
add_list wol_manager.labo.host=nas
add_list wol_manager.labo.host=broken
set wol_manager.alice=user
add_list wol_manager.alice.allow=bureau
set wol_manager.bob=user
add_list wol_manager.bob.allow=labo
commit wol_manager
EOF
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
expect "each wake is logged" 1 \
	"$("$SSH" 'logread -e wol-manager' | grep -c 'user=alice list=bureau host=nas mac=02:00:00:00:00:01 iface=br-lan result=ok')"
expect "a failed wake is logged as an error" 1 \
	"$("$SSH" 'logread -e wol-manager' | grep -c 'user=bob list=labo host=broken .* result=error')"

echo "--- upgrade keeps the configuration"
"$SSH" 'apk add --allow-untrusted --force-reinstall /tmp/wol-manager.apk' | tail -n 1
expect "token still valid after a reinstall" 200 "$(status GET /lists "$ALICE")"

exit "$fail"
