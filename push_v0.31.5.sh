#!/bin/bash
# ROBLEND 0.31.5 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.31.5.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.31.5 - Roblox camera fixes: no drifting into the sky, Studio camera reset after Place" -m "Camera button / View > Roblox Camera: WASD/QE fly in every mode, right-drag looks (follows Studio's own camera turning), right mouse is camera-only, F focuses; held keys can't get stuck; Studio's camera is reset after Place in Studio. Trackpads: two-finger swipe turns the view, Shift + swipe pans, pinch zooms.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.31.5
git push
git push --tags
echo "ROBLEND 0.31.5 pushed."
