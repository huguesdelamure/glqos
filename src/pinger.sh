#!/bin/sh
# glqos pinger: continuous 5 Hz ping to the configured target. Every completed second is
# written to /tmp/glqos/ping.sec as "ts sent recv avg min max jitter".
# Losses are derived from sequence-number gaps.
# The ping is bound to the cellular interface: in repeater or Ethernet mode the default route is
# another uplink, and the dashboard and glqos-simguard must keep judging the cellular link.
# It runs in 60 s rounds so a recreated interface (reconnection, SIM switch) is picked up.
TARGET=$(uci -q get glqos.main.ping_target); TARGET=${TARGET:-8.8.8.8}
mkdir -p /tmp/glqos
# procd only signals this shell, and starts it with SIGPIPE ignored, so ping would survive
# awk forever: on stop, kill every child (ping and awk) explicitly.
pid=
stop() {
	for f in /proc/[0-9]*/stat; do
		read -r p _ _ pp _ < "$f" 2>/dev/null && [ "$pp" = "$$" ] && kill "$p" 2>/dev/null
	done
	exit 0
}
trap stop TERM INT
while :; do
	DEV=$(ubus call network.interface.modem_cpu status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	ping -i 0.2 -W 1 -s 8 -w 60 ${DEV:+-I "$DEV"} "$TARGET" 2>/dev/null | awk '
	function flush() {
		if (cur == "") return
		f = "/tmp/glqos/ping.sec"
		printf "%d %d %d %s %s %s %s\n", cur, sent, recv, (recv ? sprintf("%.1f", s / recv) : ""), mn, mx, (nj ? sprintf("%.1f", j / nj) : "") > f
		close(f)
		sent = recv = s = j = nj = 0; mn = mx = ""
	}
	/seq=/ {
		now = systime()
		if (now != cur) { flush(); cur = now }
		match($0, /seq=[0-9]+/); seq = substr($0, RSTART + 4, RLENGTH - 4) + 0
		match($0, /time=[0-9.]+/); x = substr($0, RSTART + 5, RLENGTH - 5) + 0
		sent += (last == "" ? 1 : seq - last); last = seq; recv++; s += x
		if (mn == "" || x < mn) mn = x
		if (mx == "" || x > mx) mx = x
		if (prev != "") { d = x - prev; j += (d < 0 ? -d : d); nj++ }
		prev = x
	}
	END { flush() }' &
	pid=$!
	wait $pid
	pid=
	[ -n "$DEV" ] || sleep 1
done
