"""A synthetic data file in the format the 2 Nov build writes (no real data): one of everything that matters."""
import json

fixture = {
    "promises": {"P1": {"id": "P1", "title": "Creatina", "icon": "pills.fill", "kind": "mustDo",
                        "schedule": {"rule": "daily", "every": 2, "start": "2026-11-01", "weekdays": [2, 4, 6], "minute": 470},
                        "active": True, "created": 1793524150000}},
    "logs": {"P1|2026-11-04": {"promiseId": "P1", "date": "2026-11-04", "status": "done", "at": 1793790000000}},
    "days": {"2026-11-03": {"date": "2026-11-03", "rating": 4, "note": "Dia bom: ação e ténis", "top3": ["Pernas"], "top3Done": [True],
                            "closedAt": 1793741954837.537, "score": 45, "points": 45, "energy": 4}},
    "profile": {"name": "", "weightKg": 78, "kcalTarget": 3160, "areasOff": ["money"], "goal": "gain", "stepGoal": 10000},
    "feedback": {"2026-11-02": {"date": "2026-11-02", "score": 52, "felt": -1}},
    "extra": {
        "water": {"W1": {"id": "W1", "date": "2026-11-04", "minute": 891, "ml": 250}},
        "medlog": {"M1|2026-11-04|480": {"medId": "M1", "taken": True, "minute": 480}},
        "gymBag": {"2026-11-02": True},
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
