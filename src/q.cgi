#!/bin/sh
# /cgi-bin/q?since=TS            raw rows newer than TS (live polling)
# /cgi-bin/q?from=A&to=B&step=S  rows in [A,B], aggregated per S seconds (S=1: raw)
D=/data/glqos
# print one day of data, gzip-compressed (past days) or not (today)
day() { if [ -r "$D/$1.csv" ]; then cat "$D/$1.csv"; elif [ -r "$D/$1.csv.gz" ]; then zcat "$D/$1.csv.gz"; fi; }

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo

since=; from=; to=; step=1
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	k=${kv%%=*}; val=${kv#*=}
	case "$val" in *[!0-9]*) continue ;; esac
	case "$k" in since) since=$val ;; from) from=$val ;; to) to=$val ;; step) step=$val ;; esac
done

if [ -n "$since" ]; then
	today="$D/$(date +%Y-%m-%d).csv"
	{ [ $(( $(date +%s) - since )) -gt 60 ] && day "$(date -d @$(( $(date +%s) - 86400 )) +%Y-%m-%d)" | tail -n 3600
	  tail -n 3600 "$today" 2>/dev/null; } | awk -F, -v s="$since" '$1 ~ /^[0-9]+$/ && $1 > s'
	exit 0
fi

[ -n "$from" ] && [ -n "$to" ] || exit 0
[ "$step" -ge 1 ] 2>/dev/null || step=1
files=
t=$from
while :; do
	f=$(date -d @$t +%Y-%m-%d)
	case " $files " in *" $f "*) ;; *) { [ -r "$D/$f.csv" ] || [ -r "$D/$f.csv.gz" ]; } && files="$files $f" ;; esac
	[ $t -ge $to ] && break
	t=$((t + 86400)); [ $t -gt $to ] && t=$to
done
[ -n "$files" ] || exit 0

if [ "$step" -le 1 ]; then
	for f in $files; do day $f; done | awk -F, -v a="$from" -v b="$to" '$1 ~ /^[0-9]+$/ && $1 >= a && $1 <= b'
	exit 0
fi

# Aggregation: categorical = last value, measures = mean, ping counts = sum, extremes = min/max.
for f in $files; do day $f; done | awk -F, -v a="$from" -v b="$to" -v st="$step" '
BEGIN { OFS = "," }
function flush(   k, out) {
	if (bk == "") return
	out = bk
	for (k = 2; k <= nf; k++) {
		if (k in cat) out = out "," last[k]
		else if (k == 44 || k == 45) out = out "," sum[k] + 0
		else if (k == 47) out = out "," mn
		else if (k == 48 || k == 50) out = out "," (k == 48 ? mx48 : mx50)
		else out = out "," (cnt[k] ? sprintf("%.2f", sum[k] / cnt[k]) : "")
	}
	print out
	delete sum; delete cnt; mn = ""; mx48 = ""; mx50 = ""
}
BEGIN { split("2 3 4 5 6 7 8 15 16 17 18 22 23 24 25 51 52 57 58 59", c, " "); for (i in c) cat[c[i]] = 1 }
$1 !~ /^[0-9]+$/ || $1 < a || $1 > b { next }
{
	k0 = int($1 / st) * st
	if (k0 != bk) { flush(); bk = k0 }
	nf = NF
	for (k = 2; k <= NF; k++) {
		if (k in cat) { if ($k != "") last[k] = $k; else if (k == 2 || k == 15 || k == 22) last[k] = $k; continue }
		if ($k == "") continue
		sum[k] += $k; cnt[k]++
		if (k == 47 && (mn == "" || $k + 0 < mn)) mn = $k + 0
		if (k == 48 && (mx48 == "" || $k + 0 > mx48)) mx48 = $k + 0
		if (k == 50 && (mx50 == "" || $k + 0 > mx50)) mx50 = $k + 0
	}
}
END { flush() }'
