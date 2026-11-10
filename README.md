# DB Client

One desktop app for your SQL and NoSQL databases. Query, browse and edit
PostgreSQL, MySQL, MariaDB, ClickHouse, MongoDB and Redis from one fast,
native app, with no account, no cloud and no server in between.

**Website and downloads: <https://dbclient.is-my.app>**

> Preview release. The builds are not yet signed, so Windows and macOS warn
> you the first time you open the app (see [Install](#install)).

## Features

- **SQL editor with autocomplete.** Suggests tables, columns, schemas and
  keywords from your live schema, resolves aliases, and quotes names
  correctly for each database. Ctrl+N (Cmd+N) opens a new editor.
- **Database navigator.** Schemas, tables, views, functions, sequences and
  more, in a tree grouped like DBeaver.
- **Edit data in the grid.** Change cells, add and delete rows, review the
  changes, then save them in one transaction or revert.
- **Table inspector.** Data preview with an adjustable row limit (20 by
  default), columns, constraints, indexes, triggers and DDL.
- **Schema editing.** Dialogs for columns, constraints, indexes and triggers
  that show the SQL before it runs (PostgreSQL).
- **Export.** Results as CSV, TSV, JSON, Markdown or SQL INSERT statements.
- **MongoDB.** A Compass-style document view with an expandable JSON tree;
  edit documents in mongosh syntax and only the changed fields are saved.
- **Redis.** Key browser for strings, hashes, lists, sets, sorted sets and
  streams, plus a command console.
- **Private by design.** The app connects straight to your database.
  Passwords are kept in the system keychain (Keychain, Windows Credential
  Locker, libsecret).
- **Themes.** VS Code Dark, GitHub Dark, Dracula and VS Code Light.

## Supported databases

| Database | Support |
|---|---|
| PostgreSQL | Full, including schema editing |
| MySQL, MariaDB | Query, browse, edit rows |
| ClickHouse | Over HTTP(S), with query cancel |
| MongoDB | Including Atlas (`mongodb+srv://`) |
| Redis | Standalone servers, with TLS |

All drivers are built in. You can paste a connection URL (for example
`postgres://user@host:5432/db`) to fill in the connection form.

## Install

Download the file for your system from the
[latest release](https://github.com/kamaludin68/db-client-releases/releases/latest).
### Windows 10 / 11 (64-bit)

1. Download `db-client-windows-x64-setup.exe` and run it. It installs for
   your account only (no administrator rights needed) and adds DB Client to
   the Start menu.
2. If SmartScreen says it protected your PC, click **More info**, then
   **Run anyway**.

Uninstall it from **Settings → Apps**. For a portable copy instead, extract
`db-client-windows-x64.zip` anywhere and run `DB Client\db_client.exe`.

To build the installer locally (needs [Inno Setup 6](https://jrsoftware.org/isinfo.php)):

```sh
cd app
flutter build windows --release
iscc /DAppVersion=0.1.0 windows\installer\db-client.iss   # -> build\installer\
```

### macOS 12 or later (Apple silicon and Intel)

1. Download `db-client-macos.zip`, unpack it and drag **DB Client** into
   **Applications**.
2. The app isn't notarized yet, so clear the download block once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/DB Client.app"
   ```

   Or open it once, then click **Open Anyway** in
   **System Settings → Privacy & Security**.

### Linux (x64)

```sh
# Libraries the app uses (most desktops already have them)
sudo apt install libgtk-3-0 libsecret-1-0 libegl1 libgles2   # Debian / Ubuntu
sudo dnf install gtk3 libsecret libglvnd-egl libglvnd-gles  # Fedora

curl -LO https://github.com/kamaludin68/db-client-releases/releases/latest/download/db-client-linux-x64.tar.gz
tar -xzf db-client-linux-x64.tar.gz -C ~/.local/share
~/.local/share/db-client/db_client
```

Saved passwords use your desktop's keyring (GNOME Keyring or KWallet).

### Android 7.0 or later

Download `db-client-android.apk` on the phone, open it and allow installing
from that source when asked. Release APKs are signed with the key named in
`app/android/key.properties` (not committed); keep that key, since updates
must be signed with the same one.

## Build from source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or
later and the desktop toolchain for your system.

```sh
git clone https://github.com/kamaludin68/db-client.git
cd db-client/app
flutter pub get
flutter run -d windows   # or macos, linux
```

See [`app/README.md`](app/README.md) for tests and platform notes, and
[`TECH_SPEC.md`](TECH_SPEC.md) for the design.

## Releases

This repository is private. Builds and the website are published from the
public [db-client-releases](https://github.com/kamaludin68/db-client-releases)
repo.

- **CI** (`.github/workflows/ci.yml`): analyzer and tests on every push to
  `main` and every pull request.
- **Release** (`.github/workflows/release.yml`): builds Windows (installer
  and zip), macOS, Linux and Android, then publishes them as a release of
  db-client-releases. Set `version:` in `app/pubspec.yaml`, commit, and push
  a matching tag:

  ```sh
  git tag v0.2.0
  git push origin v0.2.0
  ```

  Actions → Release → **Run workflow** builds everything without
  publishing (the files are kept as the run's artifacts). The secrets it
  needs are listed at the top of the workflow.

Without GitHub Actions, `scripts/build-release.ps1` builds Windows, Linux
and Android locally into `binary/`.

The website is `index.html` in db-client-releases, served by GitHub Pages
from its `main` branch.
