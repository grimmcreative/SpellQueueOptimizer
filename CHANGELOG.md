# Changelog

## [1.1.0] - 2026-06-20
- Midnight (12.0) compatibility: bumped Interface to 120000.
- Migrated to C_CVar and C_SpecializationInfo namespaces (with legacy fallbacks).
- Combat-safe: secure CVars can no longer be set during combat in 12.0, so
  changes are now deferred and re-applied on combat end (PLAYER_REGEN_ENABLED).
- Retuned to current guidance: baseline 200 ms + ping, clamped 200..400 ms,
  with small per-spec corrections (replaces the old aggressive 60..140 ms logic).

## [1.0.0] - 2025-09-20
- Initial release of SpellQueueOptimizer
- Automatically adjusts SpellQueueWindow based on latency and spec
- Slash command interface (/sqo)
- Periodic auto-check (default 5 minutes)
