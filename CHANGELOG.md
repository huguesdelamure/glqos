# Changelog

## 1.1.0 — 2026-11-11

First public release.

- Split into two packages: `glqos` (collector, pinger, dashboard) and the optional `glqos-simguard`.
- UCI configuration `/etc/config/glqos` (port, listen address, ping target, retention, guard timings).
- Dashboard listens on the LAN address by default instead of a fixed IP.
- English interface; browser locale for dates and numbers.
- `glqos-simguard` only starts on the GL-E5800, leaves GL's own failover setting untouched,
  and wakes the standby SIM up again when removed.

## 1.0.0 — 2026-11-11

Initial private version: 1 Hz collector, 5 Hz pinger, live dashboard, standby SIM guard,
history on `/data` and `keep.d` declarations for GL A/B firmware upgrades.
