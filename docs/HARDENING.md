# Cadence: verification and hardening pass (November 2026)

This pass checked the intelligence features after they were built. It covers the real wiring, persistence, missing and stale data, duplicates and contradictions, silent failures, and test data that could pass for real data. Every run uses the simulator. No physical device was used.

## Issues found

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | High | `Day.at` added absolute minutes to midnight. On the days the clocks change (29 Mar and 25 Oct in Lisbon), every scheduled time was an hour off: notifications, plan blocks, leave-by, wind-down. | Times are now built from the wall clock (`bySettingHour`), so 8:00 stays 8:00. DST tests added. |
| 2 | High | Notification learning only counted a notification as ignored when iOS reported a dismissal. iOS only reports that when you clear the notification yourself in Notification Center, so a banner you ignore never counts. | On each app launch, notifications still unanswered after 2 hours count as ignored and are cleared (`collectIgnored`). Explicit dismissals still count once. |
| 3 | High | Calibration could compare a prediction with an outcome it had already seen. Opening Today in the evening, after rating energy, recorded a "morning" prediction. Opening a finished workout recorded a training prediction. | The morning prediction is only recorded before 14:00, and only before the day is rated or closed. The training prediction is only recorded for today's unfinished session with no feel answer. Energy pairs need the prediction to be written before the day closed. |
| 4 | Medium | After a day or more without a sync, nothing was said unless it was morning and sleep was missing. Dismissing it could also silence it. | A sync of 24 h or older shows at any hour ("hasn't synced for 3 days") and dismissals can't silence it. |
| 5 | Medium | "Not useful" and acting on a recommendation left the card in place until the underlying condition changed. | A recommendation answered today leaves the card straight away. Must-dos are the exception, and they leave when done. |
| 6 | Medium | Dismissals could silence the light-day offer even when two or more illness signals were present. | The light-day offer is exempt from dismissals when there are 2 or more illness signals. |
| 7 | Medium | Contradictions: on a minimum viable day, "protect your focus block", "place a deep-work block" and "train, and let the warm-up decide" could still appear. | A minimum viable day drops focus, deadline and trainfeel. Offering a light day drops deadline pressure. |
| 8 | Medium | Quick capture had several parsing problems:<br>• "1.234,56 €" was read as 1.23.<br>• "3 bananas" logged one banana.<br>• "2 eggs" logged the "Scrambled eggs" dish.<br>• Confirm with no recognised foods said "Logged 0 foods".<br>• "Lembra-me de ligar à mãe amanhã às 18h" kept "amanhã às 18h" in the title.<br>• A "reminder" without a time silently became a task with no notification.<br>• There was no undo. | • Thousands and decimal separators are parsed in both styles.<br>• Counts repeat the single item, up to 5.<br>• Confirm is disabled when nothing would save, and partly unrecognised input says what won't be saved.<br>• Portuguese day and time words are removed without regard to accents.<br>• A reminder without a time is shown as "Task for …: no time given, so no notification".<br>• There is an Undo after every capture. |
| 9 | Medium | Smoothing (75 % today, 25 % yesterday) is fine for one night, but readiness never mentioned a week-long HRV slide. | Readiness adds a note when the median HRV over 7 days falls more than one spread below the 28-day baseline (`Engine.sustainedDecline`). |
| 10 | Low | Touch targets under 44 pt: "Not useful", the ring toggle (30×28), the energy bolts (18 pt images with tap gestures, which VoiceOver couldn't reach), "Turn off" and the workout play button (36 pt). The "+" capture button had no label. | All are now at least 44 pt. The energy bolts are buttons with "Energy n of 5" labels and a selected state. Capture and ring toggle have labels. |

### Checked and found sound

- Baselines use the 28 days before the day being judged and never include that day or any later one.
- Sleep debt is shown as "(an estimate)" and is capped: 120 min per night, 600 min in total.
- Calibration matches energy predictions by date and training predictions by session id. It needs 10 pairs before saying anything.
- Must-dos are never suppressed.
- Recommendations are capped at three, with no duplicate kinds (now covered by a test).

### Notification dismissal: what iOS actually reports

`UNNotificationDismissActionIdentifier` is delivered only when the category has `.customDismissAction` and the user explicitly clears the notification. That means swiping it away in Notification Center or tapping Clear. Banners that time out, lock-screen notifications that are never touched, and clearing everything with "Clear All" in a group are not reliably reported. The supported signal is now `getDeliveredNotifications`: anything still delivered after 2 hours was not acted on.

One side effect: if you read a notification and then act inside the app instead of tapping it, it can still count as ignored. Learning only lowers priority after 6 or more answers, and must-dos, medicines and leave-by are never affected.

## Test infrastructure

**Test mode.** It's set by `CADENCE_UITEST=<scenario>`, which only the UI test runner sets. In test mode the app:

- uses its own data file (`tmp/cadence-uitest.json`); the real `Documents/cadence.json` is never opened
- makes no network calls: sync, health, Google, weather, exercise catalogue and Open Food Facts are all off
- asks for no permissions
- doesn't run the plan seeding or the evening and anchor migrations
- shows Lottie animations as still frames

`CADENCE_UITEST_MINUTE` fixes the time of day for the rules, and `CADENCE_UITEST_RESET=1` starts from a fresh file.

**Scenarios.** Each one loads 28 days of history, then today's situation:

| Scenario | Today |
|---|---|
| `normal` | Ordinary day |
| `poorSleep` | 5 h of sleep and a deep-work block |
| `lowReadiness` | HRV 40, resting HR 63 |
| `missingToday` | No record for today, last sync 10 h ago |
| `stale` | Last sync 74 h ago, two days of history missing |
| `workload` | 8 h of calendar events |
| `minimumDay` | Minimum viable day already on |
| `calibration` | 14 matched prediction and outcome pairs |
| `empty` | Set up, but no band data and nothing learned |

**Workflow** (`.github/workflows/ios.yml`). It runs on pull requests, on pushes to main, and manually. The `simulator-tests` job:

1. picks the newest stable Xcode
2. picks an iPhone simulator for that SDK: a Pro, plus the smallest phone for screenshots
3. runs build-for-testing, then the unit tests and UI tests separately, each with its own `.xcresult`
4. exports screenshots and summaries with `xcresulttool`
5. collects the simulator log and any crash reports
6. uploads it all as the `simulator-test-results` artifact even on failure
7. fails the job when any test fails

The `ipa` job builds the unsigned IPA (`Cadence-ipa`).

## Tests added

- **Unit tests** in `HardeningTests.swift`:
  - DST and date boundaries
  - no sync for 1, 3 and 7 days, at three times of day
  - dismissals that must not silence important advice
  - conflicts on a minimum viable day
  - no duplicate kinds
  - the sleep-debt wording
  - sustained decline
  - minimum-day scoring
  - notification selection (budget, priority, horizon, 64-request limit)
  - capture parsing (separators, Portuguese, counts, unknown and partly known foods, ambiguous text, repeatability)
  - decoding of old and partial saved data
- **UI tests** in `CadenceUITests.swift`:
  - launch and Today
  - ring expansion
  - a recommendation's action turning on the minimum viable day, and turning it off
  - the minimum-day scenario
  - dismiss hiding a recommendation
  - stale data and missing-today data
  - high workload and empty history
  - quick capture in English (spending, confirm, undo) and Portuguese (reminder, cancel)
  - unknown food disabling Confirm
  - the calibration page
  - workout feel and finish
  - daily energy and closing the day surviving a relaunch
  - the minimum viable day surviving a relaunch

Results from [run 41313820684](https://github.com/jjguve5/cadence/actions/runs/41313820684), on Xcode with the iOS 26.2 simulator:

- Unit tests: 72 of 72 passed on the iPhone 17 Pro.
- UI tests: 16 of 16 passed on the iPhone 17 Pro.
- Small-screen screenshot tests: 2 of 2 passed on the iPhone 16e.

The first run, [41310631271](https://github.com/jjguve5/cadence/actions/runs/41310631271), had 2 UI failures. The capture confirmation exposed its icon's accessibility label ("Selected") instead of its text, so VoiceOver read the wrong thing too. That is fixed.

## Still needs a physical device

- Notifications: delivery, the Done, In 30 min and Skip actions, explicit-dismiss callbacks, and the 2-hour ignored check after real use.
- Live Activities and the Dynamic Island: the workout rest timer on the lock screen, Pip's nudges, and the intent buttons.
- Background refresh (`BGAppRefreshTask`). The simulator doesn't schedule it realistically.
- The real Fitbit Air data path through the server: sync timing, `fitbit://` opening the Fitbit app, battery.
- Location and weather, the camera barcode and receipt scanner, and haptics.
- Fonts, layout and Dynamic Type on your actual phone, and Lottie animation performance.
- Crossing a DST change or a time zone with the app running. The test checks the arithmetic, not a live clock change.

## Remaining limitations

- The 2-hour ignored rule is a heuristic, as described above.
- The day calendar takes the time zone when the app starts. After travelling, relaunch the app so "today" follows the new zone.
- UI tests use the real date, so weekday-dependent content (which template is today's) changes from day to day. The scenario's own "Test session" is always on today's weekday.
- The PHP server (sync, health, calendar) isn't exercised in CI. Its behaviour was verified manually earlier.
- Recommendation conflicts are resolved by fixed rules, not by weighing them.

## Manual checklist (on the phone)

1. Open Today in the morning:
   - readiness shows a confidence chip and, if data is late, the freshness note
   - at most 3 recommendations
2. Tap **Not useful** on one: it disappears at once and doesn't come back today.
3. Switch on a minimum viable day from the card:
   - the banner appears
   - focus and training advice go
   - routines show "optional today"
4. Turn it off from the banner.
5. Quick capture "+":
   - "Gastei 12,50 € no Continente": Confirm, then Undo, and nothing remains in Money
   - "Ate 2 eggs and a banana": logs 3 foods
   - "Lembra-me de ligar à mãe amanhã às 18h": a reminder tomorrow at 18:00 with a clean title, and the notification arrives
   - "Ate something weird": Confirm is greyed out
   - type something, then Close: nothing is saved
6. Leave the band unsynced for a day: Today says how many days and offers Open Fitbit.
7. Start a workout:
   - rest timer on the lock screen and Dynamic Island
   - pick a feel and finish
   - the session is in Progress
8. Close the day after 19:00 with energy, then force-quit and reopen: still closed.
9. Leave a reminder notification untouched for more than 2 h, then open the app: You › Growth › What Cadence has learned › Notifications shows it as not answered.
10. After 10 or more closed days with energy, the calibration card shows pairs and a verdict.
