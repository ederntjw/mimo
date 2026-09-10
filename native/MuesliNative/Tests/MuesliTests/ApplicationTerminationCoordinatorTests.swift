import Testing
@testable import MuesliNativeApp

@MainActor
private final class TerminationTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@Suite("Application termination coordinator")
@MainActor
struct ApplicationTerminationCoordinatorTests {
    @Test("completed cleanup replies without waiting for the deadline")
    func completedCleanupReplies() async {
        let deadline = TerminationTestGate()
        let reply = TerminationTestGate()
        var cleanupCount = 0
        var replyCount = 0
        let coordinator = ApplicationTerminationCoordinator(waitForTimeout: { await deadline.wait() })

        #expect(!coordinator.hasStarted)
        let didStart = coordinator.beginShutdown(cleanup: {
            cleanupCount += 1
        }, completion: {
            replyCount += 1
            reply.open()
        })
        #expect(didStart)

        await reply.wait()
        #expect(cleanupCount == 1)
        #expect(replyCount == 1)
        #expect(coordinator.hasStarted)
        deadline.open()
    }

    @Test("deadline replies even when cleanup ignores cancellation")
    func deadlineDoesNotAwaitUncooperativeCleanup() async {
        let cleanupStarted = TerminationTestGate()
        let releaseCleanup = TerminationTestGate()
        let cleanupFinished = TerminationTestGate()
        let deadline = TerminationTestGate()
        let reply = TerminationTestGate()
        var didFinishCleanup = false
        var replyCount = 0
        let coordinator = ApplicationTerminationCoordinator(waitForTimeout: { await deadline.wait() })

        coordinator.beginShutdown(cleanup: {
            cleanupStarted.open()
            await releaseCleanup.wait()
            didFinishCleanup = true
            cleanupFinished.open()
        }, completion: {
            replyCount += 1
            reply.open()
        })

        await cleanupStarted.wait()
        deadline.open()
        await reply.wait()
        #expect(!didFinishCleanup)
        #expect(replyCount == 1)

        releaseCleanup.open()
        await cleanupFinished.wait()
        await Task.yield()
        #expect(didFinishCleanup)
        #expect(replyCount == 1)
    }

    @Test("repeated quit starts one cleanup and keeps the original deadline")
    func repeatedQuitKeepsOriginalDeadline() async {
        let cleanupStarted = TerminationTestGate()
        let releaseCleanup = TerminationTestGate()
        let deadlineStarted = TerminationTestGate()
        let deadline = TerminationTestGate()
        let reply = TerminationTestGate()
        var deadlineCount = 0
        var cleanupCount = 0
        var replyCount = 0
        let coordinator = ApplicationTerminationCoordinator(waitForTimeout: {
            deadlineCount += 1
            deadlineStarted.open()
            await deadline.wait()
        })

        coordinator.beginShutdown(cleanup: {
            cleanupCount += 1
            cleanupStarted.open()
            await releaseCleanup.wait()
        }, completion: {
            replyCount += 1
            reply.open()
        })
        await cleanupStarted.wait()
        await deadlineStarted.wait()
        let didRestart = coordinator.beginShutdown(cleanup: {
            cleanupCount += 1
        }, completion: {
            replyCount += 1
        })
        #expect(!didRestart)

        deadline.open()
        await reply.wait()
        #expect(deadlineCount == 1)
        #expect(cleanupCount == 1)
        #expect(replyCount == 1)
        let didRestartAfterReply = coordinator.beginShutdown(cleanup: {}, completion: { replyCount += 1 })
        #expect(!didRestartAfterReply)
        #expect(replyCount == 1)
        releaseCleanup.open()
    }

    @Test("a late deadline after cleanup cannot send a second reply")
    func lateDeadlineRepliesOnce() async {
        let cleanup = TerminationTestGate()
        let deadlineStarted = TerminationTestGate()
        let deadline = TerminationTestGate()
        let deadlineFinished = TerminationTestGate()
        let reply = TerminationTestGate()
        var replyCount = 0
        let coordinator = ApplicationTerminationCoordinator(waitForTimeout: {
            deadlineStarted.open()
            // Deliberately ignore cancellation to exercise the reply-once gate.
            await deadline.wait()
            deadlineFinished.open()
        })

        coordinator.beginShutdown(cleanup: { await cleanup.wait() }, completion: {
            replyCount += 1
            reply.open()
        })
        await deadlineStarted.wait()
        cleanup.open()
        await reply.wait()
        deadline.open()
        await deadlineFinished.wait()
        await Task.yield()
        #expect(replyCount == 1)
    }
}
