# Changelog

## 1.2.0 — 2026-11-11

Dashboard redesign.

- Plain-language diagnosis of the last minute: only what needs attention (loss, stalls, weak coverage,
  interference, busy cell, handover ping-pong, unstable 5G, unbalanced antennas, uplink at high power,
  hot modem, standby SIM awake), with the likely cause; "Nothing to report" otherwise.
- Frequency map: which frequencies (700 to 3500 MHz) are in use now and how often over the selected range.
- Carrier table readable without expertise: frequency, role, width and a signal word; raw values kept for experts.
- Explanations behind every metric and chart label.
- Light theme with high contrast for sunlight; follows the OS, or forced from the header.
- Flattened layout, one surface and one radius; stats row instead of cards; consistent colours
  (blue = 4G, orange = 5G only); denser and readable on phones.

## 1.1.1 — 2026-11-11

- `glqos-simguard`: upgrading or reinstalling the package no longer wakes the standby SIM up
  (only a real removal does). The wake-up caused a few minutes of stalls after each upgrade.

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
