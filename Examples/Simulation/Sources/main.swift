import Foundation
import IdentityFlowCore
import IdentityFlowDemoSupport

print("SIMULATION ONLY — no identity verification is performed")
let client = VerificationClient(provider: ScriptedProvider(scenario: .approved))
let result = try await client.run(
    session: VerificationSession(id: "demo", token: "synthetic", expiresAt: Date().addingTimeInterval(60)),
    consent: Consent(disclosureVersion: "sample-v1"),
    evidence: SyntheticEvidenceSource()
)
print(result)
