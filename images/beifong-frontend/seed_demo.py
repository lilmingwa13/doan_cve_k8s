"""Create deterministic, local-only Beifong demo data for the Chapter 3 UI.

The upstream application normally fills the podcast database through its
agent workflow. The lab has no external model/API credentials, so a single
fixture lets the Podcasts page and audio player be demonstrated without
changing the upstream source code or contacting a third party.
"""

import json
import os
import sqlite3
import wave
from datetime import datetime
from pathlib import Path


ROOT = Path("/app")
DB_PATH = Path(os.environ.get("PODCASTS_DB_PATH", ROOT / "databases" / "podcasts.db"))
AUDIO_DIR = ROOT / "podcasts" / "audio"
AUDIO_PATH = AUDIO_DIR / "demo-podcast.wav"
BASELINE_AUDIO_PATH = AUDIO_DIR / "demo-audio.txt"
TITLE = "Cloud-native AI Security Lab — Demo Briefing"


def write_demo_audio() -> None:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    if not BASELINE_AUDIO_PATH.exists():
        BASELINE_AUDIO_PATH.write_text("LAB_AUDIO_BASELINE\n", encoding="utf-8")
    if AUDIO_PATH.exists() and AUDIO_PATH.stat().st_size > 44:
        return
    # A short silent PCM WAV is deterministic and contains no external data.
    with wave.open(str(AUDIO_PATH), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16000)
        audio.writeframes(b"\x00\x00" * 16000)


def seed_database() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    content = {
        "title": TITLE,
        "sections": [
            {
                "heading": "Demo briefing",
                "text": "Local fixture for validating the Beifong Podcasts interface in the Kubernetes lab.",
            },
            {
                "heading": "Scope",
                "text": "No OpenAI, GitHub, or other external service is contacted by this fixture.",
            },
        ],
    }
    now = datetime.utcnow().isoformat(timespec="seconds") + "Z"
    with sqlite3.connect(DB_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS podcasts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                date TEXT,
                content_json TEXT,
                audio_generated BOOLEAN DEFAULT 0,
                audio_path TEXT,
                banner_img_path TEXT,
                tts_engine TEXT DEFAULT 'elevenlabs',
                language_code TEXT DEFAULT 'en',
                sources_json TEXT,
                banner_images TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        existing = connection.execute(
            "SELECT id FROM podcasts WHERE title = ? LIMIT 1", (TITLE,)
        ).fetchone()
        if existing is None:
            connection.execute(
                """
                INSERT INTO podcasts
                    (title, date, content_json, audio_generated, audio_path,
                     tts_engine, language_code, sources_json, banner_images, created_at)
                VALUES (?, ?, ?, 1, ?, 'lab-fixture', 'en', ?, '[]', ?)
                """,
                (
                    TITLE,
                    datetime.utcnow().strftime("%Y-%m-%d"),
                    json.dumps(content),
                    AUDIO_PATH.name,
                    json.dumps([{"title": "Local lab fixture", "url": "about:blank"}]),
                    now,
                ),
            )
        connection.commit()


if __name__ == "__main__":
    write_demo_audio()
    seed_database()
    print(f"Beifong demo fixture ready: {TITLE}")
