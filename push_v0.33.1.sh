#!/bin/bash
# ROBLEND 0.33.1 - Palette + shading. Run in Git Bash: bash ~/Documents/ROBLEND/push_v0.33.1.sh
set -e
cd ~/Documents/ROBLEND
git add -A
git commit -m "ROBLEND 0.33.1: Palette + shading (Material > Palette, face colours; true colours while colouring)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git push
echo "Pushed 0.33.1. Now upload build/ROBLEND.rbxmx to the Creator Store + a GitHub release."
