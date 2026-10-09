"""Pack src/ into a Roblox plugin file (build/ROBLEND.rbxmx).
The Script 'ROBLEND' runs Main.server.lua; BMesh, Ops, MeshTools, Modifiers, Display, UI, View and Icon are ModuleScripts under it.
SPDX-License-Identifier: GPL-2.0-or-later
"""
import hashlib, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
src = root / 'src'
out = root / 'build' / 'ROBLEND.rbxmx'
ref = [0]


def cdata(text):
    return '<![CDATA[' + text.replace(']]>', ']]]]><![CDATA[>') + ']]>'


def item(cls, name, source, children=''):
    ref[0] += 1
    return (f'<Item class="{cls}" referent="RBX{ref[0]:04d}"><Properties>'
            f'<string name="Name">{name}</string>'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties>{children}</Item>')


mods = ''.join(item('ModuleScript', n, (src / f'{n}.lua').read_text()) for n in ('BMesh', 'Ops', 'MeshTools', 'Modifiers', 'Display', 'UI', 'View', 'Icon'))
main = item('Script', 'ROBLEND', (src / 'Main.server.lua').read_text(), mods)
xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
       'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
       '<External>null</External><External>nil</External>' + main + '</roblox>')
out.parent.mkdir(exist_ok=True)
out.write_bytes(xml.encode('utf-8'))
print(out, len(xml), 'bytes sha256', hashlib.sha256(xml.encode('utf-8')).hexdigest())
