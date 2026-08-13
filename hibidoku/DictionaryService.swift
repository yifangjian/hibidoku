import Foundation
import SQLite3

struct DictEntry: Identifiable {
    let id: Int
    let kanjiText: String?
    let kanaText: String
    let partsOfSpeech: String?
    let glosses: String
}

final class DictionaryService {

    static let shared = DictionaryService()

    private var db: OpaquePointer?

    private init() {
        guard let dbPath = Bundle.main.path(forResource: "jmdict", ofType: "sqlite") else {
            print("DictionaryService: jmdict.sqlite not found in bundle")
            return
        }
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("DictionaryService: failed to open database")
            db = nil
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    /// Look up a word by its surface form (kanji or kana).
    /// First tries exact match on kanji_elements, then falls back to kana_elements.
    func lookup(_ word: String) -> [DictEntry] {
        guard db != nil else { return [] }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Try kanji match first
        let kanjiResults = queryByKanji(trimmed)
        if !kanjiResults.isEmpty {
            return kanjiResults
        }

        // Fall back to kana match
        return queryByKana(trimmed)
    }

    private func queryByKanji(_ word: String) -> [DictEntry] {
        let sql = """
            SELECT e.id, k.text, ka.text, s.pos, s.glosses
            FROM kanji_elements k
            JOIN entries e ON k.entry_id = e.id
            JOIN kana_elements ka ON ka.entry_id = e.id
            JOIN senses s ON s.entry_id = e.id
            WHERE k.text = ?
            """
        return executeQuery(sql, param: word)
    }

    private func queryByKana(_ word: String) -> [DictEntry] {
        let sql = """
            SELECT e.id, NULL, ka.text, s.pos, s.glosses
            FROM kana_elements ka
            JOIN entries e ON ka.entry_id = e.id
            JOIN senses s ON s.entry_id = e.id
            WHERE ka.text = ?
            """
        return executeQuery(sql, param: word)
    }

    private func executeQuery(_ sql: String, param: String) -> [DictEntry] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (param as NSString).utf8String, -1, nil)

        var results: [DictEntry] = []
        // Track seen (id, glosses) pairs to avoid duplicates from JOINs
        var seen = Set<String>()

        while sqlite3_step(stmt) == SQLITE_ROW {
            let entryId = Int(sqlite3_column_int64(stmt, 0))
            let kanjiText = columnText(stmt, index: 1)
            let kanaText = columnText(stmt, index: 2) ?? ""
            let pos = columnText(stmt, index: 3)
            let glosses = columnText(stmt, index: 4) ?? ""

            let key = "\(entryId)-\(glosses)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(DictEntry(
                id: entryId,
                kanjiText: kanjiText,
                kanaText: kanaText,
                partsOfSpeech: pos,
                glosses: glosses
            ))
        }

        return results
    }

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }
}
