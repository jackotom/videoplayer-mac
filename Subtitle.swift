import Foundation

// MARK: - 字幕模型与解析（SRT / VTT / ASS）

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleParser {

    static func load(url: URL) -> [SubtitleCue] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))

        // 依次尝试多种编码（SRT/VTT 中文常见 GBK / UTF-8 / UTF-16）
        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
            gbk, big5, .windowsCP1252, .isoLatin1,
        ]
        for enc in encodings {
            if let s = String(data: data, encoding: enc) {
                let cues = parse(text: s)
                if !cues.isEmpty { return cues }
            }
        }
        return []
    }

    /// 剥离 VTT/SRT 里常见的 HTML 标签（<i>、<b>、<c.yellow> 等），保留文本内容
    static func stripBasicTags(_ s: String) -> String {
        // 只匹配形如 <tag> / </tag> 的完整标签；"a < b" 这类数学表达不受影响
        guard let regex = try? NSRegularExpression(pattern: "</?[a-zA-Z][^<>]*>") else { return s }
        return regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s), withTemplate: "")
    }

    static func parse(text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                if parts.count == 2,
                   let start = parseTime(parts[0]),
                   let end = parseTime(parts[1]) {
                    var textLines: [String] = []
                    i += 1
                    while i < lines.count {
                        let t = lines[i].trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { break }
                        textLines.append(t)
                        i += 1
                    }
                    let joined = stripBasicTags(textLines.joined(separator: "\n"))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty {
                        cues.append(SubtitleCue(start: start, end: end, text: joined))
                    }
                }
            }
            i += 1
        }
        return cues
    }

    /// 解析 ASS/SSA 的 Dialogue 行（忽略特效标签）
    static func parseASS(text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Dialogue:") else { continue }
            let parts = trimmed.components(separatedBy: ",")
            guard parts.count >= 10,
                  let start = parseASSTime(parts[1]),
                  let end = parseASSTime(parts[2]) else { continue }
            var content = parts[9...].joined(separator: ",")
            content = stripASSTags(content)
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: content))
            }
        }
        return cues
    }

    private static func parseASSTime(_ s: String) -> Double? {
        // H:MM:SS.cc
        let parts = s.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]) else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard let sec = Double(secParts[0]) else { return nil }
        var centi = 0.0
        if secParts.count > 1, let c = Double(secParts[1]) {
            centi = c / 100.0
        }
        return h * 3600 + m * 60 + sec + centi
    }

    private static func stripASSTags(_ s: String) -> String {
        var result = s
        while let open = result.range(of: "{") {
            guard let close = result.range(of: "}", range: open.upperBound..<result.endIndex) else { break }
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }

    private static func parseTime(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // 去掉 VTT 里可能出现的 "align:start position:0%" 等标记
        if let sp = s.firstIndex(where: { $0 == " " }) {
            s = String(s[..<sp])
        }
        let comps = s.components(separatedBy: ":")
        guard comps.count >= 2, comps.count <= 3 else { return nil }

        var hours = 0.0, minutes = 0.0, seconds = 0.0
        if comps.count == 3 {
            guard let h = Double(comps[0]) else { return nil }
            hours = h
            guard let m = Double(comps[1]) else { return nil }
            minutes = m
            guard let sec = parseSeconds(comps[2]) else { return nil }
            seconds = sec
        } else {
            guard let m = Double(comps[0]) else { return nil }
            minutes = m
            guard let sec = parseSeconds(comps[1]) else { return nil }
            seconds = sec
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func parseSeconds(_ raw: String) -> Double? {
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: ",."))
        guard let sec = Double(parts[0]) else { return nil }
        var millis = 0.0
        if parts.count > 1, !parts[1].isEmpty, let ms = Double(parts[1]) {
            let scale = pow(10.0, Double(parts[1].count))
            millis = ms / scale
        }
        return sec + millis
    }
}
