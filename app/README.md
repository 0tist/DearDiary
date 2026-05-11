# DearDiary GUI (Tauri)

Always-open compose window. Type a thought, hit Save (or Cmd+Enter), and the
entry lands in `~/DearDiary/diary/inbox/<id>.md`. Every 15 minutes a launchd
job hands the inbox to a headless `claude -p` run that decides where each
entry belongs (`~/DearDiary/diary/<folder>/...`, optionally appending to
`~/DearDiary/TODO.md`). The "Process Now" button fires the same job
on-demand.

## Prerequisites

- macOS (Apple Silicon or Intel)
- Rust toolchain — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- Node 20+ — `brew install node` (or your preferred installer)
- The DearDiary install ran (`bash ../install.sh`) — that's what registers the
  launchd cron job and creates `~/DearDiary/diary/{inbox,processed}/`.

## Build

```bash
cd app
npm install
npm run tauri build
```

The bundled app lands at:

```
app/src-tauri/target/release/bundle/macos/DearDiary.app
```

Drag it to `/Applications` and pin it to your Dock. Closing the window keeps
the app alive (it just hides) so it stays in your app deck. Cmd+Q quits.

## Bake the repo path at build time

The Rust binary needs to know where this repo is on your machine so it can
spawn `scripts/diary-process.sh` when you click **Process Now**. Bake the
absolute path in at build time:

```bash
DEARDIARY_REPO="$(cd .. && pwd)" npm run tauri build
```

You can also override at runtime via the env var, but a shell-launched
`.app` doesn't inherit your shell env, so baking it in is the reliable path
for production use.

## Dev loop

```bash
DEARDIARY_REPO="$(cd .. && pwd)" npm run tauri dev
```

Opens a hot-reloading window. Save an entry, then `ls ~/DearDiary/diary/inbox/`
to confirm the file landed.

## Config knobs (env vars)

| Var | Default | Purpose |
|---|---|---|
| `DEARDIARY_DIR` | `$HOME/DearDiary` | Where the inbox/processed/diary tree lives |
| `DEARDIARY_REPO` | (baked at build) | Where this repo lives, for spawning `diary-process.sh` |

## Cron cadence

The launchd job (`com.deardiary.process`) ticks every 900s. Change in
`launchd/com.deardiary.process.plist.template`'s `StartInterval` and re-run
`bash ../install.sh` to re-register.
