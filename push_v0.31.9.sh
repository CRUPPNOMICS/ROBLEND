#!/bin/bash
# ROBLEND 0.31.9 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.31.9.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.31.9 - Roblox camera, trackpad gestures, camera back home, Place with nothing selected, new shapes start at home" -m "Camera button / View > Roblox Camera: WASD/QE fly in every mode, right-drag looks (follows Studio's own camera turning), right mouse is camera-only, F focuses; held keys can't get stuck. Import starts from the home angle; Place in Studio resets Studio's camera and ROBLEND's view; reopening frames only what's in the workshop; Place in Studio with nothing selected takes everything; new shapes start at home and the view comes to them. Trackpads: two-finger swipe turns the view, Shift + swipe pans, pinch zooms.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.31.9
git push
git push --tags
echo "ROBLEND 0.31.9 pushed."
