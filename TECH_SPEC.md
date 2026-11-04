# DBeaver Web — Technical Specification, Feature Audit & Roadmap

**Application Name**: DBeaver Web - Multi-Database Client & SQL IDE  
**Version**: 1.0.0 (Production Release)  
**Target Environment**: Cross-Platform Progressive Web App (PWA) & Web Application  
**Custom Subdomain**: [`dbclient.is-my.app`](https://dbclient.is-my.app)  
**GitHub Repository**: [github.com/kamaludin68/db-client](https://github.com/kamaludin68/db-client)

---

## 1. Architecture Overview

DBeaver Web is a desktop-grade, client-side database management platform inspired by DBeaver, TablePlus, and DataGrip. It is architected as an offline-first Progressive Web Application (PWA) running on modern Web Standards, featuring a dark-mode user interface, multi-database engine abstraction, a multi-tab workspace, and client-side data management.

### Tech Stack
- **Core Framework**: React 19 (`react`, `react-dom`)
- **Language**: TypeScript 5.8+ (Strict Type Checking, No Emit)
- **Build & Dev Tooling**: Vite 8 (`@vitejs/plugin-react`, `tsx`, `esbuild`)
- **Styling & Theme**: Tailwind CSS v4 (`@tailwindcss/vite`), custom dark theme palette, monospace typography (`Fira Code`, `Inter`)
- **PWA & Offline Service Worker**: `vite-plugin-pwa` with Workbox runtime precaching and Web App Manifest
- **Icons & UI Primitives**: `lucide-react`, custom SVG/Canvas-rendered brand icon assets
- **Data & Persistence**: `LocalStorage` + `IndexedDB` abstraction via `StorageService`

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DBeaver Web UI                                  │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ Top Bar: Brand, Connections,  │ Global Modals:                              │
│ Drivers, History, PWA Install │ Driver Manager, Connection Wizard, Export   │
├───────────────────────────────┼─────────────────────────────────────────────┤
│ Left Pane (Database Tree):    │ Right Pane (Multi-Tab Workspace):           │
│ • Connections                 │ • SQL & NoSQL Editor Scripts                │
│ • Schemas & Databases         │ • 7-Tab Table / Object Inspector            │
│ • Tables & Collections        │ • Visual ER Diagram                         │
│ • Columns, Indexes, Partitions│ • Execution Plan Visualizer                 │
├───────────────────────────────┴─────────────────────────────────────────────┤
│ Services Layer:                                                             │
│ • QueryEngine (SQL/BSON Parser, Execution Simulator, Cost Optimizer)        │
│ • StorageService (Persistent State, Catalogs, Drivers, History, Tabs)       │
│ • PWA Engine (Workbox Service Worker, Offline Caching, Install Prompts)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Implemented Features (Working Functionality)

The following capabilities are fully built, tested, and operational in the application:

### A. Core Database Support (Default Capability)
- **PostgreSQL 16**:
  - Multi-schema support (`public`, `analytics`).
  - Heap tables with typed columns, serial sequences, nullability, defaults, and comments.
  - Secondary Indexes: B-Tree, GIN (JSONB attributes), Composite indexes.
  - Partitioned tables: Quarterly range partitioning on `payment_transactions` (`payments_2024_q1` to `q4`).
  - Constraint definitions: `PRIMARY KEY`, `FOREIGN KEY` (with cascade actions), `CHECK` constraints, `UNIQUE` constraints.
- **MongoDB 7.0**:
  - Document collections (`customers`, `events_stream`).
  - BSON / JSON document model, document counts, and nested object inspection.
  - Multi-key and compound indexes, text indexes, 30-day TTL indexes (`createdAt_ttl`).
  - Schema validators (`$jsonSchema`).
- **ClickHouse 24.3**:
  - Columnar analytical tables (`pageviews_mergetree`).
  - `MergeTree()` engine with `toYYYYMM(event_date)` partition key.
  - Column compression codecs: `ZSTD(3)`, `DoubleDelta`.
  - Sorting keys (`ORDER BY`) and Primary keys.

### B. Extensible Driver Manager ("Download Driver First")
- **Pre-installed Core Drivers**: PostgreSQL JDBC, MongoDB Java Driver, ClickHouse Native JDBC.
- **Downloadable Driver Marketplace**:
  - MySQL Connector/J (`mysql`)
  - SQLite JDBC (`sqlite`)
  - Redis RESP3 Client (`redis`)
  - Apache Cassandra CQL (`cassandra`)
  - Snowflake JDBC (`snowflake`)
  - DuckDB In-Memory OLAP (`duckdb`)
  - Oracle JDBC (`oracle`)
  - Microsoft SQL Server (`sqlserver`)
- **Driver Download Flow**: Simulated package download with real-time percentage progress bar, SHA verification, and instant activation.
- **Custom Driver Registration**: Form to register custom JDBC drivers with custom protocol URL templates, driver classes, default ports, and engine categories.

### C. Database Navigator Tree
- DBeaver-style hierarchical explorer:
  - Connection Node (color tag dot, status indicator, latency ping, context menu).
  - Schemas / Databases.
  - Tables & Collections with child folders:
    - **Columns**: icons for Primary Key, Foreign Key, data types.
    - **Indexes**: icons for Unique, BTree, GIN, Compound.
    - **Partitions**: partition expressions and range bounds.
    - **Constraints**: PK, FK, Check, and Unique rules.
- Fast object filter search input that searches tables and columns in real-time.
- Node expansion, collapse all, and quick-open SQL console actions.

### D. Deep Table & Object Inspector (7 Views)
1. **Data Grid**: Tabular spreadsheet view with column type headers, sortable columns, row selection, insert row, delete row, and cell inspector modal (JSON/text formatting).
2. **Columns Tab**: Name, data type, primary/foreign key badges, nullability, default values, compression codecs, and comments.
3. **Indexes Tab**: Name, type (`BTREE`, `GIN`, `COMPOUND`, `ORDER_BY`, `TTL`), uniqueness, indexed columns, and storage size.
4. **Partitions Tab**: Partition names, expressions, value bounds, row counts, and storage footprints.
5. **Constraints Tab**: Primary Keys, Foreign Keys (with referenced tables and cascade actions), Check expressions, and Unique constraints.
6. **DDL / Source Tab**: Dynamically generated, syntax-highlighted `CREATE TABLE` and index creation statements with one-click copy.
7. **ER Diagram Tab**: Interactive schema relationship graph showing active tables, PK/FK connection lines, and cardinality.

### E. Built-in SQL & NoSQL Query Editor
- Multi-tab script management (`Script-1.sql`, `Script-2.sql`, etc.).
- Line numbers with active line indicator.
- Keyboard shortcut: <kbd>Ctrl</kbd> + <kbd>Enter</kbd> / <kbd>Cmd</kbd> + <kbd>Enter</kbd> to execute queries.
- **Explain Plan**: Visual hierarchical query plan tree displaying startup and total costs, execution times, filters, and index scan nodes.
- **SQL Formatter**: Aligns standard SQL keywords (`SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, `ORDER BY`).
- **Query Snippets Library**: Pre-built templates for multi-table JOINs, partition pruning queries, ClickHouse columnar aggregates, and MongoDB `.find()` / `.countDocuments()`.
- **Query Execution History**: Persistent log of past queries with duration in milliseconds, row counts, and one-click re-run.

### F. Data Export Tools
- Multi-format exporter: **CSV**, **JSON**, **SQL INSERTs**, **Markdown tables**, **TSV (Excel)**, and **HTML**.
- Configuration options: custom delimiters (comma, semicolon, tab, pipe), header toggle, string quoting options.
- Direct file download with auto-generated filenames and "Copy to Clipboard" with live 4-row preview.

### G. PWA & Offline Support
- Service worker generated via `vite-plugin-pwa` with precached app shell and offline fallback.
- Standard resolutions: `192x192`, `512x512`, `512x512 maskable`, `apple-touch-icon.png`, and `icon.svg`.
- In-app install button (`PWAInstallButton`) with Chromium beforeinstallprompt handling and iOS Safari installation guidance.
- Offline status indicator banner that alerts the user when network connectivity changes.
- Persistent local storage: custom connections, downloaded drivers, query history, saved scripts, and data modifications remain preserved offline.

---

## 3. What Functions Are NOT Working Yet (Limitations & Simulation)

Because DBeaver Web currently runs 100% inside a standard browser sandbox as a client-side PWA, certain low-level desktop features operate in simulation mode:

### 1. Direct Raw TCP Sockets to Remote Databases
- **Current Behavior**: The connection wizard and query engine execute against rich, client-side database catalogs and in-memory query parsers.
- **Limitation**: Web browsers security sandboxes do NOT permit opening arbitrary raw TCP sockets (e.g. TCP port `5432` for PostgreSQL or `27017` for MongoDB). Direct connection requires either:
  - An HTTP/REST interface (e.g., ClickHouse HTTP API, PostgREST, MongoDB Atlas Data API).
  - A lightweight local or cloud WebSocket Proxy daemon (`dbeaver-web-proxy`).

### 2. Native Java Driver Execution (`.jar` JVM)
- **Current Behavior**: When a user "downloads" a driver (e.g., MySQL, Redis, Snowflake), the application registers the driver metadata, classes, ports, and configuration in persistent storage and unlocks connection creation.
- **Limitation**: The browser cannot execute compiled Java bytecode (`.class`/`.jar` files) natively. True in-browser execution requires compiling database clients to WebAssembly (WASM).

### 3. Visual Table Alter / Schema Migration Tool
- **Current Behavior**: Users can view generated DDL (`CREATE TABLE ...`) and inspect existing constraints and partitions.
- **Limitation**: There is no interactive visual GUI to edit an existing table's schema (e.g. `ALTER TABLE ADD COLUMN`, `DROP CONSTRAINT`) with automatic migration script generation.

### 4. Large Dataset Virtualization (> 100,000 Rows)
- **Current Behavior**: The Data Grid renders up to thousands of records smoothly using standard HTML table markup and pagination.
- **Limitation**: For queries returning 100,000+ rows, the DOM may suffer performance degradation without windowed virtual scrolling (e.g. TanStack Virtual or ag-grid).

### 5. Multi-Statement Transaction Commit/Rollback Bar
- **Current Behavior**: Inserting and deleting rows immediately updates the in-memory catalog.
- **Limitation**: There is no staged "Dirty Rows" buffer with a pending commit bar (like DBeaver's bottom `Save / Revert` transaction buttons) that requires explicit `COMMIT` or `ROLLBACK`.

---

## 4. Prioritized TODO List & Roadmap

### Phase 1: Real In-Browser Database Engines (Immediate Priority)
- [ ] **PGlite Integration (`@electric-sql/pglite`)**:
  - Embed the real PostgreSQL database engine compiled to WebAssembly inside the PWA.
  - Allows users to create real, 100% functional local PostgreSQL databases with real SQL parsing, ACID transactions, and full syntax right inside IndexedDB!
- [ ] **DuckDB-WASM Integration (`@duckdb/duckdb-wasm`)**:
  - Add native client-side analytical querying for Parquet, CSV, and Arrow files with lightning-fast columnar execution in browser workers.
- [ ] **ClickHouse HTTP Interface**:
  - Connect to real ClickHouse clusters using ClickHouse's native HTTP/HTTPS interface (`POST /?query=...`) with CORS headers.
- [ ] **MongoDB Data API / Atlas App Services**:
  - Wire the MongoDB console to real remote MongoDB Atlas clusters using the HTTPS Data API.

### Phase 2: Companion WebSocket Proxy Daemon
- [ ] **Develop `dbeaver-web-proxy`**:
  - A tiny single-binary daemon (in Go or Node.js) that users can run locally (`npx dbeaver-web-proxy`):
  - Bridges browser WebSocket connections directly to raw TCP ports:
    - Postgres: `ws://localhost:8080/pg` -> `tcp://localhost:5432`
    - MySQL: `ws://localhost:8080/mysql` -> `tcp://localhost:3306`
    - Mongo: `ws://localhost:8080/mongo` -> `tcp://localhost:27017`
    - Redis: `ws://localhost:8080/redis` -> `tcp://localhost:6379`
  - Unlocks 100% genuine raw database connections identical to the desktop DBeaver application.

### Phase 3: Advanced SQL Editor & Autocompletion
- [ ] **Monaco Editor / CodeMirror 6 Migration**:
  - Replace current textarea with full Monaco Editor.
  - Schema-aware intelligent autocompletion (IntelliSense) for tables, columns, aliases, and SQL keywords.
  - Multi-cursor editing, bracket matching, and query folding.
- [ ] **Multi-Statement Execution**:
  - Execute statement under cursor (<kbd>Ctrl</kbd> + <kbd>Enter</kbd>) vs execute entire script (<kbd>Alt</kbd> + <kbd>X</kbd>).
  - Display multiple result tabs for scripts containing multiple `SELECT` statements.

### Phase 4: Data Grid Enhancements & Transactions
- [ ] **Virtualized Viewport**:
  - Implement `@tanstack/react-virtual` for handling 1,000,000+ rows with constant 60fps scrolling and negligible memory footprint.
- [ ] **Staged Transaction Management**:
  - Highlight modified, inserted, and deleted cells in yellow/green/red.
  - Show a persistent bottom bar with `Commit (N changes)` and `Rollback` buttons.
- [ ] **Binary / Blob Viewer**:
  - Cell inspector for viewing images, base64 data, hex view, and formatted JSON/XML trees.

### Phase 5: Visual Schema Designer & Import Wizard
- [ ] **Visual Table Designer**:
  - GUI to create and alter tables, add indexes, and define foreign key relationships visually.
- [ ] **Interactive Drag & Drop ERD Canvas**:
  - Upgrade ER Diagram to an interactive canvas (using React Flow or HTML5 Canvas) where tables can be rearranged, linked, and exported as PNG/SVG.
- [ ] **CSV / JSON Data Import Wizard**:
  - Complement the export tools with a multi-step Import Wizard to upload CSV/JSON files into existing database tables with column mapping and type coercion.

---

## 5. Deployment & Domain Verification

| Target | Configuration | Status |
| :--- | :--- | :--- |
| **PWA Service Worker** | `dist/sw.js` via Workbox | Active |
| **Web App Manifest** | `dist/manifest.webmanifest` (`id: '/'`, `display: 'standalone'`) | Active |
| **GitHub Pages Branch** | `gh-pages` | Deployed |
| **Custom Domain CNAME** | `dbclient.is-my.app` -> `kamaludin68.github.io` | Merged via PR #42 |
| **DNS Status** | Registered on `is-my.app` edge | Active |
