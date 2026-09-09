import UIKit
import IdentityFlowCore
import IdentityFlowDemoSupport

/// Sample-host UI only. It deliberately never requests camera or identity information.
@MainActor
final class SimulationViewController: UIViewController {
    private let scenarios = UISegmentedControl(items: ["Approve", "Reject", "Pending", "Failure"])
    private let consent = UISwitch()
    private let start = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let status = UILabel()
    private var runTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "IdentityFlow"
        let titleLabel = label("Try the identity flow", style: .largeTitle)
        titleLabel.accessibilityTraits = .header
        let disclosure = label("SIMULATION ONLY\nNo identity verification is performed. This sample uses synthetic data. No photos, documents or credentials are requested or uploaded.", style: .body)
        let consentLabel = label("I agree to run the synthetic demo (sample disclosure v1).", style: .body)
        consent.accessibilityLabel = "Agree to synthetic demo"
        consent.setContentHuggingPriority(.required, for: .horizontal)
        consent.setContentCompressionResistancePriority(.required, for: .horizontal)
        consent.addTarget(self, action: #selector(consentChanged), for: .valueChanged)
        let consentRow = UIStackView(arrangedSubviews: [consentLabel, consent])
        consentRow.spacing = 16
        consentRow.alignment = .center
        scenarios.selectedSegmentIndex = 0
        scenarios.accessibilityLabel = "Simulated outcome"
        start.configuration = .filled()
        start.setTitle("Start simulation", for: .normal)
        start.addTarget(self, action: #selector(startSimulation), for: .touchUpInside)
        cancel.configuration = .bordered()
        cancel.setTitle("Cancel simulation", for: .normal)
        cancel.addTarget(self, action: #selector(cancelSimulation), for: .touchUpInside)
        cancel.isHidden = true
        start.isEnabled = false
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.text = "Choose an outcome and accept the sample disclosure to begin."
        status.accessibilityIdentifier = "simulationStatus"
        let stack = UIStackView(arrangedSubviews: [titleLabel, disclosure, label("Simulated outcome", style: .headline), scenarios, consentRow, start, cancel, status])
        stack.axis = .vertical
        stack.spacing = 24
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(cancelSimulation), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        runTask?.cancel()
    }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    @objc private func consentChanged() { start.isEnabled = consent.isOn && runTask == nil }

    @objc private func cancelSimulation() { runTask?.cancel() }

    @objc private func startSimulation() {
        guard runTask == nil, consent.isOn else { return }
        let options: [ScriptedProvider.Scenario] = [.approved, .rejected, .pending, .failure]
        let client = VerificationClient(provider: PacedSimulationProvider(scenario: options[scenarios.selectedSegmentIndex]))
        let (stream, continuation) = AsyncStream<VerificationProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        start.isEnabled = false
        consent.isEnabled = false
        scenarios.isEnabled = false
        cancel.isHidden = false
        status.text = "Starting simulation…"
        runTask = Task { [weak self] in
            let progressTask = Task { [weak self] in
                for await progress in stream { self?.status.text = Self.message(for: progress) }
            }
            let message: String
            do {
                let result = try await client.run(
                    session: .init(id: UUID().uuidString, token: "synthetic-demo-token", expiresAt: Date().addingTimeInterval(60)),
                    consent: .init(disclosureVersion: "sample-v1"),
                    evidence: SyntheticEvidenceSource(), progress: continuation
                )
                switch result {
                case .approved: message = "Simulated approval. No identity was verified."
                case .rejected: message = "Simulated rejection. No identity was evaluated."
                case .pending: message = "Simulated pending result. No real server is processing this demo."
                case .cancelled: message = "Simulation cancelled. Synthetic evidence was cleared."
                }
            } catch {
                message = "Simulated technical failure. Synthetic evidence was cleared. You can try again."
            }
            continuation.finish()
            await progressTask.value
            guard let self else { return }
            self.status.text = message
            self.runTask = nil
            self.consent.isEnabled = true
            self.scenarios.isEnabled = true
            self.cancel.isHidden = true
            self.start.isEnabled = self.consent.isOn
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private static func message(for progress: VerificationProgress) -> String {
        switch progress {
        case .consent: "Acknowledging sample disclosure…"
        case .capture(let side): "Preparing synthetic \(side.rawValue) evidence…"
        case .upload(let side): "Simulating \(side.rawValue) transfer locally…"
        case .submit: "Simulating submission…"
        case .awaitDecision: "Waiting for simulated outcome…"
        case .finished: "Finishing simulation…"
        }
    }
}

/// Adds cancellable delays so the user can observe and interrupt the local simulation.
private struct PacedSimulationProvider: VerificationProvider {
    let provider: ScriptedProvider
    init(scenario: ScriptedProvider.Scenario) { provider = ScriptedProvider(scenario: scenario) }
    private func pause() async throws { try await Task.sleep(for: .milliseconds(700)) }
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async throws {
        try await pause()
        await provider.acknowledgeConsent(consent, session: session)
    }
    func upload(_ evidence: Evidence, session: VerificationSession) async throws {
        try await pause()
        try await provider.upload(evidence, session: session)
    }
    func submit(session: VerificationSession, idempotencyKey: UUID) async throws {
        try await pause()
        await provider.submit(session: session, idempotencyKey: idempotencyKey)
    }
    func decision(session: VerificationSession) async throws -> VerificationOutcome {
        try await pause()
        return try await provider.decision(session: session)
    }
    func cancel(session: VerificationSession) async { await provider.cancel(session: session) }
}
