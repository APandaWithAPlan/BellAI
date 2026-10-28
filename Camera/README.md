# BellAi Home Camera

## Overview

**BellAi Home Camera** lets you watch your home through a live camera feed while you're away and play back clips of anything that moved. A USB webcam on the Raspberry Pi streams through go2rtc, a motion detection service records a short MP4 clip whenever something moves, and both are reachable over HTTPS only from devices on the team's Tailscale network. The camera restarts on its own after a reboot or when it's unplugged and plugged back in.

## Getting Started

### Prerequisites

* Hardware: Raspberry Pi 4 with a USB webcam (tested with a Razer Kiyo). The 5.1V / 3A power supply.
* Operating System: Ubuntu 26.04 on the Pi. The setup commands use `apt`, `systemd` and `ufw`.
* Software: `ffmpeg`, `v4l-utils`, `curl`, `python3-opencv` and `python3-numpy` from `apt`, plus go2rtc `1.9` or newer (`go2rtc_linux_arm64` from the go2rtc GitHub releases) which are downloaded to `/usr/local/bin/go2rtc`.
* Network: The Pi and every viewing device must be on the team's Tailscale network. The tailnet policy must allow your account to reach the Pi on `tcp:22` (SSH), `tcp:443` (HTTPS) and `tcp:8555` / `udp:8555` (WebRTC). MagicDNS and HTTPS Certificates must be turned on in the Tailscale admin console under **DNS**.
* Firewall: `ufw` on the Pi allows ports `22`, `443` and `8555` on `tailscale0` only, plus `41641/udp` for direct Tailscale connections.
* Files on the Pi:
  * `/etc/go2rtc/go2rtc.yaml`: camera and stream configuration.
  * `/etc/udev/rules.d/99-homecam.rules`: gives the camera the fixed name `/dev/homecam` and restarts go2rtc when it's plugged in.
  * `/etc/systemd/system/go2rtc.service`: starts go2rtc on boot.
  * `/usr/local/bin/homecam-watchdog.sh`, with `homecam-watchdog.service` and `.timer`: restarts go2rtc if it stops responding.
  * `/usr/local/bin/homecam-motion.py`, with `homecam-motion.service`: motion detection and recording. Settings are in `/etc/systemd/system/homecam-motion.service.d/limits.conf`.

### How to Enable / Access

1. Connect to the Pi with `ssh bella@100.85.250.95`, or use a keyboard and screen on the Pi.
2. Start everything and set it to run on boot with `sudo systemctl enable --now go2rtc homecam-watchdog.timer homecam-motion`.
3. Share the camera over HTTPS with `sudo tailscale serve --bg http://127.0.0.1:1984`, then share the recordings with `sudo tailscale serve --bg --set-path /recordings /var/lib/homecam/recordings`. Run these one at a time. They stay on after a reboot.
4. Check the setup with `tailscale serve status`. It should show `https://csc5323pi.tail0829d3.ts.net (tailnet only)` with `/` and `/recordings/` listed under it.
5. With Tailscale on, open https://csc5323pi.tail0829d3.ts.net/api/stream.mjpeg?src=home_cam in a browser to see the live view.

## How to Use It

1. **Watch live:** Open `/api/stream.mjpeg?src=home_cam` for the lowest delay, or `/stream.html?src=home_cam_h264&mode=webrtc` for a player that uses less data on cellular. Use `/api/frame.jpeg?src=home_cam` for a single snapshot. All paths are relative to `https://csc5323pi.tail0829d3.ts.net`.
2. **Browse motion events:** Open `/recordings/events.json` to see every event, newest first, with its start time, length, thumbnail and video path. Add a `video` path to `/recordings/` to play a clip, for example `/recordings/2026-10-28/20261028-124344.mp4`.
3. **Check the logs:** Run `sudo journalctl -u homecam-motion -f` to watch motion events as they happen, and `journalctl -u go2rtc -n 30 --no-pager` for camera errors. Run `sudo du -sh /var/lib/homecam/recordings` to see how much space recordings use.
4. **Tune motion detection:** Edit `/etc/systemd/system/homecam-motion.service.d/limits.conf`, then run `sudo systemctl daemon-reload && sudo systemctl restart homecam-motion`. Lower `MOTION_PCT` (default `2`) if movement is missed, or raise it if lighting changes cause false events. `PRE_ROLL_S` and `POST_ROLL_S` set how many seconds are kept before and after motion. `RETENTION_DAYS` (default `3`) and `MAX_STORAGE_GB` (default `5`) control when old clips are deleted.
5. **Test the auto-restart:** Run `sudo reboot` and check that the stream comes back without doing anything. Unplug the camera and plug it back in, then check `ls -l /dev/homecam` and reload the stream. Run `sudo pkill go2rtc` and check that `systemctl is-active go2rtc` says `active` again after a few seconds.

## Important Links

All camera and recording links only work on a device with Tailscale connected.

### Live Camera

* [Live view (MJPEG)](https://csc5323pi.tail0829d3.ts.net/api/stream.mjpeg?src=home_cam): Main live feed with the lowest delay.
* [Live view (WebRTC)](https://csc5323pi.tail0829d3.ts.net/stream.html?src=home_cam_h264&mode=webrtc): Player that uses less data, good on cellular.
* [Snapshot](https://csc5323pi.tail0829d3.ts.net/api/frame.jpeg?src=home_cam): One current photo from the camera.
* [go2rtc dashboard](https://csc5323pi.tail0829d3.ts.net/): Stream list, viewer count, config and logs.
* [Camera status](https://csc5323pi.tail0829d3.ts.net/api/streams): JSON check that the camera is reachable.

### Motion Recordings

* [Motion events](https://csc5323pi.tail0829d3.ts.net/recordings/events.json): Every event, newest first, with video and thumbnail paths.
* [Recordings folder](https://csc5323pi.tail0829d3.ts.net/recordings/): Browse clips and thumbnails by date.

### Admin and Setup

* [Tailscale admin console](https://login.tailscale.com/admin): Starting point for tailnet settings.
* [Machines](https://login.tailscale.com/admin/machines): The Pi's tag, key expiry and which devices are online.
* [Access controls](https://login.tailscale.com/admin/acls): Port rules for `22`, `443` and `8555`.
* [DNS](https://login.tailscale.com/admin/dns): MagicDNS and HTTPS Certificates.
* [go2rtc releases](https://github.com/AlexxIT/go2rtc/releases): Downloads for updating go2rtc.
#

> **💡Tip 1:** go2rtc only turns the camera on while something is watching, so the camera's light being off just means no one is viewing. The motion service is always watching, though, so its light stays on while `homecam-motion` is running. If the Pi drops off the network while the camera is streaming, check `dmesg | grep -i voltage` for under-voltage and switch to the official power supply. 

> **💡Tip 2:** If SSH or the stream times out, run `tailscale status` on both devices and check the tailnet policy allows your account on the needed ports. If `tailscale serve` says HTTPS is not enabled, turn on HTTPS Certificates in the Tailscale admin console. If the stream won't start, check `journalctl -u go2rtc`. A missing `/dev/homecam` means the Pi doesn't see the camera, so try another USB port and check with `v4l2-ctl --list-devices`.
