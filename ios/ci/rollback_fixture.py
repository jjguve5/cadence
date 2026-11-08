"""A synthetic data file in the format the 2 Nov build writes (no real data): one of everything that matters."""
import json

fixture = {
    "promises": {"P1": {"id": "P1", "title": "Creatina", "icon": "pills.fill", "kind": "mustDo",
                        "schedule": {"rule": "daily", "every": 2, "start": "2026-11-01", "weekdays": [2, 4, 6], "minute": 470},
                        "active": True, "created": 1793524150000}},
    # an answer from before phase 2.2 (no source), one imported from the band and one you gave (phase 2.2)
    "logs": {"P1|2026-11-04": {"promiseId": "P1", "date": "2026-11-04", "status": "done", "at": 1793790000000},
             "P1|2026-11-03": {"promiseId": "P1", "date": "2026-11-03", "status": "done", "at": 1793700000000, "source": "fitbit"},
             "P1|2026-11-02": {"promiseId": "P1", "date": "2026-11-02", "status": "skipped", "at": 1793610000000, "source": "you"},
             # «Não se aplica» from the end-of-day review (phase 2.8): a skip with notApplicable, which older builds read as skipped
             "P1|2026-11-01": {"promiseId": "P1", "date": "2026-11-01", "status": "skipped", "at": 1793520000000, "source": "you", "notApplicable": True}},
    "days": {"2026-11-03": {"date": "2026-11-03", "rating": 4, "note": "Dia bom: ação e ténis", "top3": ["Pernas"], "top3Done": [True],
                            "closedAt": 1793741954837.537, "score": 45, "points": 45, "energy": 4}},
    # The whole profile, as the app writes it (every build saves all its fields): with only a few fields, whether a
    # build happened to save in its 20 s on screen decided whether the later ones looked "different" (phase 2.2 run
    # 42476758508). Values: the fixture's own plus the defaults both the 2 Nov build and the new one fill in.
    "profile": {"name": "", "weightKg": 78, "kcalTarget": 3160, "areasOff": ["money"], "goal": "gain", "stepGoal": 10000,
                "age": 25, "barKg": 20, "healthSource": "fitbit", "heightCm": 178, "male": True, "notificationBudget": 12,
                "plates": [25, 20, 15, 10, 5, 2.5, 1.25], "proteinPerKg": 1.8, "quietEnd": 420, "quietStart": 1410,
                "readinessOffset": 0, "setupDone": False, "sleepNeed": 465, "wakeMinute": 435, "waterGoalMl": 3000,
                "windDownLead": 30},
    "feedback": {"2026-11-02": {"date": "2026-11-02", "score": 52, "felt": -1}},
    "extra": {
        "water": {"W1": {"id": "W1", "date": "2026-11-04", "minute": 891, "ml": 250}},
        "medlog": {"M1|2026-11-04|480": {"medId": "M1", "taken": True, "minute": 480}},
        "gymBag": {"2026-11-02": True},
        # a bought mark as phase 2.2 saves it (id the server takes, object value)
        "bought": {"2026-11-02_whey": {"at": 1793610000000}},
        # every record type phase 2 adds, as the app writes it: older builds keep them untouched (validator C, L1)
        "routinelog": {"R1_2026-11-01": {"id": "R1_2026-11-01", "routineId": "R1", "date": "2026-11-01", "steps": {"s1": 1793600000000}}},
        "careproduct": {"P9": {"id": "P9", "name": "Gel", "size": 200, "unit": "ml", "perUse": 2}},
        "watergoal": {"2026-11-01": {"date": "2026-11-01", "ml": 2800, "at": 1793600000000}},
        "nowDismiss": {"2026-11-01_ev1": {"id": "2026-11-01_ev1", "date": "2026-11-01", "event": "ev1", "action": "snooze", "until": 900, "at": 1793600000000}},
        "trainingTarget": {"next:leg-extension": {"id": "next:leg-extension", "exerciseId": "leg-extension", "weight": 30, "reps": 10,
                                                  "reason": "Fizeste todas as repetições.", "session": "S1", "at": 1793600000000}},
        "leaveItem": {"keys": {"id": "keys", "title": "Chaves e carteira", "when": "always", "at": 1793600000000}},
        "leaveDay": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "seen": ["keys"], "ready": 1793600000000, "at": 1793600000000}},
        "gymBagPacked": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "items": ["towel"], "done": True, "at": 1793600000000}},
        "nightPrep": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "dismissed": True, "at": 1793600000000}},
        "sleepIntent": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "minute": 1400, "at": 1793600000000}},
        "readingPlan": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "minutes": 20, "start": 1340, "until": 1360, "at": 1793600000000}},
        "sleepManual": {"2026-11-01": {"id": "2026-11-01", "date": "2026-11-01", "bed": 1400, "wake": 435, "source": "you", "at": 1793600000000}},
        # a laundry mark undone (D25): a plain value the reminder ignores
        "laundry": {"2026-11-01-gym 30°": False},
        "session": {"S1": {"id": "S1", "date": "2026-11-02", "name": "Pernas", "start": 1793600000000, "end": 1793604000000,
                           "order": [], "sets": [], "notes": []}},
    },
    "health": {"2026-11-07": {"date": "2026-11-07", "steps": 1371, "rhr": 56, "hrv": 113.9,
                              "sleep": {"start": "2026-11-07T00:12:00Z", "end": "2026-11-07T06:12:00Z", "asleep": 350}}},
    "connection": {"server": "https://example.invalid", "token": "t"},
    "dirty": {"water:W1": 3},
    "tombstones": ["log:X|2026-11-01"],
    "rev": 192,
    "seeded": True,
}

if __name__ == "__main__":
    print(json.dumps(fixture, ensure_ascii=False))
