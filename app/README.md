# DB Client (Flutter)

Cross-platform database client. See `../TECH_SPEC.md` for the plan.

## Run

```sh
flutter pub get
flutter run -d windows        # or android, macos, linux, ios
```

After changing `lib/data/app_database.dart`, regenerate drift code:

```sh
dart run build_runner build
```

Windows builds need Visual Studio Build Tools with the C++ workload **and**
the ATL component (used by `flutter_secure_storage`), plus Developer Mode on.

## Test

```sh
flutter test
```

Integration tests run read-only queries against a real PostgreSQL server and
are skipped unless `PG_TEST_HOST` is set:

```sh
PG_TEST_HOST=... PG_TEST_DB=... PG_TEST_USER=... PG_TEST_PASSWORD=... \
PG_TEST_TLS=disable PG_TEST_SCHEMA=public \
flutter test test/integration
```
