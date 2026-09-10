import Foundation

/// Bounds cleanup only after the app has approved termination, including any
/// confirmation needed for a recording or unfinished meeting.
@MainActor
final class ApplicationTerminationCoordinator {
    private let waitForTimeout: @MainActor () async throws -> Void
    private var cleanupTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completion: (@MainActor () -> Void)?
    private(set) var hasStarted = false

    init(
        waitForTimeout: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .seconds(10))
        }
    ) {
        self.waitForTimeout = waitForTimeout
    }

    /// A repeated quit neither starts cleanup again nor extends its deadline.
    @discardableResult
    func beginShutdown(
        cleanup: @escaping @MainActor () async -> Void,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        self.completion = completion

        cleanupTask = Task { @MainActor [weak self] in
            await cleanup()
            self?.finish(timedOut: false)
        }
        let waitForTimeout = self.waitForTimeout
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                try await waitForTimeout()
                self?.finish(timedOut: true)
            } catch {
                // Successful cleanup cancels the deadline task.
            }
        }
        return true
    }

    private func finish(timedOut: Bool) {
        guard let completion else { return }
        self.completion = nil
        cleanupTask?.cancel()
        timeoutTask?.cancel()
        cleanupTask = nil
        timeoutTask = nil
        if timedOut {
            fputs("[muesli-native] graceful shutdown exceeded 10 seconds; completing approved quit\n", stderr)
        }
        // Do not await the losing task: a CloudKit or model callback may ignore
        // cancellation. AppKit receives exactly one termination reply either way.
        completion()
    }
}
