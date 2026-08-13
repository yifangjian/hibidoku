import Foundation
import SQLite3
import Compression

/// Provides catalog queries and text download for Aozora Bunko works.
final class AozoraService: @unchecked Sendable {
    static let shared = AozoraService()

    private var db: OpaquePointer?

    // MARK: - Data Types

    struct Author: Identifiable {
        let id: Int          // person_id
        let name: String
        let nameReading: String?
        let workCount: Int
    }

    struct Work: Identifiable {
        let id: Int          // work_id
        let title: String
        let titleReading: String?
        let authorId: Int
        let authorName: String
        let orthography: String?
        let textURL: String
        let textEncoding: String
    }

    // MARK: - Init

    private init() {
        guard let path = Bundle.main.path(forResource: "aozora_catalog", ofType: "sqlite") else {
            print("AozoraService: aozora_catalog.sqlite not found in bundle")
            return
        }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("AozoraService: Failed to open database")
            db = nil
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Catalog Queries

    /// Top authors sorted by work count.
    func topAuthors(limit: Int = 50) -> [Author] {
        guard let db else { return [] }
        let sql = "SELECT person_id, name, name_reading, work_count FROM authors ORDER BY work_count DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        var results: [Author] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Author(
                id: Int(sqlite3_column_int(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                nameReading: columnText(stmt, 2),
                workCount: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return results
    }

    /// Works by a specific author.
    func works(byAuthorId authorId: Int) -> [Work] {
        guard let db else { return [] }
        let sql = "SELECT work_id, title, title_reading, author_id, author_name, orthography, text_url, text_encoding FROM works WHERE author_id = ? ORDER BY title"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(authorId))
        return collectWorks(stmt)
    }

    /// Search works by title (partial match).
    func searchWorks(query: String) -> [Work] {
        guard let db, !query.isEmpty else { return [] }
        let sql = "SELECT work_id, title, title_reading, author_id, author_name, orthography, text_url, text_encoding FROM works WHERE title LIKE ? ORDER BY title LIMIT 100"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        return collectWorks(stmt)
    }

    /// Search authors by name (partial match).
    func searchAuthors(query: String) -> [Author] {
        guard let db, !query.isEmpty else { return [] }
        let sql = "SELECT person_id, name, name_reading, work_count FROM authors WHERE name LIKE ? ORDER BY work_count DESC LIMIT 50"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        var results: [Author] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Author(
                id: Int(sqlite3_column_int(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                nameReading: columnText(stmt, 2),
                workCount: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return results
    }

    // MARK: - Download

    /// Download and extract text for a work. Returns cleaned UTF-8 text.
    func downloadText(for work: Work) async throws -> String {
        guard let url = URL(string: work.textURL) else {
            throw AozoraError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // The URL points to a ZIP file containing the text
        let textData: Data
        if isZip(data) {
            textData = try extractFirstFileFromZip(data)
        } else {
            textData = data
        }

        // Decode based on encoding info
        let rawText = decodeText(textData, encoding: work.textEncoding)
        guard let rawText else {
            throw AozoraError.decodingFailed
        }

        return AozoraTextParser.clean(rawText)
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func collectWorks(_ stmt: OpaquePointer?) -> [Work] {
        var results: [Work] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Work(
                id: Int(sqlite3_column_int(stmt, 0)),
                title: String(cString: sqlite3_column_text(stmt, 1)),
                titleReading: columnText(stmt, 2),
                authorId: Int(sqlite3_column_int(stmt, 3)),
                authorName: String(cString: sqlite3_column_text(stmt, 4)),
                orthography: columnText(stmt, 5),
                textURL: String(cString: sqlite3_column_text(stmt, 6)),
                textEncoding: String(cString: sqlite3_column_text(stmt, 7))
            ))
        }
        return results
    }

    private func decodeText(_ data: Data, encoding: String) -> String? {
        // Try specified encoding first
        let primaryEncoding: String.Encoding = encoding.contains("UTF") ? .utf8 : .shiftJIS
        if let text = String(data: data, encoding: primaryEncoding) {
            return text
        }
        // Fallback chain
        for enc in [String.Encoding.shiftJIS, .japaneseEUC, .utf8] {
            if let text = String(data: data, encoding: enc) {
                return text
            }
        }
        return nil
    }

    // MARK: - ZIP Extraction (minimal, zero-dependency)

    private func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04
    }

    /// Extract the first file from a ZIP archive.
    /// Handles DEFLATE (method 8) and STORED (method 0).
    private func extractFirstFileFromZip(_ data: Data) throws -> Data {
        guard data.count >= 30 else { throw AozoraError.invalidZip }

        // Local file header
        let compMethod = UInt16(data[8]) | (UInt16(data[9]) << 8)
        let compSize = UInt32(data[18]) | (UInt32(data[19]) << 8) | (UInt32(data[20]) << 16) | (UInt32(data[21]) << 24)
        let uncompSize = UInt32(data[22]) | (UInt32(data[23]) << 8) | (UInt32(data[24]) << 16) | (UInt32(data[25]) << 24)
        let nameLen = UInt16(data[26]) | (UInt16(data[27]) << 8)
        let extraLen = UInt16(data[28]) | (UInt16(data[29]) << 8)

        let dataOffset = 30 + Int(nameLen) + Int(extraLen)
        let compressedData = data[dataOffset..<(dataOffset + Int(compSize))]

        if compMethod == 0 {
            // STORED
            return Data(compressedData)
        } else if compMethod == 8 {
            // DEFLATE
            return try decompressDeflate(Data(compressedData), uncompressedSize: Int(uncompSize))
        } else {
            throw AozoraError.unsupportedCompression
        }
    }

    private func decompressDeflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        let bufferSize = max(uncompressedSize, compressed.count * 4)
        var decompressed = Data(count: bufferSize)

        let result = compressed.withUnsafeBytes { srcPtr -> Int in
            decompressed.withUnsafeMutableBytes { dstPtr -> Int in
                guard let src = srcPtr.baseAddress,
                      let dst = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    dst, bufferSize,
                    src.assumingMemoryBound(to: UInt8.self), compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else { throw AozoraError.decompressionFailed }
        return decompressed.prefix(result)
    }

    // MARK: - Errors

    enum AozoraError: LocalizedError {
        case invalidURL
        case decodingFailed
        case invalidZip
        case unsupportedCompression
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: "無效的下載連結"
            case .decodingFailed: "文字編碼解析失敗"
            case .invalidZip: "無效的 ZIP 檔案"
            case .unsupportedCompression: "不支援的壓縮格式"
            case .decompressionFailed: "解壓縮失敗"
            }
        }
    }
}
