import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import backend
import power_state


class PowerReadings(unittest.TestCase):
    def test_energy_and_power_use_the_right_units(self):
        with tempfile.TemporaryDirectory() as directory:
            battery = Path(directory)
            for name, value in {
                "energy_full": 59_500_000,
                "energy_full_design": 70_000_000,
                "current_now": -1_500_000,
                "voltage_now": 12_000_000,
            }.items():
                (battery/name).write_text(str(value))
            self.assertEqual(power_state.battery_readings(battery),
                             {"watts": 18.0, "fullWh": 59.5, "designWh": 70.0, "health": 85})


class AutoRefresh(unittest.TestCase):
    def test_auto_uses_only_an_internal_mode_at_the_current_resolution(self):
        panel = {
            "name": "eDP-1", "enabled": True,
            "modes": [
                {"width": 2560, "height": 1600, "refresh": 180.0, "current": True},
                {"width": 2560, "height": 1600, "refresh": 60.0, "current": False},
                {"width": 1920, "height": 1080, "refresh": 60.0, "current": False},
            ],
        }
        external = {"name": "DP-1", "enabled": True, "modes": []}

        def command(*args):
            if args == ("wlr-randr", "--json"):
                return json.dumps([external, panel])
            self.assertEqual(args, ("wlr-randr", "--output", "eDP-1", "--mode", "2560x1600@60.000Hz"))
            panel["modes"][0]["current"] = False
            panel["modes"][1]["current"] = True
            return ""

        with patch.object(power_state, "supported", return_value=True), \
             patch.object(power_state.shutil, "which", return_value="/usr/bin/wlr-randr"), \
             patch.object(power_state, "on_battery", return_value=True), \
             patch.object(power_state, "command", side_effect=command) as run:
            power_state.apply_refresh()
            self.assertTrue(panel["modes"][1]["current"])
            run.reset_mock()
            power_state.apply_refresh()
            run.assert_called_once_with("wlr-randr", "--json")
            panel["modes"].pop(0)
            with self.assertRaisesRegex(ValueError, "60 and 180 Hz"):
                power_state.apply_refresh()


class ChargeOnce(unittest.TestCase):
    def test_one_shot_uses_daemon_method_and_verifies_temporary_cap(self):
        with tempfile.TemporaryDirectory() as directory:
            battery = Path(directory)/"BAT0"
            battery.mkdir()
            (battery/"type").write_text("Battery\n")
            threshold = battery/"charge_control_end_threshold"
            threshold.write_text("80\n")
            with patch.object(power_state, "POWER_SUPPLY", Path(directory)), \
                 patch.object(power_state, "on_battery", return_value=True) as on_battery, \
                 patch.object(backend, "run", side_effect=lambda *_: threshold.write_text("100\n")) as run:
                with self.assertRaisesRegex(ValueError, "Plug in the charger"):
                    backend.charge_once()
                run.assert_not_called()
                on_battery.return_value = False
                self.assertIn("restores your 80% limit", backend.charge_once())
                run.assert_called_once_with("busctl", "--system", "call", backend.DEST, "/xyz/ljones",
                                            backend.PLATFORM, "OneShotFullCharge")
                with self.assertRaisesRegex(ValueError, "below 100%"):
                    backend.charge_once()
