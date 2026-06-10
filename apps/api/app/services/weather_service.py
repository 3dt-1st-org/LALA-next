from __future__ import annotations


def current_weather(*, lat: float, lng: float, force: bool = False) -> dict:
    return {
        "lat": lat,
        "lng": lng,
        "temp": "11",
        "icon": "partly-cloudy",
        "dust": {
            "pm10": "37",
            "pm25": "26",
            "grade": "normal",
            "grade_ko": "보통",
        },
        "forecast": [
            {"time": "2026-06-11T12:00:00+09:00", "temp": "12", "icon": "partly-cloudy"}
        ],
        "outdoor_status": "good",
        "force": force,
        "source": "skeleton",
    }

