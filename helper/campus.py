"""Preview a weekly itinerary or replay it on a paired iPhone using Xcode."""
import argparse
import json
import math
import subprocess
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

WEEK = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2 - lat1) / 2)**2
    h += math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2)**2
    return 12742000 * math.asin(math.sqrt(min(1, h)))


def schedule(config, day):
    zone = ZoneInfo(config["timezone"])
    routine = config["days"][WEEK[day.weekday()]]
    speed = config["walking_meters_per_second"]
    if not math.isfinite(speed) or speed <= 0:
        raise ValueError("Walking speed must be positive.")
    stops = []
    for clock, name in config["routines"][routine]:
        point = config["places"][name]
        lat, lon = point
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError(f"Invalid coordinates for {name}")
        arrival = datetime.combine(day, datetime.strptime(clock, "%H:%M").time(), zone)
        departure = arrival
        if stops:
            previous, _, previous_point, _ = stops[-1]
            departure -= timedelta(seconds=distance(previous_point, point) / speed)
            if departure < previous or arrival <= previous:
                raise ValueError(f"Insufficient travel time before {clock} {name}")
        stops.append((arrival, name, point, departure))
    if not stops:
        raise ValueError(f"Empty routine: {routine}")
    return stops


def position(stops, now):
    point = stops[0][2]
    for arrival, _, target, departure in stops[1:]:
        if now < departure:
            break
        if now < arrival:
            t = (now - departure) / (arrival - departure)
            return tuple(a + (b - a) * t for a, b in zip(point, target))
        point = target
    return tuple(point)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(__file__).with_name("campus-week.json"))
    parser.add_argument("--date", type=date.fromisoformat, help="preview starting on YYYY-MM-DD")
    parser.add_argument("--days", type=int, default=1, help="number of calendar days")
    parser.add_argument("--live", action="store_true", help="follow the current local schedule")
    parser.add_argument("--device", help="paired iPhone identifier")
    args = parser.parse_args()
    if args.days < 1 or (args.live and args.date):
        parser.error("Use a positive day count. Live playback starts today.")
    if args.live and not args.device:
        parser.error("--device is required for live playback.")
    config = json.loads(args.config.read_text())
    zone = ZoneInfo(config["timezone"])
    start = args.date or datetime.now(zone).date()
    plans = {}
    for offset in range(args.days):
        day = start + timedelta(days=offset)
        stops = schedule(config, day)
        plans[day] = stops
        print(day, WEEK[day.weekday()], flush=True)
        for arrival, name, _, departure in stops:
            walk = f" (leave at {departure:%H:%M:%S})" if departure != arrival else ""
            print(f"  {arrival:%H:%M}  {name}{walk}")
    if not args.live:
        return
    base = ["xcrun", "devicectl", "device", "simulate", "location"]
    device = ["--device", args.device, "--timeout", "10"]
    last = None
    try:
        while True:
            now = datetime.now(zone)
            if now.date() not in plans:
                break
            lat, lon = position(plans[now.date()], now)
            point = (f"{lat:.7f}", f"{lon:.7f}")
            if point != last:
                subprocess.run(base + ["coordinate", *device, f"--latitude={point[0]}",
                                       f"--longitude={point[1]}"], check=True, stdout=subprocess.DEVNULL)
                last = point
            time.sleep(2)
    finally:
        if last is not None:
            subprocess.run(base + ["clear", *device], check=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
