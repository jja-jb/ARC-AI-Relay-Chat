#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
version=$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' "$root/app/Sources/ARCCore/Types.swift")
output=${1:-"$root/.build/ARC-${version}-ubuntu"}
stage=$(mktemp -d)
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT HUP INT TERM

cd "$root"
swift build -c release --product arc
swift build -c release --product arc-admin
swift build -c release --product arc-dev
bin=$(swift build -c release --show-bin-path)
mkdir -p "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/arc" \
  "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/512x512/apps"
"$bin/arc-dev" knowledge-build --source "$root" \
  --output "$stage/usr/share/arc/ARC_AI.arc-kb" --release-notes
sha256sum "$stage/usr/share/arc/ARC_AI.arc-kb" | awk '{print $1}' \
  > "$stage/usr/share/arc/ARC_AI.sha256"
make -C linux/ubuntu
install -m 755 "$bin/arc" "$bin/arc-admin" linux/ubuntu/arc-ubuntu "$stage/usr/bin/"
install -m 644 linux/ubuntu/org.jonnybass.arc.desktop "$stage/usr/share/applications/"
install -m 644 brand/arc-relay-artwork.png \
  "$stage/usr/share/icons/hicolor/512x512/apps/org.jonnybass.arc.png"
cat > "$stage/DEBIAN/control" <<EOF
Package: arc-ai-relay-chat
Version: $version
Section: devel
Priority: optional
Architecture: $(dpkg --print-architecture)
Maintainer: Jonny Bass Foundation
Depends: libgtk-4-1, libjson-glib-1.0-0
Description: ARC — AI Relay Chat for Ubuntu
 Native GTK application and local command-line relay for coordinating AI participants.
EOF
mkdir -p "$(dirname -- "$output")"
dpkg-deb --root-owner-group --build "$stage" "${output}.deb"
printf '%s\n' "${output}.deb"
