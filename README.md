# EdgeTX Stick CSV Logger

Lua tool/telemetry script for EdgeTX 2.8+ that records stick/channel movement to CSV for later video overlay work.

## Install

1. Copy `SCRIPTS/TOOLS/stklog.lua` to the radio SD card at `SCRIPTS/TOOLS/stklog.lua`.
2. Optional, for telemetry-screen access: copy `SCRIPTS/TELEMETRY/stklog.lua` to `SCRIPTS/TELEMETRY/stklog.lua`.
3. Make sure the SD card has a `/LOGS/` directory.
4. Open `SYS` -> `TOOLS` and run `stklog`.
5. Configure:
   - `Arm`: arm channel, default `CH5`.
   - `Order`: channel order preset, default `AETR`; available presets are `AETR`, `TAER`, and `RETA`.
     `A` = aileron/roll, `E` = elevator/pitch, `T` = throttle, `R` = rudder/yaw. The letters describe channels 1-4 in order.
   - `StopSec`: how long to keep logging after `Arm` goes low. Default is `60`; use `30` for a shorter grace period.

The first screen is a status screen with `Waiting for arm`, `Recording`, or `Pending stop` and a live two-stick monitor. Press `ENT` or `MENU` to open settings. In settings, press `ENT` to edit the selected item, use next/previous or rotary controls to change values, then press `ENT` again to save. Press `EXIT` to return to the status screen. Settings are stored as `/SCRIPTS/TOOLS/stklog.cfg`.

For continuous telemetry-screen use on radios that support Lua telemetry scripts, assign `stklog` from `SCRIPTS/TELEMETRY` to a model display/telemetry screen. The telemetry wrapper loads the same tool script and calls its `background()` function.

## Behavior

Logging starts when `Arm` is high, currently source value greater than `512`. Logging does not stop immediately when `Arm` goes low. The script enters a pending-stop state and keeps writing to the same CSV until `Arm` has stayed low for `StopSec` continuous seconds.

If the model is rearmed before `StopSec` expires, the same CSV continues. This avoids splitting one flight into multiple files during short disarm/rearm gaps.

The target sample rate is 50 Hz. EdgeTX calls the active tool/telemetry script periodically, so actual cadence depends on radio load.

The web app interpolates between CSV samples during preview and render, so 50 Hz logs still draw smoothly on 60/90 fps video. Captured motion detail is still limited by the logger cadence and by how often EdgeTX schedules the Lua script.

## CSV Format

Files are written as `/LOGS/STICK001.CSV`, `/LOGS/STICK002.CSV`, and so on.

Header:

```csv
kind,t_ms,roll,pitch,thr,yaw,arm
```

Rows:

```csv
start,0,,,,,1
sample,20,0,0,-1000,0,1
stop,91000,,,,,0
```

`t_ms` is relative to the start of the log. Stick values are normalized to `pct10`: approximately `-1000..1000` for `-100.0%..100.0%`. `arm` is `1` when armed and `0` otherwise.

## Development

Run local tests with:

```sh
lua tests/stklog_test.lua
```

## Web App

The browser app lives in `docs/` and is deployed to GitHub Pages from the `main` branch and `/docs` folder. It runs fully in the browser: select a local flight video and a `STICK*.CSV` file, align the stick overlay, then render a combined WebM video.

The published app is available at:

```text
https://lesharodin.github.io/lua-stick-overlay/
```
