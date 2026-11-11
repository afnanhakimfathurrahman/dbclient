# DB Client — Technical Specification & Roadmap

**Working name**: DB Client (final name TBD — avoid "DBeaver", a trademark of DBeaver Corp)
**Version**: 0.1.0 (pre-release, Flutter rewrite)
**Platforms**: Windows, macOS, Linux, Android, iOS
**Stack**: Flutter (Dart) — single codebase, no backend server
**Repository**: [github.com/afnanhakimfathurrahman/dbclient](https://github.com/afnanhakimfathurrahman/dbclient)
**Website**: [`dbclient.is-my.app`](https://dbclient.is-my.app) — landing & download page

---

## 1. Product Overview

A cross-platform database client (in the spirit of DBeaver, TablePlus, DataGrip) that connects **directly** to real databases from the user's device. There is no hosted backend: all connections, queries, and credentials stay on the device.

### Goals
- Real TCP connections to PostgreSQL, MySQL, SQLite, ClickHouse, and MongoDB.
- One codebase for desktop and mobile, with layouts adapted to each form factor.
- Fast with large result sets (virtualized grid, streamed results).
- Secure by default: credentials in the OS secure store, TLS and SSH tunneling built in.

### Non-goals (for now)
- A hosted/web version that connects to remote databases (browsers cannot open TCP sockets).
- Team features (shared connections, cloud sync, user accounts).
- Running JDBC drivers. All drivers are native Dart (or Rust via FFI where needed).

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Flutter UI (Dart)                        │
│  Navigator tree · SQL editor · Results grid · Inspector      │
│  Responsive shell: 3-pane (desktop/tablet) ↔ stacked (phone) │
├──────────────────────────────────────────────────────────────┤
│               State layer (Riverpod providers)               │
│  Connections · Sessions · Tabs · Query history · Settings    │
├──────────────────────────────────────────────────────────────┤
│                  Driver layer (DatabaseDriver)               │
│  PostgresDriver · MySqlDriver · SqliteDriver                 │
│  ClickHouseDriver (HTTP) · MongoDriver                       │
├───────────────────────────┬──────────────────────────────────┤
│  Transport: TCP / TLS     │  SSH tunnel (dartssh2)           │
├───────────────────────────┴──────────────────────────────────┤
│  Local storage: drift (SQLite) · flutter_secure_storage      │
└──────────────────────────────────────────────────────────────┘
                              │ real network
                              ▼
                   User's database servers
```

### Driver abstraction

Every engine implements one interface so the UI stays engine-agnostic:

```dart
abstract class DatabaseDriver {
  DriverCapabilities get capabilities; // sql vs document, schemas, explain, transactions…

  Future<void> connect(ConnectionConfig config);
  Future<void> close();
  Future<Duration> ping();

  Future<List<SchemaNode>> listSchemas();
  Future<List<ObjectNode>> listObjects(String schema); // tables, views, collections
  Future<ObjectDetails> describe(ObjectRef ref);        // columns, indexes, constraints, partitions
  Future<String> ddl(ObjectRef ref);

  Stream<ResultBatch> execute(String query, {int batchSize = 500});
  Future<void> cancel();

  Future<void> begin();
  Future<void> commit();
  Future<void> rollback();
}
```

- Results are **streamed in batches** so the grid renders the first rows immediately and memory stays bounded.
- Heavy work (large result decoding, export) runs in a background isolate (`Isolate.run`) to keep the UI at 60 fps.
- A capability flag set lets the UI hide features an engine doesn't support (e.g. no `EXPLAIN` in MongoDB).

---

## 3. Tech Stack

| Concern | Package | Notes |
|---|---|---|
| Framework | Flutter (stable) | Dart 3.x |
| State management | `flutter_riverpod` | |
| Routing | `go_router` | |
| Local app database | `drift` + `sqlite3_flutter_libs` | Connections (no secrets), history, saved scripts, settings |
| Secrets | `flutter_secure_storage` | Keychain (iOS/macOS), Keystore (Android), Credential Locker (Windows), libsecret (Linux) |
| SQL editor | `re_editor` | Syntax highlighting, large files, custom autocomplete |
| Results grid | `two_dimensional_scrollables` (or `trina_grid`) | Virtualized rows and columns |
| SSH tunnels | `dartssh2` | Password and private key auth |
| HTTP | `dio` | ClickHouse HTTP interface |
| File pick/save | `file_selector` | Import, export, open SQLite files |
| Window management (desktop) | `window_manager` | Remember size and position |

### Database drivers

| Engine | Package | Maturity | Notes |
|---|---|---|---|
| PostgreSQL | `postgres` (v3) | Solid | TLS, extended protocol, streaming |
| SQLite | `sqlite3` | Solid | Open local `.db`/`.sqlite` files |
| MySQL / MariaDB | `mysql_client` | Good | |
| ClickHouse | HTTP interface via `dio` | Good | `FORMAT JSONEachRow` for streaming |
| MongoDB | `mongo_dart` | Fair | Community-maintained; may lag on newer server features |

**Fallback**: if a Dart driver proves too limited (most likely MongoDB), wrap the Rust driver through `flutter_rust_bridge` behind the same `DatabaseDriver` interface. The UI does not change.

---

## 4. Feature Scope

### MVP (v0.1)
- **Connections**: create, edit, delete, test. Host/port/user/password/database, TLS mode, color tag.
- **Navigator tree**: connection → schemas → tables/views → columns, with a filter box.
- **SQL editor**: multiple tabs, syntax highlighting, run statement under cursor (`Ctrl/Cmd+Enter`), run whole script, cancel a running query.
- **Results grid**: virtualized, sortable, column resize, copy cells/rows, NULL display, value viewer for JSON/long text.
- **Query history**: per connection, with duration and row count, click to re-open.
- **Engine**: PostgreSQL only.
- **Platform**: Windows desktop.

### v0.2
- Engines: SQLite, MySQL.
- Table inspector: columns, indexes, constraints, DDL.
- Export results: CSV, JSON, SQL INSERT, Markdown.
- SSH tunneling.
- Android build with a phone layout.

### v0.3
- Engines: ClickHouse, MongoDB (document view + JSON editor).
- Schema-aware autocomplete (tables, columns, aliases).
- Inline editing in the grid with staged changes: modified/inserted/deleted rows highlighted, **Commit (N)** / **Rollback** bar.
- `EXPLAIN` plan view (PostgreSQL, MySQL, ClickHouse).
- macOS, Linux, iOS builds via CI.

### Later
- ER diagram (interactive, export PNG/SVG).
- Visual table designer generating `ALTER` scripts.
- CSV/JSON import wizard with column mapping.
- Partitions view, binary/BLOB viewer.
- Optional encrypted export/import of connection list for moving between devices.

---

## 5. UI & Responsive Layout

| Width | Layout |
|---|---|
| ≥ 1000 px (desktop, large tablet) | Three panes: navigator · editor/inspector tabs · results (resizable splitters) |
| 600–999 px (small tablet, narrow window) | Collapsible navigator drawer, editor and results stacked |
| < 600 px (phone) | Bottom navigation: Connections → Objects → Editor → Results, one screen at a time |

- Dark and light themes, following the system setting by default.
- Keyboard shortcuts on desktop. Touch-friendly targets (≥ 48 px) on mobile.
- Monospace font for editor and grid (bundled, e.g. JetBrains Mono or Fira Code).

---

## 6. Security

- Passwords, SSH keys, and passphrases are stored **only** in `flutter_secure_storage`. The drift database stores a reference key, never the secret.
- TLS modes per connection: disable / require / verify-ca / verify-full. Custom CA certificate upload.
- SSH tunnel host key verification with fingerprint confirmation on first connect.
- Optional "ask for password every time" per connection.
- No telemetry and no network traffic except to the user's own databases.

---

## 7. Platform Notes

| Platform | Notes |
|---|---|
| Windows | Build on this machine. Requires Visual Studio Build Tools (C++ workload). |
| Android | Build on this machine. Requires Android SDK. Needs the `INTERNET` permission. Cleartext traffic only for explicitly non-TLS connections. |
| Linux | Build in CI (Ubuntu runner) or WSL. Needs `libsecret` for secure storage. |
| macOS | Build in CI (macOS runner) or on a Mac. Requires the network client entitlement (`com.apple.security.network.client`). |
| iOS | Build in CI (macOS runner) or on a Mac. Requires an Apple Developer account to distribute. |

**Mobile lifecycle**: iOS and Android suspend backgrounded apps and drop sockets. The connection manager must detect dead connections and reconnect transparently on resume, without losing editor content.

---

## 8. Project Structure

The Flutter app lives in `app/`. The previous React prototype stays at the repo root as a design reference until the Flutter app reaches feature parity, then it is removed.

```
app/
  lib/
    main.dart
    app/                 # app shell, routing, theme
    core/                # shared utilities, errors, logging
    data/                # drift database, repositories, secure storage
    drivers/
      driver.dart        # DatabaseDriver interface, shared models
      postgres/
      mysql/
      sqlite/
      clickhouse/
      mongo/
    features/
      connections/
      navigator/
      editor/
      results/
      inspector/
      history/
      export/
  test/
  integration_test/
```

---

## 9. Testing

- **Unit tests**: SQL statement splitting, export formatters, result model conversions.
- **Driver integration tests**: run against real databases in Docker (`docker compose` with Postgres, MySQL, ClickHouse, MongoDB). Run locally and in CI.
- **Widget tests**: connection form validation, grid rendering, layout breakpoints.
- **Manual checklist** per release on each platform: connect, browse, query, cancel, export, reconnect after suspend (mobile).

---

## 10. Build & Release

- **CI**: GitHub Actions matrix — `windows-latest`, `ubuntu-latest`, `macos-latest`. Runs `flutter analyze`, tests, and builds artifacts.
- **Desktop distribution**: Windows MSIX or installer, macOS DMG (signed + notarized), Linux AppImage or `.deb`.
- **Mobile distribution**: Google Play (AAB), Apple App Store / TestFlight.
- **Website**: `dbclient.is-my.app` on GitHub Pages becomes a static landing page with download links.

---

## 11. Current Status

- The existing React/Vite PWA at the repo root is a **UI prototype only**. It does not connect to any database: queries run against hardcoded sample data, and connection tests and driver downloads are simulated.
- The Flutter app has not been started yet.
- Dev environment (Windows): Flutter SDK installed; Visual Studio Build Tools and Android Studio being installed.

---

## 12. Open Decisions

- Final product name.
- Grid package: `two_dimensional_scrollables` (more control, more work) vs `trina_grid` (more built-in features).
- MongoDB: start with `mongo_dart`, or go straight to a Rust driver via `flutter_rust_bridge`.
- Licensing: open source (which license) or closed.
