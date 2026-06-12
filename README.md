# ☢ claude-geiger

A Geiger counter that doesn't measure radioactivity — it measures **Claude tokens**.

Leave it running in a spare terminal. As your Claude Code sessions burn tokens, it
clicks like a Geiger tube: sparse lonely ticks while you're idle, a frantic crackle
when an agent fleet goes critical.

```
   ☢  CLAUDE GEIGER · dosimeter for token exposure

   ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯ ⚡CLICK

   RATE  42.0 ktok   /min     ZONE  CRITICAL
   DOSE  10.5 ktok           UPTIME  00:00:07
   LAST  +2.6 ktok  repo-claude-geiger

   cache reads shielded · ctrl-c to evacuate
```

## Run

```sh
node claude-geiger.js          # clicks + gauge
node claude-geiger.js --mute   # gauge only
```

No dependencies. Node ≥ 18. Audio via `afplay` on macOS, terminal bell elsewhere.

## Menu bar app (macOS)

A native menu bar version lives in `macos/` — same logic, no terminal needed.
☢ in the menu bar, tinted by zone, with the token rate next to it and the
full readout in the dropdown. Clicks play in-process; mute from the menu.

```sh
cd macos
make app                      # builds "Claude Geiger.app"
open "Claude Geiger.app"
```

Requires macOS 13+ and the Xcode command line tools (`swift`). Tests:
`make test`. The dropdown has a Launch at Login toggle (works from the
.app bundle, not from `swift run`).

## How it works

- Tails every live session transcript under `~/.claude/projects/**/*.jsonl`
  (override with `--dir`).
- Counts **fresh** tokens per assistant message: input + cache-creation + output.
  Cache reads are shielded background radiation and don't register.
- Streaming updates repeat the same message with growing counts; messages are
  deduplicated by id and only the delta registers.
- Click timing is a Poisson process whose rate follows tokens/min on a log
  scale, saturating at ~30 clicks/sec like a real tube. Even at zero activity
  you get the occasional cosmic-ray click.

## Readout

| Field | Meaning |
|-------|---------|
| RATE  | fresh tokens per minute, 15s sliding window |
| DOSE  | total tokens absorbed since launch |
| ZONE  | BACKGROUND → ELEVATED → HOT → CRITICAL → MELTDOWN |
| LAST  | most recent burst and which project emitted it |
