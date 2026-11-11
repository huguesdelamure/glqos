#!/bin/sh
# glqos-simguard: standby SIM guard for the GL-E5800 (dual-SIM modem with a single radio).
#
# While a second SIM is registered, its idle activity (paging, measurements, cell
# reselection, tracking area updates) steals the shared radio from the SIM carrying data:
# 1-13 s stalls and packet loss, much worse on the move. This guard keeps the SIM that
# does not carry data deregistered (AT+COPS=2). If the data SIM stops answering pings for
# down_s seconds, the standby SIM is re-registered (AT+COPS=0) and data is switched to it
# through GL's own failover event; once the new SIM has been healthy for calm_s seconds,
# the old one is deregistered.
#
# Manual pause (hands-on work): touch /tmp/glqos/simguard.pause
STATE=/tmp/glqos/simguard.state
LOG=/data/glqos/simguard.log
cfg() { v=$(uci -q get glqos.simguard."$1"); echo "${v:-$2}"; }
DOWN_S=$(cfg down_s 30)     # no ping reply for this long: data SIM considered down
CALM_S=$(cfg calm_s 120)    # healthy for this long: put the standby SIM back to sleep
CHECK_S=$(cfg check_s 60)   # periodic check that the standby SIM is still deregistered

mkdir -p /tmp/glqos /data/glqos
at() { gl_modem -B cpu -U "$1" AT "$2" 2>/dev/null; }
log() { logger -t glqos-simguard "$*"; echo "$(date '+%F %T') $*" >> "$LOG"; }

# Switch data to slot $1 with GL's failover module. If GL's own automatic failover is
# disabled, the module is only started for the event and stopped again afterwards.
switch_data() {
	gl_auto=$(ubus call cellular.modem get_all_config '{"bus":"cpu"}' 2>/dev/null | jsonfilter -e '@.slot_feature[*].failover.enable_switch' 2>/dev/null | head -1)
	[ "$gl_auto" = "true" ] || { ubus call cellular.failover start '{"bus":"cpu"}' >/dev/null 2>&1; sleep 2; }
	r=$(ubus call cellular.failover switch_event "{\"event\":\"MANUAL_SWITCH\",\"slot\":$1,\"bus\":\"cpu\"}" 2>&1 | tr -d '\n\t ')
	sleep 2
	[ "$gl_auto" = "true" ] || ubus call cellular.failover stop '{"bus":"cpu"}' >/dev/null 2>&1
	log "data switch to SIM $1 requested ($r)"
}

data_sub=; pip=; last_ok=$(date +%s); healthy_since=; standby=unknown; last_check=0

while :; do
	if [ -e /tmp/glqos/simguard.pause ]; then
		echo "pause ${data_sub:-?}" > "$STATE"; sleep 5; continue
	fi
	now=$(date +%s)
	ST=$(ubus call network.interface.modem_cpu status 2>/dev/null)
	IF=$(echo "$ST" | jsonfilter -e '@.l3_device' 2>/dev/null)
	UP=$(echo "$ST" | jsonfilter -e '@.up' 2>/dev/null)
	IP=$(ip -4 addr show "$IF" 2>/dev/null | awk '/inet /{split($2, a, "/"); print a[1]; exit}')

	# Which subscription holds the data interface IP
	if [ -n "$IP" ] && [ "$IP" != "$pip" ]; then
		for u in 1 2; do
			at $u 'AT+CGPADDR' | grep -q "\"$IP\"" && { new=$u; break; }
		done
		if [ -n "$new" ] && [ "$new" != "$data_sub" ]; then
			[ -n "$data_sub" ] && log "data moved from SIM $data_sub to SIM $new"
			data_sub=$new; healthy_since=
			# the previous data SIM stays registered until we put it to sleep
			standby=on
		fi
		pip=$IP; new=
	fi

	# Health: last second with at least one ping reply (written by glqos pinger.sh)
	set -- $(cat /tmp/glqos/ping.sec 2>/dev/null)
	[ -n "$1" ] && [ "${3:-0}" -gt 0 ] && [ $((now - $1)) -le 3 ] && last_ok=$1
	if [ "$UP" = "true" ] && [ $((now - last_ok)) -lt "$DOWN_S" ]; then
		[ -z "$healthy_since" ] && healthy_since=$now
	else
		healthy_since=
	fi

	if [ -n "$data_sub" ]; then
		other=$((3 - data_sub))
		if [ -z "$healthy_since" ] && [ $((now - last_ok)) -ge "$DOWN_S" ]; then
			# Data SIM down: wake the standby SIM, wait for registration (60 s max), switch data
			if [ "$standby" != "on" ]; then
				at $other 'AT+COPS=0' >/dev/null
				standby=on
				log "SIM $data_sub silent for $((now - last_ok)) s: SIM $other woken up"
				reg=; for i in $(seq 1 20); do
					at $other 'AT+CEREG?' | grep -qE 'CEREG: [0-9],(1|5)' && { reg=1; break; }
					sleep 3
				done
				if [ -n "$reg" ]; then switch_data $other
				else log "SIM $other not registered after 60 s: no switch"
				fi
			fi
		elif [ -n "$healthy_since" ] && [ $((now - healthy_since)) -ge "$CALM_S" ]; then
			# Data SIM healthy: the standby SIM must sleep
			if [ "$standby" != "off" ] || [ $((now - last_check)) -ge "$CHECK_S" ]; then
				last_check=$now
				if ! at $other 'AT+COPS?' | grep -q '+COPS: 2'; then
					at $other 'AT+COPS=2' >/dev/null
					log "standby SIM $other deregistered, data on SIM $data_sub"
				fi
				standby=off
			fi
		fi
	fi
	echo "$standby ${data_sub:-?}" > "$STATE"
	sleep 5
done
