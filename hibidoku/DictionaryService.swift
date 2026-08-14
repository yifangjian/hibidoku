import Foundation
import SQLite3

struct DictEntry: Identifiable {
    let id: Int
    let kanjiText: String?
    let kanaText: String
    let partsOfSpeech: String?
    let glosses: String
}

/// Result of a dictionary lookup, including both the matched entries
/// and the dictionary form of the word (if deinflected).
struct LookupResult {
    let entries: [DictEntry]
    /// The form that actually matched in the dictionary (may differ from the input
    /// if the word was deinflected, e.g. "食べている" → "食べる").
    let matchedForm: String?
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
    /// Tries exact match first, then deinflection, then progressively shorter substrings.
    func lookup(_ word: String) -> [DictEntry] {
        smartLookup(word).entries
    }

    /// Look up with full result info (matched form, deinflection, etc.)
    func smartLookup(_ word: String) -> LookupResult {
        guard db != nil else { return LookupResult(entries: [], matchedForm: nil) }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LookupResult(entries: [], matchedForm: nil) }

        // 1. Try exact match
        let exact = exactLookup(trimmed)
        if !exact.isEmpty {
            return LookupResult(entries: exact, matchedForm: trimmed)
        }

        // 2. Try deinflection (e.g. 食べている → 食べる)
        for candidate in Deinflector.deinflect(trimmed) {
            let results = exactLookup(candidate)
            if !results.isEmpty {
                return LookupResult(entries: results, matchedForm: candidate)
            }
        }

        // 3. Try progressively shorter prefixes (for compound tokens)
        let chars = Array(trimmed)
        if chars.count > 1 {
            for length in stride(from: chars.count - 1, through: max(chars.count / 2, 1), by: -1) {
                let sub = String(chars.prefix(length))
                let results = exactLookup(sub)
                if !results.isEmpty {
                    return LookupResult(entries: results, matchedForm: sub)
                }
                // Also try deinflection on the prefix
                for candidate in Deinflector.deinflect(sub) {
                    let dResults = exactLookup(candidate)
                    if !dResults.isEmpty {
                        return LookupResult(entries: dResults, matchedForm: candidate)
                    }
                }
            }
        }

        return LookupResult(entries: [], matchedForm: nil)
    }

    // MARK: - Exact Lookup

    private func exactLookup(_ word: String) -> [DictEntry] {
        let kanjiResults = queryByKanji(word)
        if !kanjiResults.isEmpty {
            return kanjiResults
        }
        return queryByKana(word)
    }

    private func queryByKanji(_ word: String) -> [DictEntry] {
        let sql = """
            SELECT e.id, k.text, ka.text, s.pos, s.glosses
            FROM kanji_elements k
            JOIN entries e ON k.entry_id = e.id
            JOIN kana_elements ka ON ka.entry_id = e.id
            JOIN senses s ON s.entry_id = e.id
            WHERE k.text = ?
            ORDER BY e.common DESC
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
            ORDER BY e.common DESC
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

// MARK: - Japanese Deinflector

/// Strips common Japanese verb/adjective conjugation endings to recover
/// the dictionary form (辞書形). Handles te-form, masu-form, ta-form,
/// nai-form, progressive, potential, passive, causative, etc.
enum Deinflector {

    /// Return candidate dictionary forms (most likely first, no duplicates).
    static func deinflect(_ word: String) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func add(_ s: String) {
            guard !s.isEmpty, !seen.contains(s), s != word else { return }
            seen.insert(s)
            candidates.append(s)
        }

        // --- て/で form → dictionary form ---
        // 食べて → 食べる, 読んで → 読む, 行って → 行く, etc.
        applyTeFormRules(word, add: add)

        // --- た/だ form (past tense) ---
        applyTaFormRules(word, add: add)

        // --- ます form ---
        if word.hasSuffix("ます") {
            let stem = String(word.dropLast(2))
            addIchidanAndGodanFromMasuStem(stem, add: add)
        }
        if word.hasSuffix("ました") {
            let stem = String(word.dropLast(3))
            addIchidanAndGodanFromMasuStem(stem, add: add)
        }
        if word.hasSuffix("ません") {
            let stem = String(word.dropLast(3))
            addIchidanAndGodanFromMasuStem(stem, add: add)
        }

        // --- ない form (negative) ---
        if word.hasSuffix("ない") {
            let stem = String(word.dropLast(2))
            // ichidan: 食べない → 食べる
            add(stem + "る")
            // godan: 読まない → 読む, 書かない → 書く, etc.
            addGodanFromNegStem(stem, add: add)
        }
        if word.hasSuffix("なかった") {
            let stem = String(word.dropLast(4))
            add(stem + "る")
            addGodanFromNegStem(stem, add: add)
        }

        // --- ている / ていた / でいる / でいた (progressive) ---
        for (suffix, dropCount) in [("ている", 3), ("ていた", 3), ("でいる", 3), ("でいた", 3)] {
            if word.hasSuffix(suffix) {
                let base = String(word.dropLast(dropCount))
                let connector = suffix.hasPrefix("て") ? "て" : "で"
                let teForm = base + connector
                for c in deinflect(teForm) { add(c) }
            }
        }
        // Contracted forms: 食べてる, 読んでる
        if word.hasSuffix("てる") || word.hasSuffix("でる") {
            let base = String(word.dropLast(1)) // remove る, keep て/で
            for c in deinflect(base) { add(c) }
        }

        // --- potential form ---
        // 食べられる → 食べる, 読める → 読む
        if word.hasSuffix("られる") {
            add(String(word.dropLast(3)) + "る")
        }
        if word.hasSuffix("える") {
            let stem = String(word.dropLast(2))
            add(stem + "う")
        }
        if word.hasSuffix("ける") {
            add(String(word.dropLast(2)) + "く")
        }
        if word.hasSuffix("せる") {
            let stem = String(word.dropLast(2))
            add(stem + "す")
        }
        if word.hasSuffix("てる") && !word.hasSuffix("てる") {
            // handled above
        }
        if word.hasSuffix("める") {
            add(String(word.dropLast(2)) + "む")
        }
        if word.hasSuffix("ねる") {
            add(String(word.dropLast(2)) + "ぬ")
        }
        if word.hasSuffix("べる") {
            add(String(word.dropLast(2)) + "ぶ")
        }
        if word.hasSuffix("れる") {
            // passive or ichidan
            add(String(word.dropLast(2)) + "る")
        }

        // --- i-adjective ---
        if word.hasSuffix("くない") {
            add(String(word.dropLast(3)) + "い")
        }
        if word.hasSuffix("かった") {
            add(String(word.dropLast(3)) + "い")
        }
        if word.hasSuffix("くなかった") {
            add(String(word.dropLast(5)) + "い")
        }
        if word.hasSuffix("くて") {
            add(String(word.dropLast(2)) + "い")
        }

        return candidates
    }

    // MARK: - Te-form rules

    private static func applyTeFormRules(_ word: String, add: (String) -> Void) {
        if word.hasSuffix("って") {
            let stem = String(word.dropLast(2))
            add(stem + "う")  // 買って → 買う
            add(stem + "つ")  // 待って → 待つ
            add(stem + "る")  // 走って → 走る (godan る)
        }
        if word.hasSuffix("いて") {
            add(String(word.dropLast(2)) + "く")  // 書いて → 書く
        }
        if word.hasSuffix("いで") {
            add(String(word.dropLast(2)) + "ぐ")  // 泳いで → 泳ぐ
        }
        if word.hasSuffix("して") {
            add(String(word.dropLast(2)) + "す")  // 話して → 話す
        }
        if word.hasSuffix("んで") {
            let stem = String(word.dropLast(2))
            add(stem + "む")  // 読んで → 読む
            add(stem + "ぬ")  // 死んで → 死ぬ
            add(stem + "ぶ")  // 遊んで → 遊ぶ
        }
        // ichidan te-form: 食べて → 食べる
        if word.hasSuffix("て") {
            add(String(word.dropLast(1)) + "る")
        }
        // 行って is special: 行く
        if word.hasSuffix("行って") || word.hasSuffix("いって") {
            add(String(word.dropLast(2)) + "く")
        }
    }

    // MARK: - Ta-form rules (same consonant changes as te-form)

    private static func applyTaFormRules(_ word: String, add: (String) -> Void) {
        if word.hasSuffix("った") {
            let stem = String(word.dropLast(2))
            add(stem + "う")
            add(stem + "つ")
            add(stem + "る")
        }
        if word.hasSuffix("いた") {
            add(String(word.dropLast(2)) + "く")
        }
        if word.hasSuffix("いだ") {
            add(String(word.dropLast(2)) + "ぐ")
        }
        if word.hasSuffix("した") {
            add(String(word.dropLast(2)) + "す")
        }
        if word.hasSuffix("んだ") {
            let stem = String(word.dropLast(2))
            add(stem + "む")
            add(stem + "ぬ")
            add(stem + "ぶ")
        }
        if word.hasSuffix("た") {
            add(String(word.dropLast(1)) + "る")
        }
    }

    // MARK: - Masu stem helpers

    private static func addIchidanAndGodanFromMasuStem(_ stem: String, add: (String) -> Void) {
        // ichidan: 食べ+ます → 食べる
        add(stem + "る")
        // godan: the stem ends with the い-dan of the consonant row
        guard let lastChar = stem.last else { return }
        let base = String(stem.dropLast())
        switch lastChar {
        case "い": add(base + "う")
        case "き": add(base + "く")
        case "ぎ": add(base + "ぐ")
        case "し": add(base + "す")
        case "ち": add(base + "つ")
        case "に": add(base + "ぬ")
        case "び": add(base + "ぶ")
        case "み": add(base + "む")
        case "り": add(base + "る")
        default: break
        }
    }

    // MARK: - Negative stem helpers

    private static func addGodanFromNegStem(_ stem: String, add: (String) -> Void) {
        // godan negative: stem ends with あ-dan
        guard let lastChar = stem.last else { return }
        let base = String(stem.dropLast())
        switch lastChar {
        case "わ": add(base + "う")
        case "か": add(base + "く")
        case "が": add(base + "ぐ")
        case "さ": add(base + "す")
        case "た": add(base + "つ")
        case "な": add(base + "ぬ")
        case "ば": add(base + "ぶ")
        case "ま": add(base + "む")
        case "ら": add(base + "る")
        default: break
        }
        // する → し+ない
        if stem.hasSuffix("し") {
            add(String(stem.dropLast()) + "する")
        }
    }
}
