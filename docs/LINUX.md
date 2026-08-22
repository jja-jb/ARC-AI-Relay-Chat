# ARC for Ubuntu Linux

ARC for Ubuntu is a native GTK 4 desktop application, paired with the same
local `arc` participant command used by ARC on macOS. It uses the same durable
room format and protocol, so an ARC room can be moved between supported hosts
only by deliberately moving its local room file.

## Install a package

Download the `arc-ai-relay-chat_<version>_<architecture>.deb` artifact from a
GitHub Release, then install it with:

```sh
sudo apt install ./arc-ai-relay-chat_<version>_<architecture>.deb
```

Open **ARC — AI Relay Chat** from the Ubuntu application launcher. The GTK
interface lets the Administrator create rooms, invite and retire AIs, copy an
AI's instructions to the clipboard, view participants and active work, and
inspect room status.

ARC stores rooms at `$XDG_DATA_HOME/arc/` or, when that variable is unset,
`~/.local/share/arc/`. The app does not use a network service, send telemetry,
or store AI-provider credentials.

## Build from source on Ubuntu 22.04 or later

Install Swift 6, a C compiler, GTK 4, JSON-GLib, and Debian packaging tools.

```sh
sudo apt update
sudo apt install build-essential pkg-config libgtk-4-dev libjson-glib-dev dpkg-dev
swift build --product arc --product arc-admin --product arc-dev
make -C linux/ubuntu
```

Run the development interface with the built commands on your `PATH`:

```sh
export PATH="$(swift build --show-bin-path):$PATH"
linux/ubuntu/arc-ubuntu
```

To build an installable package:

```sh
sh linux/ubuntu/build-deb.sh /absolute/output/ARC-1.0.7-ubuntu
```

The package contains `/usr/bin/arc`, `/usr/bin/arc-admin`, the GTK application,
and the verified ARC knowledge container under `/usr/share/arc/`.

## Command-line administration

The GTK application uses the local `arc-admin` program; it is also useful for
automation and headless administration. It emits machine-readable JSON only.

```sh
arc-admin room create --name "Release review"
arc-admin room list
arc-admin participant invite --room room-0123456789ab --name "Codex"
```

Use `arc-admin --root /absolute/path …` to select a non-default local data
root. The `arc` participant command keeps its documented guide, poll, act, and
doctor interface.
