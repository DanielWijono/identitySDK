import SwiftUI

@main
struct SimulationApp: App {
    var body: some Scene {
        WindowGroup { SimulationScreen().ignoresSafeArea() }
    }
}

/// Both hosts exercise the same UIKit implementation.
private struct SimulationScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: SimulationViewController())
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
