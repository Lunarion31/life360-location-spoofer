# Life360 Location Spoofer

An iPhone map and GPS debugger with a small Mac companion.

- Pick driving destinations and export GPX routes.
- Edit a weekly routine with map pins and arrival times.
- Hold the current coordinate or clear simulation.
- Inspect location timestamps and source flags.

Requires Xcode 27.2, Python 3.9+, and a paired iPhone with Developer Mode enabled.

1. Open `CampusLocationLab.xcodeproj`, select your signing team, and run `MyApp`.
2. Find your phone with `xcrun devicectl list devices`.
3. Start the companion on your Mac:

```sh
python3 helper/drive_helper.py --device YOUR_DEVICE_ID
```

Use **Drive**, **Routine**, or **GPS** on the phone. If you change the app's bundle identifier, pass the same value with `--bundle-id`.

Routines use New York time and straight-line walking at 1.4 m/s. Edit the sample stops before starting. The Mac must stay awake and reachable for scheduled updates. Holding a coordinate still uses iOS simulation; persistence after disconnecting or quitting Xcode varies.

To preview the sample week:

```sh
python3 helper/campus.py --days 7
```
