#!/bin/sh
# glqos pinger: continuous 5 Hz ping to the configured target. Every completed second is
# written to /tmp/glqos/ping.sec as "ts sent recv avg min max jitter".
# Losses are derived from sequence-number gaps.
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
	ping -i 0.2 -W 1 "$TARGET" 2>/dev/null | awk '
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
	}' &
	pid=$!
	wait $pid
	pid=
	sleep 1
done
