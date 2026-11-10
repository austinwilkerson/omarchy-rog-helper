"""Optional software Fn Lock for the GZ302EA detachable keyboard."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

DEVICES = (
    "asustek-computer-inc.-gz302ea-keyboard",
    "asustek-computer-inc.-gz302ea-keyboard-2",
)
LAYOUT_FIELDS = ("rules", "model", "layout", "variant", "options")
MODES = ("function", "media")
DESCRIPTION = "ROG Helper: Toggle software Fn Lock"
KEYMAP_SUFFIX = " (ROG Helper Media)"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "rog-helper/fnlock"
MODE = STATE / "mode"
SETUP = STATE / "setup.json"
LUA = STATE / "fnlock.lua"


def supported():
    try:
        model = Path("/sys/class/dmi/id/product_name").read_text()
    except OSError:
        return False
    return re.search(r"\bGZ302EA\b|\bGZ302EA_GZ302EA\b", model) is not None


def command(*args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        raise RuntimeError((result.stderr.strip() or result.stdout.strip() or args[0] + " failed")[:300])
    return result.stdout.strip()


def hypr(*args):
    return command("hyprctl", *args)


def attached():
    return [key for key in json.loads(hypr("devices", "-j"))["keyboards"] if key["name"] in DEVICES]


def option(name):
    value = json.loads(hypr("getoption", name, "-j"))["str"]
    return "" if value == "[[EMPTY]]" else value


def layout():
    if option("input:kb_file"):
        raise RuntimeError("A global custom XKB file is active. Review it before setting up Fn Lock.")
    return {field: option("input:kb_" + field) for field in LAYOUT_FIELDS}


def fn_binds():
    return [
        bind for bind in json.loads(hypr("binds", "-j"))
        if bind["key"].lower() == "xf86fn_esc" or bind.get("keycode") == 473
    ]


def expect_binding(description):
    binds = fn_binds()
    if len(binds) != 1 or any(
        binds[0].get(key) != value
        for key, value in {"description": description, "modmask": 0, "submap": ""}.items()
    ):
        raise RuntimeError("Expected exactly one Fn+Esc binding. Review Hyprland bindings.")


def mode():
    value = MODE.read_text().strip()
    if value not in MODES:
        raise RuntimeError("Invalid saved Fn Lock mode. Rerun setup after reviewing the state files.")
    return value


def check_applied(value, *, require_keyboard=False):
    keyboards = attached()
    if require_keyboard and not keyboards:
        raise RuntimeError("Attach the Z13 keyboard to change Fn Lock mode.")
    if any(key["active_keymap"].endswith(KEYMAP_SUFFIX) != (value == "media") for key in keyboards):
        raise RuntimeError("The Z13 keyboard's active keymap does not match the saved Fn Lock mode.")
    return bool(keyboards)


def atomic_write(path, value):
    if path.is_symlink():
        raise RuntimeError(f"Review the symbolic link at {path} before proceeding.")
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
            if path.exists():
                temporary.chmod(path.stat().st_mode & 0o777)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


@contextmanager
def lock():
    STATE.mkdir(parents=True, mode=0o700, exist_ok=True)
    with (STATE / "lock").open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def lua_string(value):
    if any(ord(char) < 32 for char in value):
        raise ValueError("Control characters in a keyboard setting or path are unsupported.")
    return json.dumps(value, ensure_ascii=False)


def check_setup():
    settings = json.loads(SETUP.read_text())
    if settings["layout"] != layout():
        raise RuntimeError("The keyboard layout changed. Remove and set up Fn Lock again to rebuild its keymap.")
    expect_binding(DESCRIPTION)


def status():
    result = {"supported": supported(), "configured": SETUP.is_file(), "available": False}
    if result["supported"] and result["configured"]:
        try:
            with lock():
                check_setup()
                result["mode"] = mode()
                result["available"] = check_applied(result["mode"])
                if not result["available"]:
                    result["message"] = "Attach the Z13 keyboard to change its saved mode."
        except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            result["message"] = str(error)
    return result


def apply(value):
    code = f"dofile({lua_string(str(LUA))}).apply({lua_string(value)})"
    if hypr("eval", code) != "ok":
        raise RuntimeError("Hyprland rejected the Fn Lock change.")
    check_applied(value)


def change(request):
    if request not in (*MODES, "toggle"):
        raise ValueError("Choose function, media or toggle.")
    if not supported() or not SETUP.is_file():
        raise RuntimeError("Set up optional Fn Lock on the GZ302EA first.")
    with lock():
        check_setup()
        previous = mode()
        check_applied(previous, require_keyboard=True)
        target = ("function" if previous == "media" else "media") if request == "toggle" else request
        if target == previous:
            return previous
        # Publish the desired mode first so a simultaneous reload uses it too.
        atomic_write(MODE, target + "\n")
        try:
            apply(target)
        except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            try:
                atomic_write(MODE, previous + "\n")
                apply(previous)
            except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as rollback:
                raise RuntimeError(f"Fn Lock change failed: {error}. Recovery failed: {rollback}. Reload Hyprland.") from error
            raise RuntimeError(f"Fn Lock change failed. Previous mode restored: {error}") from error
        return target
