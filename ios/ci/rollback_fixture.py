"""A synthetic data file in the format the 2 Nov build writes (no real data): one of everything that matters."""
import json

fixture = {
    "promises": {"P1": {"id": "P1", "title": "Creatina", "icon": "pills.fill", "kind": "mustDo",
                        "schedule": {"rule": "daily", "every": 2, "start": "2026-11-01", "weekdays": [2, 4, 6], "minute": 470},
                        "active": True, "created": 1793524150000}},
    # an answer from before phase 2.2 (no source), one imported from the band and one you gave (phase 2.2)
    "logs": {"P1|2026-11-04": {"promiseId": "P1", "date": "2026-11-04", "status": "done", "at": 1793790000000},
             "P1|2026-11-03": {"promiseId": "P1", "date": "2026-11-03", "status": "done", "at": 1793700000000, "source": "fitbit"},
             "P1|2026-11-02": {"promiseId": "P1", "date": "2026-11-02", "status": "skipped", "at": 1793610000000, "source": "you"}},
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
