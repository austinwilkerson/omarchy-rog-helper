"""Install or remove the opt-in Hyprland Fn Lock configuration."""

import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fnlock as fn

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
HYPR = CONFIG / "hypr"
PLUGIN = CONFIG / "omarchy/plugins/rog-helper"
INPUT = HYPR / "input.lua"
BINDS = HYPR / "bindings.lua"
LEGACY_MODE = Path.home() / ".local/state/omarchy/z13-fnlock-enabled"
LEGACY_DESCRIPTION = "Toggle Z13 Fn-lock"
LEGACY_MARKER = "-- ROG Helper migrated the Z13 Fn+Esc binding from here.\n"
LEGACY_BIND = '''-- Fn+Esc is emitted as KEY_FN_ESC by the Z13 USB keyboard.
o.bind("XF86Fn_Esc", "Toggle Z13 Fn-lock", os.getenv("HOME") .. "/.local/bin/z13-fnlock")
'''
LEGACY_INPUT = '''-- Z13 software Fn-lock: only remap this laptop's USB keyboard.
do
  local home = os.getenv("HOME")
  local flag = io.open(home .. "/.local/state/omarchy/z13-fnlock-enabled", "r")
  local keymap = ""
  if flag then
    flag:close()
    keymap = home .. "/.config/hypr/xkb/z13-media.xkb"
  end
  for _, name in ipairs({"asustek-computer-inc.-gz302ea-keyboard", "asustek-computer-inc.-gz302ea-keyboard-2"}) do
    hl.device({ name = name, kb_file = keymap, resolve_binds_by_sym = true })
  end
end
'''
SYMBOLS = {
    "FK01": "XF86AudioMute",
    "FK02": "XF86AudioLowerVolume",
    "FK03": "XF86AudioRaiseVolume",
    "FK04": "XF86AudioMicMute",
    "FK05": "XF86Launch5",
    "FK06": "Print",
    "FK07": "XF86MonBrightnessDown",
    "FK08": "XF86MonBrightnessUp",
    "FK09": "XF86Display",
    "FK10": "XF86TouchpadToggle",
    "FK11": "XF86KbdLightOnOff",
    "FK12": "XF86RFKill",
}
EXTRA_BINDS = {"xf86launch5", "xf86display", "xf86rfkill"}


def hook():
    lua, backend, runtime = (fn.lua_string(str(p)) for p in (fn.LUA, PLUGIN / "backend.py", PLUGIN / "fnlock.lua"))
    return f'''-- BEGIN ROG Helper software Fn Lock
do
  local function readable(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
  end
  if readable({lua}) and readable({backend}) and readable({runtime}) then
    dofile({lua}).setup()
  end
end
-- END ROG Helper software Fn Lock
'''


def configured_lua(settings):
    quote = fn.lua_string
    fields = ", ".join(f"{key} = {quote(value)}" for key, value in settings.items())
    devices = ", ".join(map(quote, fn.DEVICES))
    command = shlex.join(["python3", "-B", str(PLUGIN / "backend.py")])
    return f'''return dofile({quote(str(PLUGIN / "fnlock.lua"))})({{
  layout = {{ {fields} }},
  devices = {{ {devices} }},
  mode = {quote(str(fn.MODE))},
  keymap = {quote(str(fn.STATE / "media.xkb"))},
  description = {quote(fn.DESCRIPTION)},
  command = {quote(command)},
}})
'''


def build_keymap(settings):
    if not settings["layout"] or "," in settings["layout"]:
        raise RuntimeError("Fn Lock currently supports one configured XKB layout. Review multiple-layout setups manually.")
    args = ["xkbcli", "compile-keymap", "--output-format", "1"]
    for field, value in settings.items():
        args.extend(["--" + field, value])
    result = fn.command(*args)
    result, count = re.subn(r'(?m)^([ \t]*name\[1\]\s*=\s*"[^"\n]*)(")', r'\g<1>' + fn.KEYMAP_SUFFIX + r'\2', result)
    if count != 1:
        raise RuntimeError("Could not identify the XKB layout group.")
    for key, symbol in SYMBOLS.items():
        result, count = re.subn(
            rf"(?ms)^(\s*)key <{key}>\s*\{{.*?\}};",
            rf"\1key <{key}> {{ [ {symbol} ] }};",
            result,
        )
        if count != 1:
            raise RuntimeError(f"Could not find {key} in the compiled keymap.")
    fn.command("xkbcli", "compile-keymap", "--input-format", "1", "--from-xkb", "-", "--test", data=result)
    return result + "\n"


def inspect_config():
    if 'require("hypr.input")' not in (HYPR / "hyprland.lua").read_text():
        raise RuntimeError("Expected Omarchy's Hyprland Lua input configuration.")
    before = {p: p.read_text() for p in (INPUT, BINDS)}
    after = dict(before)
    legacy = before[INPUT].count(LEGACY_INPUT) == before[BINDS].count(LEGACY_BIND) == 1
    if legacy:
        fn.expect_binding(LEGACY_DESCRIPTION)
        after[INPUT] = before[INPUT].replace(LEGACY_INPUT, hook())
        after[BINDS] = before[BINDS].replace(LEGACY_BIND, LEGACY_MARKER)
    elif fn.fn_binds():
        raise RuntimeError("An existing Fn+Esc binding needs review. Setup accepts only the verified legacy configuration.")
    for binding in json.loads(fn.hypr("binds", "-j")):
        if binding["key"].lower() in EXTRA_BINDS and binding.get("modmask") == 0:
            raise RuntimeError(f"Review the existing {binding['key']} shortcut before setting up Fn Lock.")
    for path in HYPR.rglob("*"):
        if path.suffix not in (".lua", ".conf") or not path.is_file():
            continue
        candidate = before[path] if path in before else path.read_text()
        if legacy and path == INPUT:
            candidate = candidate.replace(LEGACY_INPUT, "")
        if legacy and path == BINDS:
            candidate = candidate.replace(LEGACY_BIND, "")
        # Conservative on purpose: custom device rules can change XKB behavior.
        if re.search(r"gz302ea-keyboard|XF86Fn_Esc|code:\s*473|ROG Helper software Fn Lock|ROG Helper migrated the Z13", candidate, re.I):
            raise RuntimeError(f"Review the existing Z13 device rule or Fn+Esc binding in {path}.")
    if not legacy:
        after[INPUT] = before[INPUT].rstrip("\n") + "\n\n" + hook()
    return before, after, legacy


def reload():
    if fn.hypr("reload") != "ok":
        raise RuntimeError("Hyprland rejected the reload.")
    errors = fn.hypr("configerrors")
    if errors:
        raise RuntimeError("Hyprland configuration errors: " + errors[:400])


def edit_config(before, after, verify):
    changed = {p: value for p, value in after.items() if before[p] != value}
    written = []
    try:
        for path, value in changed.items():
            if path.read_text() != before[path]:
                raise RuntimeError(f"{path} changed during setup.")
            fn.atomic_write(path, value)
            written.append(path)
        reload()
        verify()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        for path in reversed(written):
            if path.read_text() == changed[path]:
                fn.atomic_write(path, before[path])
        reload()
        raise


def install():
    if not fn.supported():
        raise RuntimeError("This optional setup is specific to the ROG Flow Z13 GZ302EA.")
    if not all((PLUGIN / name).is_file() for name in ("backend.py", "fnlock.py", "fnlock.lua")):
        raise RuntimeError("Install this version of ROG Helper before setting up Fn Lock.")
    if fn.SETUP.exists():
        if INPUT.read_text().count(hook()) != 1:
            raise RuntimeError("Review the existing managed block in input.lua.")
        fn.check_setup()
        fn.check_applied(fn.mode())
        print("ROG Helper Fn Lock is already set up.")
        return

    if fn.hypr("configerrors"):
        raise RuntimeError("Resolve existing Hyprland configuration errors before setup.")
    keyboards = fn.attached()
    if not keyboards:
        raise RuntimeError("Attach the GZ302EA keyboard before setup.")
    settings = fn.layout()
    if any(any(key.get(field) != value for field, value in settings.items()) for key in keyboards):
        raise RuntimeError("The Z13 keyboard has layout overrides. Review them before setup.")
    before, after, legacy = inspect_config()
    initial = "media" if legacy and LEGACY_MODE.exists() else "function"
    keymap = build_keymap(settings)

    backup = Path(tempfile.mkdtemp(prefix="before-", dir=fn.STATE))
    for path, value in before.items():
        fn.atomic_write(backup / path.name, value)
    fn.atomic_write(fn.STATE / "media.xkb", keymap)
    fn.atomic_write(fn.LUA, configured_lua(settings))
    fn.atomic_write(fn.MODE, initial + "\n")
    fn.atomic_write(fn.SETUP, json.dumps({"layout": settings, "legacy": legacy}) + "\n")

    def verify():
        fn.expect_binding(fn.DESCRIPTION)
        fn.check_applied(initial, require_keyboard=True)

    try:
        edit_config(before, after, verify)
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        if all(path.read_text() == value for path, value in before.items()):
            clear_state()
        print(f"Pre-setup backup: {backup}", file=sys.stderr)
        raise
    print(f"ROG Helper Fn Lock enabled ({initial} keys). Pre-setup backup: {backup}")


def clear_state():
    for path in (fn.SETUP, fn.LUA, fn.MODE, fn.STATE / "media.xkb"):
        path.unlink(missing_ok=True)


def remove():
    if not fn.SETUP.exists():
        print("ROG Helper Fn Lock is not set up.")
        return
    settings = json.loads(fn.SETUP.read_text())
    before = {p: p.read_text() for p in (INPUT, BINDS)}
    if before[INPUT].count(hook()) != 1 or (settings["legacy"] and before[BINDS].count(LEGACY_MARKER) != 1):
        raise RuntimeError("Managed Fn Lock configuration was edited. Review the block and backups before removal.")
    after = dict(before)
    after[INPUT] = before[INPUT].replace(hook(), LEGACY_INPUT if settings["legacy"] else "")
    if settings["legacy"]:
        after[BINDS] = before[BINDS].replace(LEGACY_MARKER, LEGACY_BIND)

    def verify():
        if settings["legacy"]:
            fn.expect_binding(LEGACY_DESCRIPTION)
        elif fn.fn_binds():
            raise RuntimeError("A separate Fn+Esc binding appeared. Review the config before removing Fn Lock.")
        fn.check_applied("function")  # The legacy media map has no ROG Helper group suffix.

    edit_config(before, after, verify)
    clear_state()
    print("ROG Helper Fn Lock removed. Previous keyboard configuration restored.")


if __name__ == "__main__":
    try:
        if sys.argv[1:] not in (["install"], ["remove"]):
            raise ValueError("Usage: fnlock-setup.py install|remove")
        with fn.lock():
            (install if sys.argv[1] == "install" else remove)()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"Fn Lock: {error}", file=sys.stderr)
        sys.exit(1)
