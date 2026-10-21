#!/bin/bash
# ROBLEND 0.32.0 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.32.0.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.32.0 - Roblox camera, trackpad gestures, Modes button, tutorial, camera/home fixes" -m "Camera button / View > Roblox Camera: WASD/QE fly in every mode, right-drag looks (follows Studio's own camera turning), right mouse is camera-only, F focuses; held keys can't get stuck. Modes button (the Q menu) next to it; the tutorial ends by showing both. Import starts from the home angle; Place in Studio resets Studio's camera and ROBLEND's view; reopening frames only what's in the workshop; Place with nothing selected takes everything; new shapes start at home. Trackpads: two-finger swipe turns the view, Shift + swipe pans, pinch zooms.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.32.0
git push
git push --tags
echo "ROBLEND 0.32.0 pushed."
