//
//  BetaBuildDetection.swift
//  Apex
//
//  Detects TestFlight installs so Release builds can unlock Apex Pro for beta
//  testers without a purchase. App Store retail installs are not affected — they
//  are re-signed without the `beta-reports-active` entitlement.
//
//  Result is computed once at first use — reading `embedded.mobileprovision` on
//  every `isPremium` check was freezing the UI across the app.
//

import Foundation

enum BetaBuildDetection {
    /// True when the app was installed via TestFlight (internal or external).
    static let isTestFlight: Bool = {
        hasTestFlightEntitlement || hasSandboxReceipt
    }()

    /// TestFlight provisioning profiles include `beta-reports-active`.
    private static let hasTestFlightEntitlement: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let provision = String(data: data, encoding: .isoLatin1)
        else { return false }
        return provision.contains("beta-reports-active")
    }()

    /// Fallback: TestFlight receipt path differs from App Store retail.
    private static let hasSandboxReceipt: Bool = {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }()
}
