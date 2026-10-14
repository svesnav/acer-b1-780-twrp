#!/usr/bin/env bash
set -eo pipefail

workspace="/mnt/c/Users/slava/Documents/Acer LineageOS"
source_root="$HOME/acer-twrp/src6/out/target/product/acer_barricadewifi/recovery/root"
payload_root="$HOME/acer-twrp/twrp-runtime-payload"
archive="$workspace/builds/twrp-runtime-payload.tar.gz"

rm -rf "$payload_root"
mkdir -p "$payload_root/sbin"
cp -a "$source_root/twres" "$source_root/res" "$source_root/etc" \
  "$payload_root/"

for file in "$source_root"/sbin/*; do
  base=${file##*/}
  case "$base" in
    adbd|healthd|busybox|sh|recovery) ;;
    *) cp -a "$file" "$payload_root/sbin/" ;;
  esac
done
cp -a "$source_root/sbin/recovery" "$payload_root/sbin/twrp-recovery"

tar -C "$payload_root" -czf "$archive" .
du -sh "$payload_root"
ls -l "$archive"
