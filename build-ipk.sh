#!/bin/sh
# Builds the glqos and glqos-simguard opkg packages (architecture "all") into dist/.
# Usage: ./build-ipk.sh
set -e
VERSION=1.4.3-1
MAINTAINER="Hugues Voiturier <16280457+huguesdelamure@users.noreply.github.com>"
URL="https://github.com/huguesdelamure/glqos"
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/src
OUT=$HERE/dist
mkdir -p "$OUT"
export COPYFILE_DISABLE=1   # no macOS ._ files in archives
TAR="tar --uid 0 --gid 0 --uname root --gname root --format ustar"

# pack <name> <data dir> <control dir>
pack() {
	w=$(dirname "$2")
	(cd "$2" && $TAR -czf "$w/data.tar.gz" .)
	(cd "$3" && $TAR -czf "$w/control.tar.gz" .)
	echo "2.0" > "$w/debian-binary"
	(cd "$w" && $TAR -czf "$OUT/${1}_${VERSION}_all.ipk" ./debian-binary ./control.tar.gz ./data.tar.gz)
	echo "$OUT/${1}_${VERSION}_all.ipk"
}

# ---------- glqos: collector, pinger, dashboard ----------
W=$(mktemp -d); trap 'rm -rf "$W" "$W2"' EXIT
D=$W/data; C=$W/control
mkdir -p $D/etc/glqos/www/cgi-bin $D/etc/init.d $D/etc/config $D/lib/upgrade/keep.d $C
install -m 755 $SRC/collect.sh $SRC/pinger.sh $D/etc/glqos/
install -m 644 $SRC/index.html $D/etc/glqos/www/index.html
install -m 755 $SRC/q.cgi $D/etc/glqos/www/cgi-bin/q
mkdir -p $D/etc/glqos/www/fonts
install -m 644 $SRC/fonts/*.woff2 $SRC/fonts/OFL-*.txt $D/etc/glqos/www/fonts/
install -m 755 $SRC/glqos.init $D/etc/init.d/glqos
install -m 644 $SRC/glqos.config $D/etc/config/glqos
# kept across GL A/B firmware upgrades (abfota_update reads /lib/upgrade/keep.d)
cat > $D/lib/upgrade/keep.d/glqos <<'EOF'
/etc/glqos/
/etc/init.d/glqos
/etc/rc.d/S99glqos
/etc/rc.d/K10glqos
/etc/config/glqos
/lib/upgrade/keep.d/glqos
EOF
cat > $C/control <<EOF
Package: glqos
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
License: MIT
Source: $URL
Depends: uhttpd, jsonfilter
Section: net
Description: Live 4G/5G radio and IP QoS dashboard for the GL.iNet GL-E5800 (Mudi 7).
 1 Hz modem sampling (Quectel AT), 5 Hz ping, history in /data/glqos.
EOF
echo "/etc/config/glqos" > $C/conffiles
cat > $C/postinst <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
mkdir -p /data/glqos
/etc/init.d/glqos enable
/etc/init.d/glqos restart
exit 0
EOF
cat > $C/prerm <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/glqos stop
/etc/init.d/glqos disable
exit 0
EOF
chmod 755 $C/postinst $C/prerm
pack glqos $D $C

# ---------- glqos-simguard: standby SIM guard ----------
W2=$(mktemp -d)
D=$W2/data; C=$W2/control
mkdir -p $D/etc/glqos $D/etc/init.d $D/lib/upgrade/keep.d $C
install -m 755 $SRC/simguard.sh $D/etc/glqos/
install -m 755 $SRC/glqos-simguard.init $D/etc/init.d/glqos-simguard
cat > $D/lib/upgrade/keep.d/glqos-simguard <<'EOF'
/etc/glqos/simguard.sh
/etc/init.d/glqos-simguard
/etc/rc.d/S99glqos-simguard
/lib/upgrade/keep.d/glqos-simguard
EOF
cat > $C/control <<EOF
Package: glqos-simguard
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
License: MIT
Source: $URL
Depends: glqos
Section: net
Description: Standby SIM guard for the GL.iNet GL-E5800 (Mudi 7).
 Keeps the SIM that does not carry data deregistered, because its idle activity steals
 the single shared radio (multi-second stalls, packet loss). Fails over automatically.
 The standby SIM cannot receive SMS while asleep.
EOF
cat > $C/postinst <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/glqos-simguard enable
/etc/init.d/glqos-simguard restart
exit 0
EOF
# On removal (not on upgrade/reinstall), wake the standby SIM up again so the router is
# back to stock behaviour. opkg sets PKG_UPGRADE=1 when the package is being replaced.
cat > $C/prerm <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/glqos-simguard stop
[ "$PKG_UPGRADE" = "1" ] && exit 0
/etc/init.d/glqos-simguard disable
data_sub=$(cut -d' ' -f2 /tmp/glqos/simguard.state 2>/dev/null)
case "$data_sub" in 1|2) gl_modem -B cpu -U $((3 - data_sub)) AT 'AT+COPS=0' >/dev/null 2>&1 ;; esac
rm -f /tmp/glqos/simguard.state
exit 0
EOF
chmod 755 $C/postinst $C/prerm
pack glqos-simguard $D $C
