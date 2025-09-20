# SpellQueueOptimizer

Automatically optimizes the SpellQueueWindow (SQW) in World of Warcraft based on your latency and specialization.

## Features
- Reads latency and specialization to compute an optimal SQW value.
- Adjusts on login, spec/zone changes, and periodically (default 5 minutes).
- Slash commands for manual control and override.
- Sensible defaults with clamps and rounding.

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
