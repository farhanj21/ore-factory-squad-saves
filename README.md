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

## Workflow
- Pull latest save → play → save & quit → commit & push. A small
  Start-OreSquad.ps1 can wrap this: pull → launch game → on quit, commit+push
  (with a pull-only mode).
- Handoff: host saves & quits (push happens) → next host pulls, loads the same
  save slot → other 2 join via Steam invite.
- Rules: one host at a time; always pull before hosting; close the game before
  any git operation; on pull conflict, stop, keep the newest save, push that.

## Risks
- Binary saves may grow large; if the repo passes ~1GB, enable Git LFS on
  Saves/** or switch to cloud sync.
- A crash resumes from the last pushed save, not the exact moment of the crash.
