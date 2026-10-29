#!/bin/sh
set -u
cd "$(dirname "$0")" || exit 1

PIDFILE=qemu.pid

if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE")
	./ssh.sh poweroff 2>/dev/null || true

	for _ in 1 2 3 4 5 6 7 8 9 10; do
		kill -0 "$PID" 2>/dev/null || break
		sleep 1
	done

	if kill -0 "$PID" 2>/dev/null; then
		kill "$PID" 2>/dev/null || true
		sleep 1
		kill -9 "$PID" 2>/dev/null || true
	fi
	rm -f "$PIDFILE"
	# The multiplexed master outlives the VM by ControlPersist, and a socket that
	# points at a dead VM delays the next run's first call until it times out.
	rm -f /tmp/wol-manager-vm-* 2>/dev/null || true
fi

echo "VM stopped"
