"""Run the tests with the Luau CLI: engine tests (BMesh + Ops + MeshTools + Modifiers) and the editor smoke test
(Main + every module in a fake Studio). usage: python3 tools/test.py [path-to-luau]
SPDX-License-Identifier: GPL-2.0-or-later"""
import pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
luau = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else 'luau'
rd = lambda p: (root / p).read_text()

# module file -> the global name it gets in the test bundle (the same names Main uses for its requires)
MODULES = [('BMesh', 'BMesh'), ('Ops', 'Ops'), ('MeshTools', 'MT'), ('Modifiers', 'Mods'), ('Display', 'Display'),
           ('UI', 'UI'), ('View', 'View'), ('Icon', 'Icon'), ('ObjectTools', 'ObjectTools')]
EXTRA = [m.stem for m in sorted((root / 'src').glob('*.lua')) if m.stem not in [a for a, _ in MODULES] and m.stem != 'Main.server']
MODULES += [(m, m) for m in EXTRA]   # new modules (Sculpt, Paint, ...) are picked up by their own name
ALIAS = dict(MODULES)


def mod(name, text):
    for file, alias in MODULES:
        text = text.replace(f'require(script.Parent.{file})', alias)
    return f'{name} = (function()\n{text}\nend)()\n'


def run(tag, src):
    out = root / f'tests/_run_{tag}.luau'
    out.write_text(src)
    r = subprocess.run([luau, str(out)], capture_output=True, text=True)
    print(f'--- {tag}\n' + r.stdout + r.stderr)
    return r.returncode


engine = (rd('tests/mock.luau') + ''.join(mod(ALIAS[n], rd(f'src/{n}.lua')) for n in ('BMesh', 'Ops', 'MeshTools', 'Modifiers', 'Sculpt', 'Paint', 'Font', 'Boolean', 'UVTools'))
          + 'do\n' + rd('tests/test_engine.luau') + '\nend\n' + rd('tests/test_tools.luau'))
main = rd('src/Main.server.lua')
for a, b in [('os.clock()', 'MOCK.t'), ('local function setStatus(t) status.Text = t', 'local function setStatus(t) status.Text = t MOCK.status = t'),
             ('view = View.new(ui.canvas)', 'view = View.new(ui.canvas) MOCK.view = view'),
             ('local api = { version = VERSION, logoImage = logoImage }', 'local api = { version = VERSION, logoImage = logoImage } MOCK.api = api')]:
    assert a in main, a
    main = main.replace(a, b)
for file, alias in MODULES:
    main = main.replace(f'require(script.{file})', alias)
assert 'require(script.' not in main, 'a require the test bundle does not know: ' + main[main.index('require(script.'):][:60]
editor = (rd('tests/mock.luau') + rd('tests/studio_mock.luau') + 'MOCK.t = 0\n' + ''.join(mod(alias, rd(f'src/{file}.lua')) for file, alias in MODULES)
          + ';(function()\n' + main + '\nend)()\n' + rd('tests/test_editor.luau'))  # own function: Main gets its own 200 locals
if '--write-only' in sys.argv:
    (root / 'tests/_run_editor.luau').write_text(editor)
    sys.exit(0)
rc = run('engine', engine) | run('editor', editor)
sys.exit(rc)
