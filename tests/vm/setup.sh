#!/bin/sh
set -eu
cd "$(dirname "$0")"

IMAGE_URL=https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz
IMAGE_GZ=openwrt-25.12.5.img.gz
IMAGE=openwrt.img
KEY=id_ed25519

if [ ! -f "$IMAGE_GZ" ]; then
	echo "Downloading $IMAGE_URL"
	curl -fsSL --retry 3 -o "$IMAGE_GZ.tmp" "$IMAGE_URL"
	mv "$IMAGE_GZ.tmp" "$IMAGE_GZ"
fi

if [ ! -f "$IMAGE" ]; then
	gunzip -c "$IMAGE_GZ" > "$IMAGE.tmp"
	mv "$IMAGE.tmp" "$IMAGE"
fi

if [ ! -f "$KEY" ]; then
	ssh-keygen -t ed25519 -N '' -f "$KEY" -C wol-manager-ci -q
fi

if [ -f .injected ] && [ .injected -nt "$KEY.pub" ]; then
	exit 0
fi

LOOPDEV=$(sudo losetup --find --show --partscan "$PWD/$IMAGE")
MNT=$(mktemp -d)
cleanup() { sudo umount "$MNT" 2>/dev/null || true; sudo losetup -d "$LOOPDEV" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

# OpenWrt combined-ext4 puts the rootfs on partition 2.
sudo mount "${LOOPDEV}p2" "$MNT"

sudo mkdir -p "$MNT/etc/dropbear"
sudo cp "$KEY.pub" "$MNT/etc/dropbear/authorized_keys"
sudo chmod 600 "$MNT/etc/dropbear/authorized_keys"
sudo chown 0:0 "$MNT/etc/dropbear/authorized_keys"

# OpenWrt's default LAN is static 192.168.1.1; QEMU user-mode networking
# hands out 10.0.2.x via DHCP, so LAN switches to DHCP on first boot.
sudo mkdir -p "$MNT/etc/uci-defaults"
sudo tee "$MNT/etc/uci-defaults/99-wol-manager-vm-network" >/dev/null <<'UCID'
#!/bin/sh
uci set network.lan.proto='dhcp'
uci delete network.lan.ipaddr 2>/dev/null || true
uci delete network.lan.netmask 2>/dev/null || true
uci commit network
exit 0
UCID
sudo chmod 755 "$MNT/etc/uci-defaults/99-wol-manager-vm-network"
sudo chown 0:0 "$MNT/etc/uci-defaults/99-wol-manager-vm-network"

touch .injected
echo "Image ready"
