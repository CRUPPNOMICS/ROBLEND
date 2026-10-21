#!/bin/bash
# ROBLEND 0.31.0 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.31.0.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.31.0 - Roblox camera (right-drag look, WASD fly)" -m "A camera button in the 3D view's header switches to Roblox Studio controls: hold right mouse + drag = look, WASD fly while right mouse is held (Q/E down/up, Shift slower), wheel zoom, middle mouse pan, F focus. Quick right-click still opens the menu.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HbZMuUEN5EEorB1Zb2BRtB"
git tag v0.31.0
git push
git push --tags
echo "ROBLEND 0.31.0 pushed."
