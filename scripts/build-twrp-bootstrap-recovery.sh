#!/usr/bin/env bash
set -eo pipefail

export JAVA_HOME="$HOME/acer-twrp/toolchains/jdk8"
export PATH="$JAVA_HOME/bin:$PATH"

workspace="/mnt/c/Users/slava/Documents/Acer LineageOS"
base="$HOME/acer-twrp/stock-debug-ramdisk"
work="$HOME/acer-twrp/twrp-bootstrap-ramdisk"
raw="$HOME/acer-twrp/twrp-bootstrap-ramdisk.img"
raw_mtk="$HOME/acer-twrp/twrp-bootstrap-ramdisk-mtk.img"
unsigned="$workspace/builds/twrp-bootstrap-recovery-unsigned.img"
signed="$workspace/builds/twrp-bootstrap-recovery-signed.img"
installed="$workspace/builds/twrp-bootstrap-recovery-installed.img"
payload="$workspace/builds/twrp-runtime-payload.tar.gz"
mkbootimg="$HOME/acer-twrp/src/out/host/linux-x86/bin/mtkbootimg"
bootsigner="$HOME/acer-twrp/src/out/host/linux-x86/framework/BootSignature.jar"
keys="$HOME/acer-twrp/src/build/target/product/security"
payload_size=$(stat -c %s "$payload")
payload_blocks=$(((payload_size + 4095) / 4096))
payload_sha256=$(sha256sum "$payload" | awk '{print $1}')
payload_offset=$((11 * 1024 * 1024))
payload_skip=$((payload_offset / 4096))

rm -rf "$work"
cp -a "$base" "$work"
if [ "${EMBED_PAYLOAD:-0}" = 1 ]; then
  cp "$payload" "$work/twrp-runtime-payload.tar.gz"
fi
mkdir -p "$work/touch-cal"
printf '\x3c\x3c\x3c\x3c\x3c\xd4' > "$work/touch-cal/gtp_clk.bin"
: > "$work/touch-cal/gtp_ref.bin"

cat > "$work/sbin/twrp-bootstrap.sh" <<SH
#!/sbin/sh
BB=/sbin/busybox
PAYLOAD=/tmp/twrp-runtime-payload.tar.gz
ROOT=/tmp/twrp-root
CACHEDEV=/dev/block/platform/mtk-msdc.0/11230000.MSDC0/by-name/cache
PERSISTDEV=/dev/block/platform/mtk-msdc.0/11230000.MSDC0/by-name/persist
RECOVERYDEV=/dev/block/platform/mtk-msdc.0/11230000.MSDC0/by-name/recovery
EXPECTED_SHA256=$payload_sha256

# First boot the known-good Acer recovery userspace.  It initializes the
# vendor display, USB gadget, and firmware environment used by the live test.
\$BB sleep 8
if [ -f /twrp-runtime-payload.tar.gz ]; then
    \$BB cp /twrp-runtime-payload.tar.gz \$PAYLOAD
else
    # Persistent installs store the payload in otherwise-unused space after
    # the signed Android boot image inside the 16 MiB recovery partition.
    \$BB dd if=\$RECOVERYDEV bs=4096 skip=$payload_skip count=$payload_blocks 2>/dev/null | \
        \$BB head -c $payload_size > \$PAYLOAD
    if [ "\$(\$BB sha256sum \$PAYLOAD | \$BB awk '{print \$1}')" != "\$EXPECTED_SHA256" ]; then
        \$BB rm -f \$PAYLOAD
    fi
fi
if [ ! -f \$PAYLOAD ]; then
    \$BB mkdir -p /cache
    if [ ! -f /cache/twrp-runtime-payload.tar.gz ]; then
        \$BB mount -t ext4 \$CACHEDEV /cache 2>/dev/null || true
    fi
fi
if [ ! -f \$PAYLOAD ] && [ -f /cache/twrp-runtime-payload.tar.gz ]; then
    \$BB cp /cache/twrp-runtime-payload.tar.gz \$PAYLOAD
    if [ "\$(\$BB sha256sum \$PAYLOAD | \$BB awk '{print \$1}')" != "\$EXPECTED_SHA256" ]; then
        \$BB rm -f \$PAYLOAD
    fi
fi
if [ ! -f \$PAYLOAD ]; then
    \$BB dd if=\$PERSISTDEV bs=4096 count=$payload_blocks 2>/dev/null | \
        \$BB head -c $payload_size > \$PAYLOAD
fi
if [ "\$(\$BB sha256sum \$PAYLOAD | \$BB awk '{print \$1}')" != "\$EXPECTED_SHA256" ]; then
    \$BB echo 'TWRP runtime payload is missing or corrupt' > /tmp/twrp-bootstrap-error
    exit 1
fi

\$BB rm -rf \$ROOT
\$BB mkdir -p \$ROOT
\$BB tar -xzf \$PAYLOAD -C \$ROOT
\$BB mkdir -p /twres /res /etc
\$BB cp -a \$ROOT/twres/. /twres/
\$BB cp -a \$ROOT/res/. /res/
\$BB cp -a \$ROOT/etc/. /etc/
for file in \$ROOT/sbin/*; do
    base=\${file##*/}
    case "\$base" in
        adbd|healthd|busybox|sh|recovery) ;;
        *) \$BB cp -a "\$file" /sbin/ ;;
    esac
done
\$BB chmod 0755 /sbin/twrp-recovery /sbin/libminuitwrp.so

# Supply the clock/reference files required by this tablet's Goodix driver.
\$BB mount -t tmpfs -o mode=0771 tmpfs /data
\$BB mkdir -p /data/tpdfw
\$BB cp /touch-cal/gtp_clk.bin /data/tpdfw/gtp_clk.bin
\$BB cp /touch-cal/gtp_ref.bin /data/tpdfw/gtp_ref.bin
\$BB chmod 0777 /data/tpdfw
\$BB chmod 0666 /data/tpdfw/gtp_clk.bin /data/tpdfw/gtp_ref.bin
i=0
while [ "\$i" -lt 200 ]; do
    \$BB dmesg | \$BB grep -q 'Send ref success.' && break
    \$BB sleep 0.1
    i=\$((i + 1))
done

/sbin/setprop ctl.stop recovery
\$BB sleep 1
\$BB umount /data || true
exec /sbin/twrp-recovery
SH
chmod 750 "$work/sbin/twrp-bootstrap.sh"

cat >> "$work/init.rc" <<'RC'

service twrp-bootstrap /sbin/twrp-bootstrap.sh
    class default
    user root
    group root
    oneshot
    seclabel u:r:recovery:s0
RC

(
  cd "$work"
  find . -print0 | cpio --null -o -H newc --owner 0:0 2>/dev/null | gzip -n -9 > "$raw"
)

# Acer's stored recovery boot path requires the MediaTek ramdisk header to be
# tagged RECOVERY.  mtkbootimg labels an unwrapped gzip ramdisk ROOTFS, which
# still works with `fastboot boot` but is rejected when read from the recovery
# partition on this device.
python3 - "$raw" "$raw_mtk" <<'PY'
import struct
import sys
from pathlib import Path

payload = Path(sys.argv[1]).read_bytes()
header = b'\x88\x16\x88\x58' + struct.pack('<I', len(payload))
header += b'RECOVERY'.ljust(32, b'\0')
header = header.ljust(512, b'\0')
Path(sys.argv[2]).write_bytes(header + payload)
PY

"$mkbootimg" \
  --kernel "$workspace/porting/recovery-kernel.bin" \
  --ramdisk "$raw_mtk" \
  --cmdline 'bootopt=64S3,32N2,64N2' \
  --base 0x40078000 \
  --pagesize 2048 \
  --ramdisk_offset 0x03f88000 \
  --second_offset 0x00e88000 \
  --tags_offset 0x0df88000 \
  --board 1495071958 \
  --mtk 1 \
  --output "$unsigned"

java -jar "$bootsigner" /recovery "$unsigned" "$keys/testkey.pk8" "$keys/testkey.x509.pem" "$signed"
java -jar "$bootsigner" -verify "$signed"

# The bootloader reads the signed image length from the Android boot header and
# ignores the remaining partition bytes. Put the runtime payload at 11 MiB so
# TWRP remains available even if /cache is wiped.
python3 - "$signed" "$payload" "$installed" "$payload_offset" <<'PY'
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
payload = Path(sys.argv[2]).read_bytes()
offset = int(sys.argv[4])
partition_size = 16 * 1024 * 1024
if len(image) > offset:
    raise SystemExit("signed recovery overlaps the payload slot")
if offset + len(payload) > partition_size:
    raise SystemExit("payload does not fit in the recovery partition")
out = bytearray(partition_size)
out[:len(image)] = image
out[offset:offset + len(payload)] = payload
Path(sys.argv[3]).write_bytes(out)
PY

sha256sum "$signed" "$payload" "$installed"
ls -l "$raw" "$raw_mtk" "$unsigned" "$signed" "$payload" "$installed"
