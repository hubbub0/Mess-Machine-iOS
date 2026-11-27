import Compression
import Foundation

/// Reads a zip's files (stored or deflated), enough for sound packs. iOS has no public unzip. Every name is checked
/// by the caller before anything is written.
enum ZipReader {
    struct Entry { let name: String; let isDirectory: Bool; let data: Data }

    enum Problem: LocalizedError, CustomStringConvertible {
        case notAZip, unsupported(String), damaged(String)
        var description: String {
            switch self {
            case .notAZip: return "not a zip file"
            case .unsupported(let n): return "\(n) is packed in a way this phone cannot open"
            case .damaged(let n): return "\(n) is damaged"
            }
        }
        var errorDescription: String? { description }
    }

    static func entries(_ zip: Data) throws -> [Entry] {
        let b = [UInt8](zip)
        func u16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { i + 3 < b.count ? u16(i) | u16(i + 2) << 16 : 0 }

        // the end of central directory record: the last PK\5\6 within the final 64 KB
        var end = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65557) {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 5, b[i + 3] == 6 { end = i; break }
            i -= 1
        }
        guard end >= 0 else { throw Problem.notAZip }
        let count = u16(end + 10)
        var p = u32(end + 16)
        var out: [Entry] = []
        for _ in 0..<count {
            guard u32(p) == 0x02014b50 else { throw Problem.notAZip }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nlen <= b.count else { throw Problem.notAZip }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen

            guard u32(local) == 0x04034b50 else { throw Problem.damaged(name) }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { throw Problem.damaged(name) }
            if name.hasSuffix("/") { out.append(Entry(name: name, isDirectory: true, data: Data())); continue }
            let raw = Data(b[start..<(start + csize)])
            switch method {
            case 0: out.append(Entry(name: name, isDirectory: false, data: raw))
            case 8: out.append(Entry(name: name, isDirectory: false, data: try inflate(raw, size: usize, name: name)))
            default: throw Problem.unsupported(name)
            }
        }
        return out
    }

    /// Raw deflate (zip's method 8): Apple's COMPRESSION_ZLIB is raw deflate without the zlib header.
    static func inflate(_ d: Data, size: Int, name: String) throws -> Data {
        if size == 0 { return Data() }
        guard !d.isEmpty else { throw Problem.damaged(name) }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == size else { throw Problem.damaged(name) }
        return out
    }
}
