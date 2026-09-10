import UIKit
import IdentityFlowCore
import IdentityFlowDemoSupport
import IdentityFlowSecurity
import IdentityFlowCapture

/// Sample-host UI only. It deliberately never requests camera or identity information.
@MainActor
final class SimulationViewController: UIViewController {
    private let scenarios = UISegmentedControl(items: ["Approve", "Reject", "Pending", "Failure"])
    private let consent = UISwitch()
    private let start = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let status = UILabel()
    private let retry = UIButton(type: .system)
    private let privacyCover = UIView()
    private let vault = EvidenceVault.shared
    private var storageReady = false
    private var lifecycleGeneration = UUID()
    private var recoveryClient: VerificationClient?
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
        retry.configuration = .bordered()
        retry.setTitle("Retry storage", for: .normal)
        retry.addTarget(self, action: #selector(retryStorage), for: .touchUpInside)
        retry.isHidden = true
        cancel.isHidden = true
        start.isEnabled = false
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.text = "Choose an outcome and accept the sample disclosure to begin."
        status.accessibilityIdentifier = "simulationStatus"
        let stack = UIStackView(arrangedSubviews: [titleLabel, disclosure, label("Simulated outcome", style: .headline), scenarios, consentRow, start, cancel, retry, status])
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
        privacyCover.backgroundColor = .systemBackground
        privacyCover.frame = view.bounds
        privacyCover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        privacyCover.isAccessibilityElement = true
        privacyCover.accessibilityLabel = "Simulation paused"
        view.addSubview(privacyCover)
        for event in [UIApplication.willResignActiveNotification, UIApplication.protectedDataWillBecomeUnavailableNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(suspendStorage), name: event, object: nil)
        }
        for event in [UIApplication.didBecomeActiveNotification, UIApplication.protectedDataDidBecomeAvailableNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(activateStorage), name: event, object: nil)
        }
        activateStorage()
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

    private func updateButtons() {
        start.isEnabled = consent.isOn && storageReady && runTask == nil && recoveryClient == nil
        retry.isHidden = storageReady && recoveryClient == nil
        retry.isEnabled = runTask == nil && UIApplication.shared.applicationState == .active
        retry.setTitle(recoveryClient == nil ? "Retry storage" : "Retry cleanup", for: .normal)
    }

    @objc private func consentChanged() { updateButtons() }

    @objc private func suspendStorage() {
        // Synchronous gate closes before returning from the lifecycle notification.
        vault.leaveForeground()
        lifecycleGeneration = UUID()
        storageReady = false
        privacyCover.isHidden = false
        runTask?.cancel()
        updateButtons()
    }

    @objc private func activateStorage() {
        guard UIApplication.shared.applicationState == .active,
              UIApplication.shared.isProtectedDataAvailable else { return }
        let generation = UUID()
        lifecycleGeneration = generation
        let permit = vault.foregroundPermit() // Captured before scheduling asynchronous activation.
        Task { [weak self, vault] in
            do {
                try await vault.enterForeground(permit)
                guard let self, self.lifecycleGeneration == generation else { return }
                self.storageReady = true
                self.privacyCover.isHidden = true
                self.updateButtons()
            } catch {
                guard let self, self.lifecycleGeneration == generation else { return }
                self.storageReady = false
                self.privacyCover.isHidden = true // Show the recovery action while the app is active.
                self.status.text = "Local storage is unavailable. Unlock the device and retry."
                self.updateButtons()
            }
        }
    }

    @objc private func retryStorage() {
        guard runTask == nil else { return }
        guard let client = recoveryClient else { activateStorage(); return }
        runTask = Task { [weak self] in
            let message: String
            do { message = Self.message(for: try await client.retryCleanup()) }
            catch VerificationError.cleanupRequired { message = "Cleanup is incomplete. Unlock the device and tap Retry cleanup." }
            catch { message = "Simulated technical failure. Synthetic evidence was cleared. You can try again." }
            let requiresCleanup = await client.requiresCleanup
            guard let self else { return }
            self.recoveryClient = requiresCleanup ? client : nil
            self.status.text = message
            self.runTask = nil
            self.updateButtons()
        }
        updateButtons()
    }

    @objc private func cancelSimulation() { runTask?.cancel() }

    @objc private func startSimulation() {
        guard runTask == nil, consent.isOn, storageReady, recoveryClient == nil else { return }
        let options: [ScriptedProvider.Scenario] = [.approved, .rejected, .pending, .failure]
        let client = VerificationClient(provider: PacedSimulationProvider(scenario: options[scenarios.selectedSegmentIndex]))
        let (stream, continuation) = AsyncStream<VerificationProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        start.isEnabled = false
        consent.isEnabled = false
        scenarios.isEnabled = false
        cancel.isHidden = false
        status.text = "Starting simulation…"
        let session = VerificationSession(id: UUID().uuidString, token: "synthetic-demo-token", expiresAt: Date().addingTimeInterval(60))
        let source = VaultEvidenceSource(sessionID: session.id, expiresAt: session.expiresAt,
                                         capture: SyntheticCardCapture(), vault: vault)
        runTask = Task { [weak self] in
            let progressTask = Task { [weak self] in
                for await progress in stream { self?.status.text = Self.message(for: progress) }
            }
            let message: String
            do {
                let result = try await client.run(
                    session: session,
                    consent: .init(disclosureVersion: "sample-v1"),
                    evidence: source, progress: continuation
                )
                message = Self.message(for: result)
            } catch VerificationError.cleanupRequired {
                self?.recoveryClient = client
                message = "Cleanup is incomplete. Unlock the device and tap Retry cleanup."
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
            self.updateButtons()
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private static func message(for result: VerificationOutcome) -> String {
        switch result {
        case .approved: "Simulated approval. No identity was verified."
        case .rejected: "Simulated rejection. No identity was evaluated."
        case .pending: "Simulated pending result. No real server is processing this demo."
        case .cancelled: "Simulation cancelled. Synthetic evidence was cleared."
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

/// Generates a small JPEG containing only a synthetic label; never accesses camera or photo library.
@MainActor
private final class SyntheticCardCapture: ConfirmedImageCapture {
    private var cancelled = false
    func confirmedJPEG(for side: DocumentSide) async throws -> Data {
        guard !cancelled else { throw CancellationError() }
        try Task.checkCancellation()
        let generated = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            let text = "SIMULATION ONLY\nSynthetic \(side.rawValue)\nNot an identity document"
            (text as NSString).draw(in: CGRect(x: 20, y: 30, width: 280, height: 140), withAttributes: [
                .font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black
            ])
        }
        let normalized = try await ImageNormalizer.shared.normalize(generated)
        guard !cancelled else { throw CancellationError() }
        return normalized.jpeg
    }
    func cancel() { cancelled = true }
}
