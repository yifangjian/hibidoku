#!/usr/bin/env python3
"""
Convert jmdict-simplified JSON to SQLite for the hibidoku app.

Supports both jmdict-eng-common (22K entries) and full jmdict-eng (180K+ entries).
The full version is preferred for better lookup coverage.

Usage:
  1. Download from https://github.com/scriptin/jmdict-simplified/releases
     - Recommended: jmdict-eng-3.6.1+20250505133950.json.zip (full version)
     - Alternative: jmdict-eng-common-3.6.1+20250505133950.json.zip (common only)
  2. Unzip the JSON file into this directory
  3. Run: python3 build_dictionary.py
  4. Copy the output jmdict.sqlite to hibidoku/hibidoku/
"""
import json
import sqlite3
import os
import glob

# Prefer full version, fall back to common-only
json_files = glob.glob("jmdict-eng-3*.json")
is_full = True
if not json_files:
    json_files = glob.glob("jmdict-eng-common*.json")
    is_full = False
if not json_files:
    print("Error: No jmdict-eng*.json file found in current directory.")
    print("Download from: https://github.com/scriptin/jmdict-simplified/releases")
    print("  Full version:   jmdict-eng-*.json.zip")
    print("  Common only:    jmdict-eng-common-*.json.zip")
    exit(1)

json_file = json_files[0]
print(f"Reading {json_file} ({'full' if is_full else 'common-only'})...")

with open(json_file, "r") as f:
    data = json.load(f)

db_path = "jmdict.sqlite"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY, common INTEGER DEFAULT 0)")
c.execute("CREATE TABLE kanji_elements (entry_id INTEGER NOT NULL, text TEXT NOT NULL, common INTEGER DEFAULT 0)")
c.execute("CREATE TABLE kana_elements (entry_id INTEGER NOT NULL, text TEXT NOT NULL, common INTEGER DEFAULT 0)")
c.execute("CREATE TABLE senses (entry_id INTEGER NOT NULL, pos TEXT, glosses TEXT NOT NULL)")

tags = data.get("tags", {})

for word in data["words"]:
    entry_id = int(word["id"])

    # Determine if this is a common word
    kanji_list = word.get("kanji", [])
    kana_list = word.get("kana", [])
    has_common_kanji = any("news" in k.get("common", []) or "ichi" in str(k.get("common", [])) for k in kanji_list)
    has_common_kana = any("news" in k.get("common", []) or "ichi" in str(k.get("common", [])) for k in kana_list)
    is_common = 1 if (has_common_kanji or has_common_kana or not is_full) else 0

    c.execute("INSERT INTO entries (id, common) VALUES (?, ?)", (entry_id, is_common))
    for k in kanji_list:
        k_common = 1 if ("news" in str(k.get("common", [])) or "ichi" in str(k.get("common", []))) else 0
        c.execute("INSERT INTO kanji_elements (entry_id, text, common) VALUES (?, ?, ?)",
                  (entry_id, k["text"], k_common))
    for k in kana_list:
        k_common = 1 if ("news" in str(k.get("common", [])) or "ichi" in str(k.get("common", []))) else 0
        c.execute("INSERT INTO kana_elements (entry_id, text, common) VALUES (?, ?, ?)",
                  (entry_id, k["text"], k_common))
    for s in word.get("sense", []):
        pos_readable = ", ".join(tags.get(p, p) for p in s.get("partOfSpeech", []))
        glosses = "; ".join(g["text"] for g in s.get("gloss", []))
        c.execute("INSERT INTO senses (entry_id, pos, glosses) VALUES (?, ?, ?)",
                  (entry_id, pos_readable, glosses))

c.execute("CREATE INDEX idx_kanji_text ON kanji_elements(text)")
c.execute("CREATE INDEX idx_kana_text ON kana_elements(text)")
c.execute("CREATE INDEX idx_senses_entry ON senses(entry_id)")
c.execute("CREATE INDEX idx_kanji_entry ON kanji_elements(entry_id)")
c.execute("CREATE INDEX idx_kana_entry ON kana_elements(entry_id)")

conn.commit()
conn.execute("VACUUM")

# Verify
c.execute("SELECT COUNT(*) FROM entries")
total = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM entries WHERE common = 1")
common = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM senses")
senses = c.fetchone()[0]

print(f"Entries: {total} (common: {common})")
print(f"Senses: {senses}")

conn.close()
size_mb = os.path.getsize(db_path) / 1024 / 1024
print(f"Output: {db_path} ({size_mb:.1f} MB)")
print(f"Copy to: hibidoku/hibidoku/jmdict.sqlite")
