"""Run the tests with the Luau CLI: engine tests (BMesh + Ops) and the editor smoke test (Main in a fake Studio).
usage: python3 tools/test.py [path-to-luau]"""
import pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
luau = sys.argv[1] if len(sys.argv) > 1 else 'luau'
rd = lambda p: (root / p).read_text()


def mod(name, text):
    text = text.replace('require(script.Parent.BMesh)', 'BMesh').replace('require(script.Parent.Ops)', 'Ops').replace('require(script.Parent.MeshTools)', 'MT')
    return f'{name} = (function()\n{text}\nend)()\n'


def run(tag, src):
    out = root / f'tests/_run_{tag}.luau'
    out.write_text(src)
    r = subprocess.run([luau, str(out)], capture_output=True, text=True)
    print(f'--- {tag}\n' + r.stdout + r.stderr)
    return r.returncode


engine = (rd('tests/mock.luau') + mod('BMesh', rd('src/BMesh.lua')) + mod('Ops', rd('src/Ops.lua')) + mod('MT', rd('src/MeshTools.lua')) + mod('Mods', rd('src/Modifiers.lua'))
          + 'do\n' + rd('tests/test_engine.luau') + '\nend\n' + rd('tests/test_tools.luau'))
main = rd('src/Main.server.lua')
for a, b in [('require(script.BMesh)', 'BMesh'), ('require(script.Ops)', 'Ops'), ('require(script.Display)', 'Display'),
             ('os.clock()', 'MOCK.t'), ('local function setStatus(t) status.Text = t', 'local function setStatus(t) status.Text = t MOCK.status = t'), ('require(script.UI)', 'UI'), ('require(script.View)', 'View'), ('require(script.MeshTools)', 'MT'), ('require(script.Modifiers)', 'Mods'), ('require(script.Icon)', 'Icon'), ('view = View.new(ui.canvas)', 'view = View.new(ui.canvas) MOCK.view = view'), ('local api = { version = VERSION, logoImage = logoImage }', 'local api = { version = VERSION, logoImage = logoImage } MOCK.api = api')]:
    assert a in main, a
    main = main.replace(a, b)
editor = (rd('tests/mock.luau') + rd('tests/studio_mock.luau') + 'MOCK.t = 0\n' + mod('BMesh', rd('src/BMesh.lua')) + mod('Ops', rd('src/Ops.lua'))
          + mod('Display', rd('src/Display.lua')) + mod('MT', rd('src/MeshTools.lua')) + mod('Mods', rd('src/Modifiers.lua')) + mod('UI', rd('src/UI.lua')) + mod('View', rd('src/View.lua')) + mod('Icon', rd('src/Icon.lua')) + 'do\n' + main + '\nend\n' + rd('tests/test_editor.luau'))
rc = run('engine', engine) | run('editor', editor)
sys.exit(rc)
