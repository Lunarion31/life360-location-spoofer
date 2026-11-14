#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import campus
import json
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import subprocess
import tempfile
import time
from pathlib import Path

BASE = ["xcrun", "devicectl", "device"]
DEVICE = ""
CONTAINER = []


def run(*args):
    return subprocess.run(BASE + list(args) + ["--timeout", "8"],
                          capture_output=True, text=True)

def weekly_plan(data):
    config = {"timezone": "America/New_York", "walking_meters_per_second": 1.4,
              "places": {}, "days": {}, "routines": {}}
    for day, stops in data["week"].items():
        config["days"][day] = day
        config["routines"][day] = []
        for i, stop in enumerate(stops):
            key = f"{day}-{i}"
            config["places"][key] = [stop["lat"], stop["lon"]]
            config["routines"][day].append((stop["clock"], key))
    if not isinstance(data["days"], int) or not 1 <= data["days"] <= 30:
        raise ValueError("Choose between 1 and 30 calendar days.")
    if set(data["week"]) != set(campus.WEEK):
        raise ValueError("The schedule must include all seven weekdays.")
    start = datetime.now(ZoneInfo(config["timezone"])).date()
    plans = {}
    for offset in range(data["days"]):
        date = start + timedelta(days=offset)
        plans[date] = campus.schedule(config, date) if config["routines"][config["days"][campus.WEEK[date.weekday()]]] else []
    return plans

def main():
    global DEVICE, CONTAINER
    parser = argparse.ArgumentParser(description="Connect the iPhone app to Xcode location simulation.")
    parser.add_argument("--device", required=True, help="Paired iPhone name or UDID")
    parser.add_argument("--bundle-id", default="helloworld6767")
    args = parser.parse_args()
    DEVICE = args.device
    CONTAINER = ["--device", DEVICE, "--domain-type", "appDataContainer",
                 "--domain-identifier", args.bundle_id]
    lock_name = hashlib.sha256(DEVICE.encode()).hexdigest()
    lock_path = Path(tempfile.gettempdir()) / f"campus-location-{lock_name}.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("A helper is already running for this device.")
        serve()


def serve():
    print("Drive helper ready. Keep this window open while using Drive.", flush=True)
    with tempfile.TemporaryDirectory() as folder:
        request = Path(folder) / "request.json"
        route = Path(folder) / "route.json"
        last = None
        plans = None
        previous = None
        try:
            while True:
                result = run("copy", "from", *CONTAINER, "--source", "Documents/drive-request.json",
                             "--destination", str(request))
                if result.returncode == 0:
                    try:
                        data = json.loads(request.read_text())
                        if not isinstance(data, dict) or not isinstance(data.get("id"), str):
                            raise ValueError("Missing request ID")
                        age = time.time() - float(data["created"])
                    except (ValueError, KeyError, TypeError):
                        time.sleep(2)
                        continue
                    if data["id"] != last and 0 <= age < 60:
                        command = ["simulate", "location"]
                        message = None
                        try:
                            if "week" in data:
                                candidate = weekly_plan(data)
                                now = datetime.now(ZoneInfo("America/New_York"))
                                stops = candidate[now.date()]
                                point = campus.position(stops, now) if stops else None
                                if point:
                                    command += ["coordinate", "--device", DEVICE, f"--latitude={point[0]}", f"--longitude={point[1]}"]
                                else:
                                    command += ["clear", "--device", DEVICE]
                            elif "hold" in data:
                                lat, lon = data["hold"]
                                if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                                    raise ValueError("Invalid hold coordinate.")
                                command += ["coordinate", "--device", DEVICE, f"--latitude={lat}", f"--longitude={lon}"]
                                message = "Holding the selected GPS fix."
                            elif data.get("stop"):
                                command += ["clear", "--device", DEVICE]
                            else:
                                route.write_text(json.dumps(data["route"]))
                                command += ["route", "--device", DEVICE, "--route-file", str(route)]
                            reply = run(*command)
                            ok = reply.returncode == 0
                            if ok:
                                plans = candidate if "week" in data else None
                                previous = point if plans else None
                                if plans:
                                    message = f"Routine started through {max(plans):%b %d}. Keep the Mac connected."
                            else:
                                message = "Mac could not apply the request. Check the phone connection."
                            print(reply.stdout or reply.stderr, flush=True)
                        except (ValueError, KeyError, TypeError, OverflowError) as error:
                            ok = False
                            message = str(error)
                        last = data["id"]
                        status = Path(folder) / "status.json"
                        result_data = {"id": last, "ok": ok}
                        if message:
                            result_data["message"] = message
                        status.write_text(json.dumps(result_data))
                        run("copy", "to", *CONTAINER, "--source", str(status),
                            "--destination", "Documents/drive-status.json")
                if plans and result.returncode == 0:
                    now = datetime.now(ZoneInfo("America/New_York"))
                    stops = plans.get(now.date())
                    point = campus.position(stops, now) if stops else None
                    if point != previous or stops is None:
                        args = ["coordinate", "--device", DEVICE, f"--latitude={point[0]}", f"--longitude={point[1]}"] if point else ["clear", "--device", DEVICE]
                        if run("simulate", "location", *args).returncode == 0:
                            previous = point
                            if stops is None:
                                plans = None
                time.sleep(2)
        except KeyboardInterrupt:
            pass
        finally:
            if plans:
                run("simulate", "location", "clear", "--device", DEVICE)


if __name__ == "__main__":
    main()
