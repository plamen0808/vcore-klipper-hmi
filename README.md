# V-Core Klipper HMI

A responsive touchscreen interface for Klipper printers that expose the Moonraker API. The project is a static web app served by the printer's existing Nginx installation.

## Features

- Home page with temperatures, fan state, print progress, and print controls
- XY and Z jogging, homing, Z-tilt, and motion-limit controls
- G-code file browser
- Extruder controls, including guarded extrude/retract actions
- Console and selectable macro pages
- Responsive portrait and landscape layouts, with a fullscreen button

The HMI detects printer objects through Moonraker. Printer features that are not configured are shown as unavailable. Runtime tuning controls send commands to Klipper; they do not edit RatOS or Klipper configuration files.

## Install on RatOS or another Moonraker host

The installer puts the web app in its own directory and adds one standalone Nginx server configuration in `/etc/nginx/conf.d/`. It does not edit RatOS configuration, Moonraker configuration, or the existing Mainsail site file.

### Requirements

- A Klipper printer with Moonraker
- Nginx installed and running
- A Linux account that can read the HMI files (usually `pi` on RatOS)
- Port `8081` available on the printer
- Moonraker listening on `127.0.0.1:7125` (the default used by RatOS)

### Install from a clone

```sh
git clone https://github.com/plamen0808/vcore-klipper-hmi.git
cd vcore-klipper-hmi
sudo bash ./install.sh pi
```

If your Linux account is not `pi`, pass its name instead:

```sh
sudo bash ./install.sh YOUR_LINUX_USER
```

Optional arguments are Linux user, HMI port, Moonraker host, and Moonraker port:

```sh
sudo bash ./install.sh pi 8081 127.0.0.1 7125
```

The installer validates the generated Nginx configuration before reloading Nginx. If it replaces an existing HMI Nginx config, it saves a timestamped backup next to it.

### Open the HMI

Use the printer's IP address and port 8081:

```text
http://PRINTER-IP:8081/
```

For the VKOR printer used during development:

```text
http://192.168.100.120:8081/
```

The standalone Nginx server proxies Moonraker's API and websocket on the same origin, so the URL does not need a `moonraker=` query parameter. The address will work from devices on the same local network. A hostname requires a DNS entry in your router; it is optional.

### Update

```sh
cd REPOSITORY
git pull
sudo bash ./install.sh pi
```

The installer updates the files in `/home/pi/apps/vcore-hmi` (or the selected user's home directory) and reloads Nginx.

### Uninstall

```sh
sudo bash ./uninstall.sh
```

This removes the HMI's standalone Nginx config (or restores a config that existed before installation) and reloads Nginx. It leaves the app files in `~/apps/vcore-hmi` so you can remove or back them up yourself.

## Nginx and Moonraker routing

The standalone listener binds port `8081`. It serves the static HMI files and proxies `/websocket`, `/printer/`, `/api/`, `/access/`, `/machine/`, and `/server/` requests to Moonraker. Mainsail continues to use its existing port-80 server.

If you change the Moonraker host or port, pass those values to `install.sh`. If port 8081 is already in use, choose a free port, for example:

```sh
sudo bash ./install.sh pi 8082 127.0.0.1 7125
```

## Fullscreen and mobile use

The HMI includes a fullscreen button. On Android, browser chrome and system bars are controlled by the browser and Android; for a kiosk-style display, install the app as a web app when your browser permits it or use a kiosk launcher. The manifest is included with the web bundle.

## Network security

This setup is intended for a trusted local network. It does not add authentication to Moonraker or the HMI. Do not expose port `8081` or Moonraker's API directly to the public internet.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
