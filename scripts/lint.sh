#!/bin/sh
# Static checks: house style, ucode syntax, shell scripts, VERSION. Runs on any
# host with ucode and shellcheck (CI lint job, or locally).
set -eu

cd "$(dirname "$0")/.."
fail=0

note() { printf '%s\n' "$*"; }

# House style: no em-dashes. grep rather than `git ls-files`, because the CI
# container has no git and the check would pass silently on an empty file list.
EMDASH=$(printf '\342\200\224')
if grep -rnI --exclude-dir=.git --exclude-dir=.sdk "$EMDASH" .; then
	note "FAIL: em-dash found (house style forbids em-dashes; use ': ' or '(...)')"
	fail=1
fi

# `ucode -c` compiles the imported modules too, so the two entry points cover
# the library and the mocks. tests/mock stands in for the OpenWrt-only uci and
# digest modules. The paths must be absolute: a relative one is not found from
# inside an imported module.
for f in files/wol.cgi files/wol-manager.cli; do
	if ! ucode -L "$PWD/tests/mock" -L "$PWD/files" -c -o /dev/null "$f" 2>/tmp/uc.err; then
		note "FAIL: ucode syntax: $f"
		cat /tmp/uc.err
		fail=1
	fi
done

if ! shellcheck -s sh scripts/*.sh tests/mock/bin/* tests/unit/*.sh tests/vm/*.sh tests/integration/*.sh; then
	note "FAIL: shellcheck"
	fail=1
fi

VER=$(sed -n '1p' VERSION)
if ! printf '%s' "$VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
	note "FAIL: VERSION must be a single x.y.z line, got: '$VER'"
	fail=1
fi

[ "$fail" = 0 ] && note "lint: OK"
exit "$fail"
