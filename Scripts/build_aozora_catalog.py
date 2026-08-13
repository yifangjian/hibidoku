#!/usr/bin/env python3
"""
Convert Aozora Bunko official CSV to a compact SQLite catalog for the hibidoku app.

Usage:
  1. Download list_person_all_extended_utf8.zip from https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip
  2. Unzip into this directory
  3. Run: python3 build_aozora_catalog.py
  4. Copy the output aozora_catalog.sqlite to hibidoku/hibidoku/
"""
import csv
import sqlite3
import os

CSV_FILE = "list_person_all_extended_utf8.csv"
DB_FILE = "aozora_catalog.sqlite"

if not os.path.exists(CSV_FILE):
    print(f"Error: {CSV_FILE} not found.")
    print("Download from: https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip")
    exit(1)

if os.path.exists(DB_FILE):
    os.remove(DB_FILE)

conn = sqlite3.connect(DB_FILE)
c = conn.cursor()

c.execute("""
CREATE TABLE authors (
    person_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    name_reading TEXT,
    work_count INTEGER DEFAULT 0
)
""")

c.execute("""
CREATE TABLE works (
    work_id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    title_reading TEXT,
    author_id INTEGER NOT NULL,
    author_name TEXT NOT NULL,
    orthography TEXT,
    text_url TEXT NOT NULL,
    text_encoding TEXT,
    FOREIGN KEY (author_id) REFERENCES authors(person_id)
)
""")

# Parse CSV
seen_works = set()
author_data = {}
work_rows = []

with open(CSV_FILE, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row["作品著作権フラグ"] != "なし":
            continue
        text_url = row["テキストファイルURL"].strip()
        if not text_url:
            continue
        if row["役割フラグ"] != "著者":
            continue

        work_id = int(row["作品ID"])
        if work_id in seen_works:
            continue
        seen_works.add(work_id)

        person_id = int(row["人物ID"])
        last_name = row["姓"].strip()
        first_name = row["名"].strip()
        author_name = last_name + first_name if last_name else first_name
        name_reading = (row["姓読み"].strip() + row["名読み"].strip()).strip() or None

        if person_id not in author_data:
            author_data[person_id] = {
                "name": author_name,
                "name_reading": name_reading,
                "work_count": 0,
            }
        author_data[person_id]["work_count"] += 1

        work_rows.append((
            work_id,
            row["作品名"].strip(),
            row["作品名読み"].strip() or None,
            person_id,
            author_name,
            row["文字遣い種別"].strip() or None,
            text_url,
            row["テキストファイル符号化方式"].strip() or "ShiftJIS",
        ))

for pid, a in author_data.items():
    c.execute("INSERT INTO authors VALUES (?, ?, ?, ?)",
              (pid, a["name"], a["name_reading"], a["work_count"]))

c.executemany("INSERT INTO works VALUES (?, ?, ?, ?, ?, ?, ?, ?)", work_rows)

c.execute("CREATE INDEX idx_works_author ON works(author_id)")
c.execute("CREATE INDEX idx_works_title ON works(title)")
c.execute("CREATE INDEX idx_authors_work_count ON authors(work_count DESC)")

conn.commit()
conn.execute("VACUUM")

c.execute("SELECT COUNT(*) FROM authors")
print(f"Authors: {c.fetchone()[0]}")
c.execute("SELECT COUNT(*) FROM works")
print(f"Works: {c.fetchone()[0]}")
c.execute("SELECT name, work_count FROM authors ORDER BY work_count DESC LIMIT 10")
print("\nTop 10 authors:")
for name, count in c.fetchall():
    print(f"  {name}: {count}")

conn.close()
size_mb = os.path.getsize(DB_FILE) / 1024 / 1024
print(f"\nOutput: {DB_FILE} ({size_mb:.1f} MB)")
print(f"Copy to: hibidoku/hibidoku/aozora_catalog.sqlite")
