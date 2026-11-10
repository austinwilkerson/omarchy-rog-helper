"""Read power information and optionally match the internal screen to AC power."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from fnlock import atomic_write, command, supported

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME") or Path.home()/".local/state") / "rog-helper"
POWER_SUPPLY = Path("/sys/class/power_supply")
FIRMWARE_ATTRIBUTES = Path("/sys/class/firmware-attributes/asus-armoury/attributes")
RATES = (60, 180)


def number(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def on_battery():
    try:
        result = json.loads(command("busctl", "--system", "--json=short", "get-property",
                                    "org.freedesktop.UPower", "/org/freedesktop/UPower",
                                    "org.freedesktop.UPower", "OnBattery"))
        value = result["data"]
        return value if isinstance(value, bool) else None
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        return None


def battery_readings(directory):
    power = number(directory/"power_now")
    if power is None:
        current = number(directory/"current_now")
        voltage = number(directory/"voltage_now")
        if current is not None and voltage is not None and voltage > 0:
            power = current * voltage / 1_000_000
    full = number(directory/"energy_full")
    design = number(directory/"energy_full_design")
    valid_energy = full is not None and full > 0 and design is not None and design > 0
    if valid_energy:
        health = round(100 * full / design)
    else:
        charge = number(directory/"charge_full")
        design_charge = number(directory/"charge_full_design")
        health = round(100 * charge / design_charge) if charge and charge > 0 and design_charge and design_charge > 0 else None
    return {
        "watts": round(abs(power) / 1_000_000, 1) if power is not None else None,
        "fullWh": round(full / 1_000_000, 1) if valid_energy else None,
        "designWh": round(design / 1_000_000, 1) if valid_energy else None,
        "health": health,
    }


def power_limits():
    result = {}
    for name, attribute in (("PL1", "ppt_pl1_spl"), ("PL2", "ppt_pl2_sppt"), ("PL3", "ppt_pl3_fppt")):
        value = number(FIRMWARE_ATTRIBUTES/attribute/"current_value")
        if value is not None and value > 0:
            result[name] = value
    return result


def refresh_enabled():
    try:
        return (STATE_DIR/"auto-refresh").read_text().strip() == "on"
    except OSError:
        return False


@contextmanager
def refresh_lock():
    STATE_DIR.mkdir(parents=True, mode=0o700, exist_ok=True)
    with (STATE_DIR/"auto-refresh.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def display_modes():
    if not supported():
        raise ValueError("Auto refresh is available on the ROG Flow Z13 GZ302EA.")
    if not shutil.which("wlr-randr"):
        raise ValueError("Auto refresh requires wlr-randr.")
    outputs = json.loads(command("wlr-randr", "--json"))
    internal = [output for output in outputs if output["enabled"] and re.fullmatch(r"eDP-\d+", output["name"])]
    if len(internal) != 1:
        raise ValueError("The built-in display must be active.")
    output = internal[0]
    current = next((mode for mode in output["modes"] if mode["current"]), None)
    if not current:
        raise ValueError("Could not read the built-in display mode.")
    matching = [mode for mode in output["modes"]
                if (mode["width"], mode["height"]) == (current["width"], current["height"])]
    rates = {}
    for rate in RATES:
        mode = min(matching, key=lambda mode: abs(mode["refresh"] - rate))
        if abs(mode["refresh"] - rate) >= 0.5:
            raise ValueError("The built-in display needs 60 and 180 Hz at its current resolution.")
        rates[rate] = mode
    return output["name"], current, rates


def refresh_status(battery):
    state = {"enabled": refresh_enabled(), "available": False}
    if not supported():
        return state
    try:
        _, current, _ = display_modes()
        state["rate"] = round(current["refresh"])
        if battery is None:
            raise ValueError("The power source is unavailable.")
        state["available"] = True
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        state["message"] = str(error)
    return state


def apply_refresh():
    battery = on_battery()
    if battery is None:
        raise ValueError("The power source is unavailable.")
    output, current, rates = display_modes()
    target = rates[60 if battery else 180]
    if abs(current["refresh"] - target["refresh"]) < 0.01:
        return
    mode = f'{target["width"]}x{target["height"]}@{target["refresh"]:.3f}Hz'
    command("wlr-randr", "--output", output, "--mode", mode)
    _, applied, _ = display_modes()
    if abs(applied["refresh"] - target["refresh"]) >= 0.5:
        raise RuntimeError("The requested refresh rate did not take effect.")


def change_refresh(value):
    if value not in ("on", "off"):
        raise ValueError("Choose on or off for auto refresh.")
    with refresh_lock():
        if value == "on":
            apply_refresh()
        atomic_write(STATE_DIR/"auto-refresh", value + "\n")


def sync_refresh():
    if refresh_enabled():
        with refresh_lock():
            if refresh_enabled():
                apply_refresh()
