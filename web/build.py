"""Inject the compiled BtcVault bytecode into the web page. Run after `forge build`."""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
art = json.loads((root / "out/BtcVault.sol/BtcVault.json").read_text())
bytecode = art["bytecode"]["object"]
tpl = (root / "web/index.template.html").read_text()
html = tpl.replace("__BYTECODE__", bytecode)
(root / "web/index.html").write_text(html)
# GitHub Pages serves /docs on main
(root / "docs").mkdir(exist_ok=True)
(root / "docs/index.html").write_text(html)
(root / "docs/.nojekyll").write_text("")
print(f"web/index.html written ({len(bytecode)//2 - 1} bytes of bytecode)")
