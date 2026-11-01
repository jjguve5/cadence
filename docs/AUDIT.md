# Cadence audit (1 Nov 2026)

## Architecture
- SwiftUI app, one `Store` (MainActor ObservableObject) that keeps everything on the phone first and syncs generic
  JSON records to a PHP server. Typed records through a `Record` protocol; decoding tolerant of new fields.
- Health data comes from the server (`health.php`), which reads the Google Health API: daily values cached per day,
  per-minute heart rate, steps and SpO₂ on request.
- Logic lives in `Store` extensions (Insights, Fuel, Training, Care, Money, Growth…); views read it directly.
- Live Activities for workouts; local notifications rebuilt as a rolling 48-hour queue.

## Strengths
- Offline first, one sync path, no external AI or paid APIs.
- Most rules are already interpretable (readiness parts, progression reasons, growth check).
- Data model is flexible: new features add record types without migrations.

## Problems found
1. **Readiness** uses a 14-day mean and SD (sensitive to one bad night), adds an arbitrary −6 for skin temperature,
   and reacts fully to a single night. It doesn't say how confident it is.
2. **Progression** drops a set when readiness is under 50: readiness alone shouldn't cut training.
3. **Sleep debt** sums 14 nights with no cap: one terrible week makes it huge, and surplus nights repay without limit.
4. **Overclaims**: "aren't getting what they need to grow" (we can't measure growth), "Cadence age" reads like a
   biological age, illness wording sounds like a diagnosis.
5. **No freshness**: the Air syncs late, but recommendations and readiness don't know whether today's data has arrived.
6. **Today is crowded**: brief, weather, readiness, next up, five rings, promises, top 3, close, sync, plus score and level.
7. **No feedback loop**: the app never checks whether its predictions (readiness, energy curve, focus windows) were right.
8. **Notifications** use fixed priorities and a daily count; ignoring a kind of reminder never changes anything.
9. **Hard days** have no mode: missing optional routines on a sick day lowers the score like any other day.
10. **No tests**: every check so far was "it compiles".

## Plan (by benefit and risk)
| # | Change | Benefit | Risk |
|---|---|---|---|
| 1 | Pure `Engine` module: robust baselines, readiness with confidence, conservative sleep debt | Fewer misleading numbers | Low |
| 2 | Data freshness and provenance on readiness and recommendations | Stops stale data posing as today | Low |
| 3 | Daily intelligence: up to 3 recommendations with why, evidence, confidence, action, dismiss | The main value add | Medium |
| 4 | Minimum viable day: offered, never imposed; essentials only; counts as a full day | Kinder on bad days | Low |
| 5 | Science fixes: progression, wording of growth, fitness age, illness | Honesty | Low |
| 6 | Simpler Today: focus card first, three key rings, details on tap | Less attention needed | Medium |
| 7 | Prediction calibration: store predictions first, compare with outcomes, monthly report | The app learns where it's right | Medium |
| 8 | Notification learning from dismissals (never for must-dos, medicines, leave-by) | Fewer useless pings | Low |
| 9 | Quick capture: one line understood, always confirmed | Less friction | Medium |
| 10 | Pip notices effort and stays quiet during focus | Warmer, less repetitive | Low |
| 11 | Unit tests for every pure calculation, run in CI | Safety net | Low |

Later: alternating (ABAB) experiments, longer-term Fitbit trend analysis, undo for more actions.
