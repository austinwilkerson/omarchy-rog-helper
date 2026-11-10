#!/usr/bin/env bash
# Omarchy invokes theme-set hooks after applying the theme's keyboard RGB.
backend="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/rog-helper/backend.py"
if [[ -f "$backend" ]]; then
    exec python3 -B "$backend" theme-changed
fi
