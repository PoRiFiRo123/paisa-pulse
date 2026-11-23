import Foundation

/// Small NSRegularExpression wrapper with JS-like helpers.
struct Rx {
  let re: NSRegularExpression
  init(_ pattern: String, caseInsensitive: Bool = true) {
    re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
  }
  private func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }
  func test(_ s: String) -> Bool { re.firstMatch(in: s, range: range(s)) != nil }
  /// Groups of the first match ("" for groups that didn't take part); index 0 is the whole match.
  func first(_ s: String) -> [String]? {
    guard let m = re.firstMatch(in: s, range: range(s)) else { return nil }
    return groups(m, s)
  }
  func firstRange(_ s: String) -> NSRange? { re.firstMatch(in: s, range: range(s))?.range }
  func all(_ s: String) -> [[String]] { re.matches(in: s, range: range(s)).map { groups($0, s) } }
  func replace(_ s: String, with t: String) -> String {
    re.stringByReplacingMatches(in: s, range: range(s), withTemplate: NSRegularExpression.escapedTemplate(for: t))
  }
  func replace(_ s: String, _ f: ([String]) -> String) -> String {
    let ns = s as NSString
    var out = ""; var last = 0
    for m in re.matches(in: s, range: range(s)) {
      out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
      out += f(groups(m, s))
      last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
  }
  func split(_ s: String) -> [String] {
    let ns = s as NSString
    var parts: [String] = []; var last = 0
    for m in re.matches(in: s, range: range(s)) {
      parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
      last = m.range.location + m.range.length
    }
    parts.append(ns.substring(from: last))
    return parts
  }
  private func groups(_ m: NSTextCheckingResult, _ s: String) -> [String] {
    let ns = s as NSString
    return (0..<m.numberOfRanges).map { i in
      let r = m.range(at: i)
      return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
  }
}
