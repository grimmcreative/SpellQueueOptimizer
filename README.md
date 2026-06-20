# SpellQueueOptimizer

Automatically optimizes the SpellQueueWindow (SQW) in World of Warcraft based on your latency and specialization.

Compatible with **Midnight (Patch 12.0)**.

## Features
- Reads latency and specialization to compute an optimal SQW value.
- Tuning follows current guidance: baseline 200 ms + ping, clamped 200–400 ms,
  with small per-spec corrections.
- Adjusts on login, spec/zone changes, and periodically (default 5 minutes).
- Combat-safe: changes are deferred during combat and applied when it ends
  (required since 12.0 locks secure CVars in combat).
- Slash commands for manual control and override.

## Installation
1. Download and unzip the addon.
2. Place the `SpellQueueOptimizer` folder into your WoW `Interface/AddOns/` directory.
3. Enable in the AddOn list.
4. Use `/sqo show` in game to check.

## Commands
- `/sqo show` – Show current SQW & ping
- `/sqo now` – Recalculate & apply now
- `/sqo on|off` – Enable/disable auto optimization
- `/sqo interval <sec>` – Set interval 60..900 seconds (default 300)
- `/sqo set <ms>` – Override SQW with fixed value
- `/sqo clear` – Remove override
- `/sqo quiet|verbose` – Toggle chat output

## Author
Maximilian Anton Grimm | grimm@grimmcreative.com
