import Foundation
import LoanPayDomain

/// Reads the flag inventory bundled at `flags.json`.
///
/// WHY a bundled file and not remote config: this app's flags gate code
/// paths per release (trunk-based development), and the inventory ships
/// with the binary so a release's behavior is fully described by its tag.
/// A real deployment would layer remote kill-switch delivery on top; the
/// seam (`FeatureFlags`) already allows it without touching call sites.
struct BundledFeatureFlags: FeatureFlags {
    private let values: [String: Bool]

    init(bundle: Bundle = .main) {
        // LANG: decoding happens once, eagerly, in init — flags are read on
        // hot paths (every list render may consult them) and must be a
        // dictionary hit, not repeated disk I/O.
        struct FlagEntry: Decodable {
            let enabled: Bool
        }
        guard let url = bundle.url(forResource: "flags", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: FlagEntry].self, from: data) else {
            // WHY fail-closed is wrong here: shipping a build whose flag
            // file is broken should degrade to DEFAULTS, not to "everything
            // off" (which would kill payments). Defaults live on the enum.
            self.values = [:]
            return
        }
        self.values = entries.mapValues(\.enabled)
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        values[flag.rawValue] ?? defaultValue(for: flag)
    }

    private func defaultValue(for flag: FeatureFlag) -> Bool {
        switch flag {
        // FINTECH: the kill switch defaults ON (payments work) — its job is
        // to be *turned off* in an incident, not to require turning on.
        case .paymentsEnabled: true
        case .search: false
        }
    }
}
