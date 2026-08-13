#!/usr/bin/env python3
"""
Convert jmdict-eng-common JSON to SQLite for the hibidoku app.

Usage:
  1. Download jmdict-eng-common from https://github.com/scriptin/jmdict-simplified/releases
  2. Unzip the JSON file into this directory
  3. Run: python3 build_dictionary.py
  4. Copy the output jmdict.sqlite to hibidoku/hibidoku/
"""
import json
import sqlite3
import os
import glob

# Find the JSON file
json_files = glob.glob("jmdict-eng-common*.json")
if not json_files:
    print("Error: No jmdict-eng-common*.json file found in current directory.")
    print("Download from: https://github.com/scriptin/jmdict-simplified/releases")
    exit(1)

json_file = json_files[0]
print(f"Reading {json_file}...")

with open(json_file, "r") as f:
    data = json.load(f)

db_path = "jmdict.sqlite"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY, common INTEGER DEFAULT 1)")
c.execute("CREATE TABLE kanji_elements (entry_id INTEGER NOT NULL, text TEXT NOT NULL)")
c.execute("CREATE TABLE kana_elements (entry_id INTEGER NOT NULL, text TEXT NOT NULL)")
c.execute("CREATE TABLE senses (entry_id INTEGER NOT NULL, pos TEXT, glosses TEXT NOT NULL)")

tags = data.get("tags", {})

for word in data["words"]:
    entry_id = int(word["id"])
    c.execute("INSERT INTO entries (id) VALUES (?)", (entry_id,))
    for k in word.get("kanji", []):
        c.execute("INSERT INTO kanji_elements (entry_id, text) VALUES (?, ?)", (entry_id, k["text"]))
    for k in word.get("kana", []):
        c.execute("INSERT INTO kana_elements (entry_id, text) VALUES (?, ?)", (entry_id, k["text"]))
    for s in word.get("sense", []):
        pos_readable = ", ".join(tags.get(p, p) for p in s.get("partOfSpeech", []))
        glosses = "; ".join(g["text"] for g in s.get("gloss", []))
        c.execute("INSERT INTO senses (entry_id, pos, glosses) VALUES (?, ?, ?)", (entry_id, pos_readable, glosses))

c.execute("CREATE INDEX idx_kanji_text ON kanji_elements(text)")
c.execute("CREATE INDEX idx_kana_text ON kana_elements(text)")
c.execute("CREATE INDEX idx_senses_entry ON senses(entry_id)")
c.execute("CREATE INDEX idx_kanji_entry ON kanji_elements(entry_id)")
c.execute("CREATE INDEX idx_kana_entry ON kana_elements(entry_id)")

conn.commit()

# Verify
c.execute("SELECT COUNT(*) FROM entries")
print(f"Entries: {c.fetchone()[0]}")
c.execute("SELECT COUNT(*) FROM senses")
print(f"Senses: {c.fetchone()[0]}")

conn.close()
print(f"Output: {db_path} ({os.path.getsize(db_path) / 1024 / 1024:.1f} MB)")
print(f"Copy to: hibidoku/hibidoku/jmdict.sqlite")
