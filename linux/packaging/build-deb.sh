#!/bin/sh
# Builds pulse-monitor_<version>_all.deb from linux/ into <out dir>.
#   linux/packaging/build-deb.sh 0.1.0 dist/linux
# Pure Python + GTK from the distribution, so one package serves amd64 and arm64.
set -eu
version=$1
out=$2
here=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
pkg=pulse-monitor
id=io.github.kutluhangil.Pulse

mkdir -p "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/lib/$pkg" "$stage/usr/share/applications" \
         "$stage/usr/share/metainfo" "$stage/usr/share/doc/$pkg"
cp -R "$here/pulse_monitor" "$stage/usr/lib/$pkg/"
find "$stage/usr/lib/$pkg" -name __pycache__ -prune -exec rm -rf {} +
sed -i "s/^__version__ = .*/__version__ = \"$version\"/" "$stage/usr/lib/$pkg/pulse_monitor/__init__.py"
install -m 755 "$here/bin/pulse-monitor" "$stage/usr/bin/pulse-monitor"
install -m 644 "$here/data/$id.desktop" "$stage/usr/share/applications/"
install -m 644 "$here/data/$id.metainfo.xml" "$stage/usr/share/metainfo/"
for s in 48 64 128 256 512; do
  mkdir -p "$stage/usr/share/icons/hicolor/${s}x${s}/apps"
  install -m 644 "$here/data/icons/$s.png" "$stage/usr/share/icons/hicolor/${s}x${s}/apps/$id.png"
done
cat > "$stage/usr/share/doc/$pkg/copyright" <<COPY
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Pulse
Source: https://github.com/kutluhangil/Pulse

Files: *
Copyright: 2026 Kutluhan Gül
License: GPL-3.0-or-later
 See /usr/share/common-licenses/GPL-3.
COPY
size=$(du -sk "$stage/usr" | cut -f1)
cat > "$stage/DEBIAN/control" <<CTRL
Package: $pkg
Version: $version
Section: admin
Priority: optional
Architecture: all
Installed-Size: $size
Depends: python3 (>= 3.10), python3-gi (>= 3.42), python3-gi-cairo, gir1.2-gtk-4.0 (>= 4.12), gir1.2-adw-1 (>= 1.5), librsvg2-common
Recommends: gir1.2-secret-1, gnome-shell-extension-appindicator | plasma-workspace
Maintainer: Kutluhan Gül <noreply@github.com>
Homepage: https://pulse.kutluhangil.dev
Description: Live monitor for a home server running the Pulse agent
 Pulse shows health score, CPU, temperature, memory, disk, network, fan,
 Docker containers and site checks of a server in real time, with a tray
 icon and desktop notifications. GTK 4 and libadwaita.
CTRL
cat > "$stage/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
POST
chmod 755 "$stage/DEBIAN/postinst"
mkdir -p "$out"
dpkg-deb --root-owner-group --build "$stage" "$out/${pkg}_${version}_all.deb"
rm -rf "$stage"
