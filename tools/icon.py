"""Rebuild src/Icon.lua from assets/roblend_icon.png (64 x 64 RGBA, base64). Needs Pillow.
SPDX-License-Identifier: GPL-2.0-or-later"""
import base64, pathlib, re
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
im = Image.open(root / 'assets' / 'roblend_icon.png').convert('RGBA').resize((64, 64), Image.LANCZOS)
b64 = base64.b64encode(im.tobytes()).decode()
lines = ',\n'.join('\t"%s"' % b64[i:i + 120] for i in range(0, len(b64), 120))
src = (root / 'src' / 'Icon.lua').read_text()
src = re.sub(r'Icon\.DATA = table\.concat\(\{\n.*?\n\}\)', 'Icon.DATA = table.concat({\n' + lines + '\n})', src, flags=re.S)
(root / 'src' / 'Icon.lua').write_text(src)
print('Icon.lua updated')
