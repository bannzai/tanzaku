import Foundation
import Testing

@testable import TanzakuKit

// 一時的な計測。Issue #70 の時間の内訳を CI で見るためのもので、計測後に消す。
@Suite(.serialized)
struct MaskingTimingProbeTests {
  @Test
  func probe() {
    let secretName =
      #"(?i)(?<![A-Z0-9_\-])((?>[A-Z0-9_\-]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API[-_ ]?KEY|ACCESS[-_ ]?KEY|PRIVATE[-_ ]?KEY|CREDENTIAL|パスワード|トークン|API ?キー|秘密鍵|シークレット)[A-Z0-9_\-]*)["']?[ \t]*[:=：][ \t]*)"#
    let patterns: [(name: String, pattern: String)] = [
      ("pem", #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#),
      ("quoted", secretName + #"(["'])(?:\\[\s\S]|(?!\2)[^\\])*\2"#),
      ("unclosed", secretName + #"(["'])(?!\[REDACTED\])[\s\S]*"#),
      ("bare", secretName + #"(?!["']|\[REDACTED\])[^\s"'}]+"#),
      ("authorization", #"(?i)((?<![A-Z0-9_\-])authorization["']?[ \t]*[:=][ \t]*["']?)[^"'\n]+"#),
      ("bearer", #"(?i)(?<![A-Z0-9_\-])(bearer|basic)\s+[A-Za-z0-9\-._~+/]{16,}=*"#),
      ("url", #"://[^/\s:@]*:[^/\s@]+@"#),
      ("prefix", #"(?<![A-Za-z0-9_\-])(sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{35})"#),
      ("long", #"[A-Za-z0-9_\-+=]{32,}"#),
    ]
    let clock = ContinuousClock()
    for word in ["TOKEN", "password=", "TOKEN:\"", "APIキー", "bearer", "authorization", "sk-", "ghp_", "://dummy:", "dummy0123456789"] {
      for count in [10_000, 20_000] {
        let text = String(repeating: word, count: count)
        let total = clock.measure {
          _ = snippetTextMaskingSecrets(text: text)
        }
        let perPattern = patterns.map { pattern in
          let regex = try! NSRegularExpression(pattern: pattern.pattern)
          let elapsed = clock.measure {
            _ = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
          }
          return "\(pattern.name)=\(elapsed)"
        }
        let containsNumber = clock.measure {
          _ = text.contains(where: \.isNumber)
        }
        print("PROBE \(word) x\(count) total=\(total) \(perPattern.joined(separator: " ")) containsNumber=\(containsNumber)")
      }
    }
  }
}
