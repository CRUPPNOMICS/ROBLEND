#!/bin/bash
# ROBLEND 0.31.3 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.31.3.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.31.3 - Roblox camera (Studio controls) + trackpad gestures" -m "Camera button / View > Roblox Camera: WASD flies like Studio (Object Mode; Edit Mode with right mouse), right-drag looks (follows Studio's own camera when Studio grabs right mouse), right mouse is camera-only, F focuses. Trackpads: two-finger swipe turns the view, Shift + swipe pans, pinch zooms.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.31.3
git push
git push --tags
echo "ROBLEND 0.31.3 pushed."
