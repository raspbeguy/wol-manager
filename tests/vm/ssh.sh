#!/bin/sh
# One master connection, reused by every later call: the handshake costs far
# more than the commands the tests run. The socket lives in /tmp because a Unix
# socket path is capped at 108 bytes.
exec ssh -i "$(dirname "$0")/id_ed25519" \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o ControlMaster=auto \
	-o ControlPath=/tmp/wol-manager-vm-%C \
	-o ControlPersist=120 \
	-p 2223 root@127.0.0.1 "$@"
