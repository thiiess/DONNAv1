import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var isOnboardingComplete: Bool = false
}
