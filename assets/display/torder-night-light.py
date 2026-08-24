#!/usr/bin/python3
"""Apply GNOME Night Light state through RandR on the tablet's X11 session."""

import math
import os
import re
import subprocess
import time


COLOR_DEST = "org.gnome.SettingsDaemon.Color"
COLOR_PATH = "/org/gnome/SettingsDaemon/Color"
PROPERTIES = "org.freedesktop.DBus.Properties.Get"


def dbus_property(name):
    result = subprocess.run(
        [
            "gdbus", "call", "--session", "--dest", COLOR_DEST,
            "--object-path", COLOR_PATH, "--method", PROPERTIES,
            "org.gnome.SettingsDaemon.Color", name,
        ],
        check=True, capture_output=True, text=True, timeout=3,
    )
    return result.stdout


def night_light_state():
    active = "true" in dbus_property("NightLightActive").lower()
    result = subprocess.run(
        [
            "gsettings", "get", "org.gnome.settings-daemon.plugins.color",
            "night-light-temperature",
        ],
        check=True, capture_output=True, text=True, timeout=3,
    )
    match = re.search(r"\b([1-9][0-9]{2,4})\b", result.stdout)
    if not match:
        raise ValueError("Night Light target temperature was not returned")
    return active, max(1000, min(6500, int(match.group(1))))


def kelvin_rgb(temperature):
    value = temperature / 100.0
    red = 255.0 if value <= 66 else 329.698727446 * ((value - 60) ** -0.1332047592)
    green = (99.4708025861 * math.log(value) - 161.1195681661
             if value <= 66 else 288.1221695283 * ((value - 60) ** -0.0755148492))
    blue = (255.0 if value >= 66 else
            (0.0 if value <= 19 else 138.5177312231 * math.log(value - 10) - 305.044792731))
    return tuple(max(0.1, min(1.0, component / 255.0))
                 for component in (red, green, blue))


def connected_outputs():
    result = subprocess.run(
        ["xrandr", "--query"], check=True, capture_output=True,
        text=True, timeout=3,
    )
    return [line.split()[0] for line in result.stdout.splitlines()
            if " connected" in line]


def apply_gamma(active, temperature):
    gamma = kelvin_rgb(temperature) if active else (1.0, 1.0, 1.0)
    value = ":".join(f"{component:.3f}" for component in gamma)
    for output in connected_outputs():
        subprocess.run(
            ["xrandr", "--output", output, "--gamma", value],
            check=True, timeout=3,
        )
    return value


def prepare_x11_environment():
    os.environ.setdefault("DISPLAY", ":0")
    if "XAUTHORITY" not in os.environ:
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        os.environ["XAUTHORITY"] = os.path.join(runtime, "gdm", "Xauthority")


def main():
    prepare_x11_environment()
    last = None
    while True:
        try:
            state = night_light_state()
            if state != last:
                gamma = apply_gamma(*state)
                print(f"active={state[0]} temperature={state[1]} gamma={gamma}", flush=True)
                last = state
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            if str(error) != last:
                print(f"waiting for GNOME X11 session: {error}", flush=True)
                last = str(error)
        time.sleep(2)


if __name__ == "__main__":
    main()
