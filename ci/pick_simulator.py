"""Gibt die UDID eines iPhone-Pro-Simulators mit der neuesten iOS-Version aus."""
import json, subprocess, sys

out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
devices = json.loads(out)["devices"]
for runtime in sorted(devices, reverse=True):
    for d in devices[runtime]:
        if d["name"].startswith("iPhone") and "Pro" in d["name"]:
            print(d["udid"])
            sys.exit()
sys.exit("kein iPhone-Simulator gefunden")
