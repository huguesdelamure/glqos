#!/bin/sh
# glqos collector (GL-E5800 / Quectel RG650V): one CSV line per second in /data/glqos.
# All AT queries go through a single gl_modem call (~150-250 ms).
D=/data/glqos
RETENTION=$(uci -q get glqos.main.retention_days); RETENTION=${RETENTION:-30}
# lat,lon,speed,sats are reserved columns (the E5800 has no usable GNSS) and stay empty.
HEADER="ts,mode,lte_band,lte_earfcn,lte_pci,lte_cellid,lte_tac,lte_dlbw,lte_rsrp,lte_rsrq,lte_rssi,lte_sinr,lte_cqi,lte_txpwr,nr_band,nr_arfcn,nr_pci,nr_bw,nr_rsrp,nr_rsrq,nr_sinr,ca,ca_lte,ca_nr,cc,lte_rsrp_a0,lte_rsrp_a1,lte_rsrp_a2,lte_rsrp_a3,lte_sinr_a0,lte_sinr_a1,lte_sinr_a2,lte_sinr_a3,nr_rsrp_a0,nr_rsrp_a1,nr_rsrp_a2,nr_rsrp_a3,nr_sinr_a0,nr_sinr_a1,nr_sinr_a2,nr_sinr_a3,dl,ul,p_sent,p_recv,p_avg,p_min,p_max,p_jit,temp,if_up,if_uptime,lat,lon,speed,sats,plmn,sub,sg"

mkdir -p "$D" /tmp/glqos
# Rows go to a RAM buffer first and reach the flash every FLUSH_S seconds, at midnight and on
# stop, so the collector does not keep the flash busy on its own. A power cut loses at most
# FLUSH_S seconds. q.cgi reads the buffer too. The init script also calls "collect.sh flush"
# from its stop (K10 at shutdown), because at reboot the final kill comes too late.
FLUSH_S=$(uci -q get glqos.main.flush_s); FLUSH_S=${FLUSH_S:-300}
BUF=/tmp/glqos/buf.csv; BUFDAY=/tmp/glqos/buf.day
flush() {
	(
	flock 9
	[ -s "$BUF" ] || exit 0
	day=$(cat "$BUFDAY" 2>/dev/null)
	[ -n "$day" ] || day=$(date -d @"$(head -1 "$BUF" | cut -d, -f1)" +%Y-%m-%d)
	f="$D/$day.csv"
	[ -s "$f" ] || echo "$HEADER" > "$f"
	cat "$BUF" >> "$f" && : > "$BUF"
	sync "$f" 2>/dev/null
	) 9> /tmp/glqos/buf.lock
}
[ "$1" = flush ] && { flush; exit 0; }
trap 'flush; exit 0' TERM INT
flush   # leftover from a collector that was killed
last_flush=$(date +%s)
# Today's file written by an older version: refresh the header (new columns are only ever appended).
F="$D/$(date +%Y-%m-%d).csv"
[ -s "$F" ] && [ "$(head -1 "$F")" != "$HEADER" ] && sed -i "1s/.*/$HEADER/" "$F"

i=0; prx=; ptx=; pt=; TEMP=; IF=; UP=; UPT=; SUB=1; PIP=
while :; do
	t0=$(cut -d' ' -f1 /proc/uptime)
	ts=$(date +%s)
	if [ $((i % 5)) -eq 0 ]; then
		ST=$(ubus call network.interface.modem_cpu status 2>/dev/null)
		IF=$(echo "$ST" | jsonfilter -e '@.l3_device' 2>/dev/null)
		UP=$(echo "$ST" | jsonfilter -e '@.up' 2>/dev/null)
		UPT=$(echo "$ST" | jsonfilter -e '@.uptime' 2>/dev/null)
		# Dual-SIM modem: follow the subscription that holds the data interface IP.
		IP=$(ip -4 addr show "$IF" 2>/dev/null | awk '/inet /{split($2, a, "/"); print a[1]; exit}')
		if [ -n "$IP" ] && [ "$IP" != "$PIP" ]; then
			for u in 1 2; do
				gl_modem -B cpu -U $u AT 'AT+CGPADDR' 2>/dev/null | grep -q "\"$IP\"" && { SUB=$u; break; }
			done
			PIP=$IP
		fi
	fi
	RX=; TX=
	if [ -n "$IF" ] && [ -r /sys/class/net/$IF/statistics/rx_bytes ]; then
		RX=$(cat /sys/class/net/$IF/statistics/rx_bytes)
		TX=$(cat /sys/class/net/$IF/statistics/tx_bytes)
	fi
	CMD='AT+QENG="servingcell";+QCAINFO;+QRSRP;+QSINR'
	[ $((i % 10)) -eq 0 ] && CMD="$CMD;+QTEMP"
	PING=$(cat /tmp/glqos/ping.sec 2>/dev/null)
	SG=$(cut -d" " -f1 /tmp/glqos/simguard.state 2>/dev/null)

	LINE=$(gl_modem -B cpu -U $SUB AT "$CMD" 2>/dev/null | awk -v ts="$ts" -v t="$t0" -v pt="$pt" \
		-v rx="$RX" -v tx="$TX" -v prx="$prx" -v ptx="$ptx" -v up="$UP" -v upt="$UPT" -v ping="$PING" -v ptemp="$TEMP" -v subid="$SUB" -v sg="$SG" '
	function v(x) { gsub(/[ \r"]/, "", x); return (x == "-" || x == "-32768" || x == "-140" || x == "") ? "" : x }
	function lte(o) {
		plmn = v(f[o+2]) "-" v(f[o+3])
		lte_cellid = v(f[o+4]); lte_pci = v(f[o+5]); lte_earfcn = v(f[o+6]); lte_band = "B" v(f[o+7])
		lte_dlbw = v(f[o+9]); lte_tac = v(f[o+10]); lte_rsrp = v(f[o+11]); lte_rsrq = v(f[o+12])
		lte_rssi = v(f[o+13]); lte_sinr = v(f[o+14]); lte_cqi = v(f[o+15]); lte_txpwr = v(f[o+16])
	}
	function strip(s, pfx) { sub(pfx, "", s); gsub(/"/, "", s); gsub(/\r/, "", s); return s }
	/^\+QENG:/ {
		n = split(strip($0, "^\\+QENG: *"), f, ",")
		if (f[1] == "servingcell") {
			if (f[3] == "LTE") { mode = "LTE"; lte(3) }
			else if (f[3] == "NR5G-SA") {
				mode = "SA"; plmn = v(f[5]) "-" v(f[6]); nr_pci = v(f[8]); nr_arfcn = v(f[10]); nr_band = "n" v(f[11]); nr_bw = v(f[12])
				nr_rsrp = v(f[13]); nr_rsrq = v(f[14]); nr_sinr = v(f[15])
			}
		} else if (f[1] == "LTE") { if (mode == "") mode = "LTE"; lte(1) }
		else if (f[1] == "NR5G-NSA") {
			nr_pci = v(f[4]); nr_rsrp = v(f[5]); nr_sinr = v(f[6]); nr_rsrq = v(f[7])
			nr_arfcn = v(f[8]); nr_band = "n" v(f[9]); nr_bw = v(f[10])
			mode = (nr_rsrp != "") ? "NSA" : "LTE"
		}
	}
	/^\+QCAINFO:/ {
		n = split(strip($0, "^\\+QCAINFO: *"), f, ",")
		b = f[4]; num = b; sub(/.* /, "", num)
		if (b ~ /^LTE/) {
			# PCC|SCC,earfcn,bw_rb,band,state,pci,rsrp,rsrq,rssi,sinr
			tag = "B" num; cal++
			d = tag (f[1] == "PCC" ? "*" : "") ":" v(f[6]) ":" v(f[7]) ":" v(f[8]) ":" v(f[10]) ":" v(f[3])
		} else if (b ~ /^NR5G/) {
			# two layouts seen for NR carriers: short (8 fields) or long
			tag = "n" num; can++
			pc = (f[1] == "PCC" ? "*" : "")
			if (n <= 8) d = tag pc ":" v(f[5]) ":" v(f[6]) ":" v(f[7]) "::" v(f[3])
			else d = tag pc ":" v(f[6]) ":" v(f[10]) ":" v(f[11]) "::" v(f[3])
		} else next
		if (f[1] == "PCC") tag = tag "*"
		ca = (ca == "") ? tag : ca "+" tag
		cc = (cc == "") ? d : cc "|" d
	}
	/^\+QRSRP:/ { n = split(strip($0, "^\\+QRSRP: *"), f, ","); for (k = 1; k <= 4; k++) if (f[5] ~ /NR/) nrr[k] = v(f[k]); else ltr[k] = v(f[k]) }
	/^\+QSINR:/ { n = split(strip($0, "^\\+QSINR: *"), f, ","); for (k = 1; k <= 4; k++) if (f[5] ~ /NR/) nrs[k] = v(f[k]); else lts[k] = v(f[k]) }
	/^\+QTEMP:/ { x = strip($0, ".*,") + 0; if (x > -100 && (tmax == "" || x > tmax)) tmax = x }
	END {
		dl = ul = ""
		if (rx != "" && prx != "" && pt != "" && t > pt && rx >= prx && tx >= ptx) {
			dl = sprintf("%.2f", (rx - prx) * 8 / 1e6 / (t - pt)); ul = sprintf("%.2f", (tx - ptx) * 8 / 1e6 / (t - pt))
		}
		# ping.sec: ts sent recv avg min max jitter (last completed second).
		# Stale file = no reply for > 3 s: lost probes are counted later from sequence
		# gaps when replies resume, so record "unknown" here rather than "lost".
		np = split(ping, p, " ")
		if (np >= 3 && ts - p[1] <= 3) { ps = p[2]; pr = p[3]; pa = p[4]; pmn = p[5]; pmx = p[6]; pj = p[7] }
		else { ps = pr = pa = pmn = pmx = pj = "" }
		if (tmax == "") tmax = ptemp
		printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,", ts, mode, (lte_band == "B" ? "" : lte_band), lte_earfcn, lte_pci, lte_cellid, lte_tac, lte_dlbw, lte_rsrp, lte_rsrq, lte_rssi, lte_sinr, lte_cqi, lte_txpwr
		printf "%s,%s,%s,%s,%s,%s,%s,", (nr_band == "n" ? "" : nr_band), nr_arfcn, nr_pci, nr_bw, nr_rsrp, nr_rsrq, nr_sinr
		printf "%s,%d,%d,%s", ca, cal, can, cc
		for (k = 1; k <= 4; k++) printf ",%s", ltr[k]
		for (k = 1; k <= 4; k++) printf ",%s", lts[k]
		for (k = 1; k <= 4; k++) printf ",%s", nrr[k]
		for (k = 1; k <= 4; k++) printf ",%s", nrs[k]
		printf ",%s,%s,%s,%s,%s,%s,%s,%s", dl, ul, ps, pr, pa, pmn, pmx, pj
		printf ",%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", tmax, (up == "true" ? 1 : 0), upt, lat, lon, spd, (lat != "" ? sats : ""), (plmn == "-" ? "" : plmn), subid, sg
	}')
	TEMP=$(echo "$LINE" | cut -d, -f50)
	today=$(date +%Y-%m-%d); F="$D/$today.csv"
	# a new day starts: the buffer still holds the previous one
	[ "$(cat "$BUFDAY" 2>/dev/null)" = "$today" ] || { flush; echo "$today" > "$BUFDAY"; }
	echo "$LINE" >> "$BUF"
	[ $((ts - last_flush)) -ge "$FLUSH_S" ] && { flush; last_flush=$ts; }
	prx=$RX; ptx=$TX; pt=$t0
	i=$((i + 1))
	if [ $((i % 3600)) -eq 0 ]; then
		# past days are gzip-compressed (~5x smaller), then expired
		for f in "$D"/*.csv; do [ "$f" != "$F" ] && [ -f "$f" ] && gzip -f "$f"; done
		find "$D" -name '*.csv.gz' -mtime +"$RETENTION" -delete 2>/dev/null
	fi
	sleep $(awk -v a="$t0" -v b="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN { d = 1 - (b - a); if (d < 0.05) d = 0.05; printf "%.2f", d }')
done
