#!/bin/bash
# ROBLEND 0.34.0 - MeshKeeper (store copies keep meshes in the place). Also commits the 0.31-0.33 work not pushed yet.
# Run in Git Bash: bash ~/Documents/ROBLEND/push_v0.34.0.sh
set -e
cd ~/Documents/ROBLEND
git add -A
git commit -m "ROBLEND 0.34.0: store copies keep meshes in the place (MeshKeeper); includes 0.31-0.33" -m "Roblox doesn't let Creator Store plugins upload meshes. A store copy now keeps each mesh in the place as data (MeshKeeperData + tag MeshKeeper) and adds the MeshKeeper scripts that build the real meshes when the game runs (needs Allow Mesh / Image APIs). Shared with PROTO 4.04. The file version still uploads.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.34.0
git push
git push --tags
echo "Pushed 0.34.0. Now upload build/ROBLEND.rbxmx to the Creator Store + a GitHub release."
