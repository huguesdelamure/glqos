# Changelog

## 1.3.1 — 2026-11-11

- `glqos`: restarting the service no longer leaves the previous `ping` running. Each restart
  added one more 5 Hz ping writing to the same file, which skewed the loss figures.
- `glqos-simguard`: after a restart the guard asks the modem whether the standby SIM is asleep
  instead of reporting it awake for two minutes.

## 1.3.0 — 2026-11-11

Network-analyzer look (Hallmark 2.0 restyle, Console theme); the layout is unchanged.

- Hairline panels cut from one graphite surface, charts on the deepest step, no shadows or glow.
- Bundled fonts so the page still works offline: Host Grotesk for labels, Atkinson Hyperlegible Mono
  for every measured value (SIL Open Font License 1.1).
- Colour meanings from the theme: cool blue for the instrument and 5G, neutral for 4G, amber for what
  needs your attention, green and red for status only.
- Light theme in the theme's warm, high-contrast paper colourway; dark in graphite.

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
