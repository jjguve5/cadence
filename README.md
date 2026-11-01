# Cadence

A personal health and productivity coach for iPhone, built around a Fitbit Air and Pip, its companion.

- `ios/`: the SwiftUI app (XcodeGen). GitHub Actions builds an unsigned IPA; install it with Sideloadly.
- `server/`: the PHP backend. It syncs the app's records and reads the Google Health API.
  Copy `config.example.php` to `config.php`; personal data stays in `server/data/`, never in this repo.
- `deploy-server.sh`: uploads `server/` over FTPS, with credentials from a local file.

Exercise data by RepDB (repdb.co). Body map based on GymMane by InlitX (GPL-3.0).
