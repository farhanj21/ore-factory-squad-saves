# Ore Factory Squad — 3-Player Co-op with Host-Left Continuity

## Goal
3 players share one world. If the host (the one who created the save) leaves,
the remaining players can continue from the same world.

## How the game works (analyzed)
- Host-authoritative: the host's PC runs the server; the world save exists only
  on the host's machine. No host migration exists in the game.
- Save folder: C:\Users\<user>\AppData\LocalLow\threeW\Ore Factory Squad\Saves\<world>_<slot>\
- Clients don't need the save to join (host streams the world); only the next
  host needs it.
- Multiplayer: Steam lobby + Steam P2P (Mirror + FizzySteam). 3-player online-fix
  connections already work. All 3 must run the same game version (1.0.4).
- Never sync: Player.log, Player-prev.log, RemoteConfigCache.json,
  MultiplayerCache/ (client-side temp).

## Solution
Use the game's Saves folder itself as a git repo backed by a private GitHub
repo. The current host pushes the save; the next host pulls it, loads the same
slot, and everyone rejoins.

## Setup
1. On the machine that owns the save, make Saves a git repo and push:
```bash
# Navigate to the Ore Factory Squad save directory
cd "$HOME/AppData/LocalLow/threeW/Ore Factory Squad/Saves"

# Initialize a Git repository
git init

# Add your GitHub repository as the remote
git remote add origin https://github.com/<your-username>/ore-factory-squad-saves.git

# Stage and commit your save files
git add -A
git commit -m "Initial save"

# Push to GitHub
git branch -M main
git push -u origin main
```
2. On the other 2 PCs: clone that repo into the same Saves folder location.
3. Add a .gitignore in the repo:
```bash
   Player*.log
   RemoteConfigCache.json
   MultiplayerCache/
```

## Canonical setup (agreed)
- Canonical save slot: **OFS_0001** (the world). OFS_0000 is the game's save-slot
  index — do not delete it; sync it like any other file.
- Game version: all 3 players must run **1.0.4**.

## Using the sync tool
`Sync-OreSquad.ps1` wraps the whole loop so nobody has to touch raw git.
Double-click `Sync-OreSquad.cmd` for a menu, or run the script directly:

| Command | When |
|---|---|
| `.\Sync-OreSquad.ps1 -Pull` | Before hosting (game closed) |
| `.\Sync-OreSquad.ps1 -Push` | After playing/saving (game closed) |
| `.\Sync-OreSquad.ps1` | Full handoff: pull then push |
| `.\Sync-OreSquad.ps1 -Message "..."` | Override the commit subject |
| `.\Sync-OreSquad.ps1 -AutoPush` | Skip the confirmation prompts |

It prints a standard commit message built from the save files:
```
save 2026-08-03 21:35 | edging and co. | day 6 | Lv4 | Ammar

Changed: 214 file(s) (42 chunk(s) dug) | slot OFS_0001
World: edging and co. | players: 3 | progression: 6 | entities: 2467
Note: <optional>
```

Safety guards built in:
- Refuses all git operations while the game is running.
- Refuses to run if the script on disk differs from the committed version
  (blocks a swapped-script attack).
- Refuses to push to any remote other than the official repo.
- Aborts on pull conflicts — never auto-merges or force-pushes. Rule on
  conflict: stop, keep the newest save, push that one over the remote.

## Workflow
- Routine: **pull (game closed) → play → save & quit → push (game closed)**.
- Handoff: host saves & quits and pushes → next host pulls, loads slot
  OFS_0001 → other 2 join via Steam invite.
- If someone launches the game directly (not via the script): after quitting,
  run `.\Sync-OreSquad.ps1 -Push` to sync — one command.
- Rules: one host at a time; always pull before hosting; close the game before
  any git operation; on pull conflict, stop, keep the newest save, push that.

## Risks
- Binary saves may grow large; if the repo passes ~1GB, enable Git LFS on
  Saves/** or switch to cloud sync.
- A crash resumes from the last pushed save, not the exact moment of the crash.
