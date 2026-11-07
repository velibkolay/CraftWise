# forever_tools (vendored subset)

`__init__.py`, `csvtable.py`, `fsio.py` and `wago.py` are copied byte for byte from [cjber/forever-core](https://github.com/cjber/forever-core) (`.agents/skills/wow-forever-addon/tooling/forever_tools`, revision `0b3b073c92d4`), as vendored by [cjber/skillup-forever](https://github.com/cjber/skillup-forever) at commit `593e0e9`.

forever-core's repository licence at that revision is GPL-3.0, and SkillUp Forever's `THIRD_PARTY.md` lists this tooling as MIT. Either is compatible with CraftWise's GPL-3.0.

They exist only for `tools/gen_thresholds.py`, `gen_recipes.py` and `gen_vendor.py`, and are not part of the addon zip. Don't edit them here. `__init__.py` mentions `sync.py`, which isn't copied.
