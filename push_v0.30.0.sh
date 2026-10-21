#!/bin/bash
# ROBLEND 0.30.0 - commit + tag + push (run: bash ~/Documents/ROBLEND/push_v0.30.0.sh)
cd ~/Documents/ROBLEND || exit 1
git add src tests README.md release
git commit -m "ROBLEND 0.30.0 - transform gizmo (move / rotate / scale handles)"
git tag v0.30.0
git push
git push --tags
echo "ROBLEND 0.30.0 pushed."
