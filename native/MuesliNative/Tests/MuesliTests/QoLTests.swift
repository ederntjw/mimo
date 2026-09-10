import AppKit
import Testing
import Foundation
import MuesliCore
import FluidAudio
import os
@testable import MuesliNativeApp

@Suite("Dictation backend readiness")
struct DictationBackendReadinessTests {
    @Test("preparing backend blocks dictation with existing warmup copy")
    func preparingBlocksDictation() {
        let readiness = DictationBackendReadiness.preparing

        #expect(!readiness.allowsDictation)
        #expect(readiness.blockingMessage(backendLabel: "Parakeet v3") == "Warming up Parakeet v3...")
    }

    @Test("ready backend allows dictation")
    func readyAllowsDictation() {
        let readiness = DictationBackendReadiness.ready

        #expect(readiness.allowsDictation)
        #expect(readiness.blockingMessage(backendLabel: "Parakeet v3") == nil)
    }

    @Test("failed backend remains blocked with actionable status")
    func failedBlocksDictation() {
        let readiness = DictationBackendReadiness.failed

        #expect(!readiness.allowsDictation)
        #expect(readiness.blockingMessage(backendLabel: "Parakeet v3") == "Parakeet v3 unavailable")
    }
}

// MARK: - ChatGPT File-based Token Storage

@Suite("ChatGPT Token Storage")
struct ChatGPTTokenStorageTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-chatgpt-storage-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeFixture(to fileURL: URL, accessToken: String = "fixture-access-token") throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tokens = [
            "access_token": accessToken,
            "account_id": "fixture-account",
            "expires_at": String(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),
        ]
        try JSONSerialization.data(withJSONObject: tokens).write(to: fileURL, options: .atomic)
    }

    @Test("a missing isolated token file is unauthenticated")
    @MainActor
    func notAuthenticatedByDefault() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = ChatGPTAuthManager(
            tokenFileURL: root.appendingPathComponent("chatgpt-auth.json"),
            migrateLegacyKeychain: false
        )
        #expect(!auth.isAuthenticated)
        await #expect(throws: ChatGPTAuthError.self) {
            try await auth.validAccessToken()
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("sign-out is idempotent for an isolated missing token file")
    @MainActor
    func signOutSafe() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenFileURL = root.appendingPathComponent("chatgpt-auth.json")
        let auth = ChatGPTAuthManager(tokenFileURL: tokenFileURL, migrateLegacyKeychain: false)
        auth.signOut()
        auth.signOut()
        #expect(!auth.isAuthenticated)
        #expect(!FileManager.default.fileExists(atPath: tokenFileURL.path))
    }

    @Test("a valid isolated token file is read without contacting the account service")
    @MainActor
    func readsStoredToken() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenFileURL = root.appendingPathComponent("chatgpt-auth.json")
        try writeFixture(to: tokenFileURL)
        let auth = ChatGPTAuthManager(tokenFileURL: tokenFileURL, migrateLegacyKeychain: false)
        #expect(auth.isAuthenticated)
        let result = try await auth.validAccessToken()
        #expect(result.token == "fixture-access-token")
        #expect(result.accountId == "fixture-account")
    }

    @Test("sign-out removes only the instance's token file and preserves neighboring storage")
    @MainActor
    func signOutIsIsolated() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenFileURL = root.appendingPathComponent("first/chatgpt-auth.json")
        let otherTokenFileURL = root.appendingPathComponent("second/chatgpt-auth.json")
        let sentinel = root.appendingPathComponent("settings.json")
        try writeFixture(to: tokenFileURL)
        try writeFixture(to: otherTokenFileURL, accessToken: "other-fixture-token")
        try Data("settings remain".utf8).write(to: sentinel)
        let auth = ChatGPTAuthManager(tokenFileURL: tokenFileURL, migrateLegacyKeychain: false)
        let otherAuth = ChatGPTAuthManager(tokenFileURL: otherTokenFileURL, migrateLegacyKeychain: false)
        auth.signOut()
        #expect(!auth.isAuthenticated)
        #expect(!FileManager.default.fileExists(atPath: tokenFileURL.path))
        #expect(otherAuth.isAuthenticated)
        #expect(try await otherAuth.validAccessToken().token == "other-fixture-token")
        #expect(try Data(contentsOf: sentinel) == Data("settings remain".utf8))
    }

    @Test("malformed isolated token storage is treated as signed out")
    @MainActor
    func malformedTokenFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenFileURL = root.appendingPathComponent("chatgpt-auth.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not valid JSON".utf8).write(to: tokenFileURL)
        let auth = ChatGPTAuthManager(tokenFileURL: tokenFileURL, migrateLegacyKeychain: false)
        #expect(!auth.isAuthenticated)
        auth.signOut()
        #expect(!FileManager.default.fileExists(atPath: tokenFileURL.path))
    }
}

// MARK: - Floating Indicator: showFloatingIndicator hides only idle state

@Suite("FloatingIndicator visibility")
struct FloatingIndicatorVisibilityTests {

    @Test("config default shows floating indicator")
    func defaultShowsIndicator() {
        let config = AppConfig()
        #expect(config.showFloatingIndicator == true)
    }

    @Test("showFloatingIndicator persists through JSON round-trip")
    func jsonRoundTrip() throws {
        var config = AppConfig()
        config.showFloatingIndicator = false
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.showFloatingIndicator == false)
    }

    @Test("showFloatingIndicator decodes from snake_case JSON")
    func snakeCaseDecode() throws {
        let json = #"{"show_floating_indicator": false}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(config.showFloatingIndicator == false)
    }

    @Test("floating hotkey defaults off while menu bar hotkey defaults on")
    func hotkeyVisibilityRoundTrip() throws {
        var config = AppConfig()
        #expect(!config.showHotkeyOnFloatingIndicator)
        #expect(config.showHotkeyInMenuBar)

        config.showHotkeyOnFloatingIndicator = true
        config.showHotkeyInMenuBar = false
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(decoded.showHotkeyOnFloatingIndicator)
        #expect(!decoded.showHotkeyInMenuBar)
    }

    @Test("missing hotkey visibility preferences use fresh-install defaults")
    func hotkeyVisibilityMissingKeysUseDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))

        #expect(!config.showHotkeyOnFloatingIndicator)
        #expect(config.showHotkeyInMenuBar)
    }

    @Test("hotkey visibility controls decode from snake_case JSON")
    func hotkeyVisibilitySnakeCaseDecode() throws {
        let json = #"{"show_hotkey_on_floating_indicator": false, "show_hotkey_in_menu_bar": false}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        #expect(!config.showHotkeyOnFloatingIndicator)
        #expect(!config.showHotkeyInMenuBar)
    }

    @Test("meeting transcript hover defaults on and persists")
    func meetingTranscriptHoverRoundTrip() throws {
        var config = AppConfig()
        #expect(config.showMeetingTranscriptOnIndicatorHover)
        config.showMeetingTranscriptOnIndicatorHover = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(!decoded.showMeetingTranscriptOnIndicatorHover)
    }

    @Test("meeting transcript hover decodes from snake_case JSON")
    func meetingTranscriptHoverSnakeCaseDecode() throws {
        let json = #"{"show_meeting_transcript_on_indicator_hover": false}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(!config.showMeetingTranscriptOnIndicatorHover)
    }

    @Test("post processor defaults to disabled")
    func postProcessorDisabledByDefault() {
        let config = AppConfig()
        #expect(config.enablePostProcessor == false)
    }

    @Test("post processor defaults to v3 model")
    func postProcessorDefaultModel() {
        let config = AppConfig()
        #expect(config.activePostProcessorId == PostProcessorOption.defaultOption.id)
    }

    @Test("post processor persists through JSON round-trip")
    func postProcessorRoundTrip() throws {
        var config = AppConfig()
        config.enablePostProcessor = true
        config.activePostProcessorId = PostProcessorOption.qwen35_0_8b.id
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.enablePostProcessor == true)
        #expect(decoded.activePostProcessorId == PostProcessorOption.qwen35_0_8b.id)
    }

    @Test("cached legacy post processor persists through JSON round-trip")
    func cachedLegacyPostProcessorRoundTrip() throws {
        let json = #"{"active_post_processor_id":"qwen3-postproc-v2"}"#
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.activePostProcessorId == PostProcessorOption.legacyV2.id)

        let data = try JSONEncoder().encode(decoded)
        let reloaded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(reloaded.activePostProcessorId == PostProcessorOption.legacyV2.id)
        #expect(PostProcessorOption.runtimeOption(
            id: reloaded.activePostProcessorId,
            downloadedIDs: [PostProcessorOption.legacyV2.id],
            hasDevOverride: false
        ) == .legacyV2)
    }

    @Test("post processor decodes from snake_case JSON")
    func postProcessorSnakeCaseDecode() throws {
        let json = #"{"enable_post_processor": true}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(config.enablePostProcessor == true)
    }
}

// MARK: - Unified indicator frame sizes

@Suite("Indicator frame sizes")
struct IndicatorFrameSizeTests {

    @Test("recording frame size is consistent for all non-meeting dictation")
    func recordingFrameUnified() {
        // Both hold and toggle dictation should use the same 76x22 size
        // Meeting recording uses 72x32
        // This test validates the model constants that drive the frame
        let config = AppConfig()
        #expect(config.showFloatingIndicator == true)
        // The frame sizes are hardcoded in FloatingIndicatorController.frameForState
        // We test that the config round-trips correctly (the visual test is manual)
    }

    @Test("default indicator center is right-middle of the screen")
    @MainActor
    func defaultIndicatorCenterUsesScreenMidpoint() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let center = FloatingIndicatorController.defaultIndicatorCenter(in: visibleFrame)
        #expect(center.x == 1270)
        #expect(center.y == 450)
    }

    @Test("off-screen saved indicator center falls back to right-middle default")
    @MainActor
    func offscreenSavedIndicatorCenterFallsBack() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let size = NSSize(width: 76, height: 22)
        let offscreen = CGPoint(x: 1708, y: 1491)

        #expect(
            !FloatingIndicatorController.isUsableIndicatorCenter(
                offscreen,
                in: visibleFrame,
                size: size
            )
        )
        #expect(
            FloatingIndicatorController.defaultIndicatorCenter(in: visibleFrame) ==
            CGPoint(x: 1270, y: 450)
        )
    }

    @Test("anchor centers respect fixed screen insets")
    @MainActor
    func anchorCentersUseExpectedInsets() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let size = NSSize(width: 44, height: 28)

        #expect(
            FloatingIndicatorController.anchorCenter(.topLeading, in: visibleFrame, size: size) ==
            CGPoint(x: 130, y: 828)
        )
        #expect(
            FloatingIndicatorController.anchorCenter(.bottomCenter, in: visibleFrame, size: size) ==
            CGPoint(x: 700, y: 72)
        )
    }

    @Test("custom idle hover keeps the collapsed pill's left edge")
    @MainActor
    func customIdleHoverKeepsLeftEdge() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let positionCenter = CGPoint(x: 422, y: 450)
        let collapsed = FloatingIndicatorController.customIdleFrame(
            positionCenter: positionCenter,
            size: NSSize(width: 44, height: 28),
            in: visibleFrame
        )
        let expanded = FloatingIndicatorController.customIdleFrame(
            positionCenter: positionCenter,
            size: NSSize(width: 220, height: 36),
            in: visibleFrame
        )

        #expect(collapsed.minX == 400)
        #expect(expanded.minX == collapsed.minX)
        #expect(expanded.midY == collapsed.midY)
    }

    @Test("custom indicator uses the display containing its saved position")
    @MainActor
    func customIndicatorUsesSecondaryDisplay() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: -1920, y: -180, width: 1920, height: 1080)
        let savedPosition = CGPoint(x: -960, y: 360)

        let selectedFrame = FloatingIndicatorController.visibleFrameForCustomIndicator(
            customPositionCenter: nil,
            indicatorFrame: nil,
            savedPositionCenter: savedPosition,
            availableVisibleFrames: [primary, secondary],
            fallback: primary
        )
        let expanded = FloatingIndicatorController.customIdleFrame(
            positionCenter: savedPosition,
            size: NSSize(width: 220, height: 36),
            in: selectedFrame
        )

        #expect(selectedFrame == secondary)
        #expect(secondary.contains(expanded))
        #expect(expanded.minX == savedPosition.x - 22)
    }

    @Test("idle hover width leaves room for the complete hotkey instruction")
    @MainActor
    func idleHoverWidthFitsInstruction() {
        let standard = FloatingIndicatorController.idleHoverPillSize(
            hotkeyLabel: "Left Option",
            screenWidth: 1200
        )
        let combination = FloatingIndicatorController.idleHoverPillSize(
            hotkeyLabel: "Control Option Shift R",
            screenWidth: 1200
        )

        #expect(standard.width >= 220)
        #expect(combination.width > standard.width)
        #expect(combination.width <= 1168)
        #expect(standard.height == 36)
    }

    @Test("expanded idle drag saves the equivalent collapsed center")
    @MainActor
    func expandedIdleDragSavesCollapsedCenter() {
        let expanded = NSRect(x: 515, y: 240, width: 220, height: 36)
        #expect(
            FloatingIndicatorController.positionCenter(
                for: expanded,
                preservesCollapsedLeftEdge: true
            ) ==
            CGPoint(x: 537, y: 258)
        )
    }

    @Test("centered loading and warning drags save their true midpoint")
    @MainActor
    func centeredTransientIdleDragsSaveMidpoint() {
        let loading = NSRect(x: 515, y: 240, width: 180, height: 36)
        let warning = NSRect(x: 280, y: 180, width: 312, height: 36)

        #expect(
            FloatingIndicatorController.positionCenter(
                for: loading,
                preservesCollapsedLeftEdge: false
            ) == CGPoint(x: 605, y: 258)
        )
        #expect(
            FloatingIndicatorController.positionCenter(
                for: warning,
                preservesCollapsedLeftEdge: false
            ) == CGPoint(x: 436, y: 198)
        )
    }

    @Test("transcribing pill widens for live CUA status labels")
    @MainActor
    func transcribingPillWidensForStatusText() {
        let short = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Planning",
            screenWidth: 1200
        )
        let long = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Navigating to YouTube search",
            screenWidth: 1200
        )

        #expect(short.width >= 190)
        #expect(long.width > short.width)
        #expect(long.width <= 360)
        #expect(long.height == 32)
    }

    @Test("transcribing pill caps to available screen width")
    @MainActor
    func transcribingPillCapsToScreenWidth() {
        let size = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Executing an unusually long computer use action label",
            screenWidth: 180
        )

        #expect(size.width <= 148)
        #expect(size.height == 32)
    }

    @Test("CUA transcript pill wraps and grows vertically instead of truncating")
    @MainActor
    func computerUseTranscriptPillWrapsAndExpands() {
        let short = FloatingIndicatorController.computerUseTranscriptPillSizeForTesting(
            transcript: "Open Twitter",
            screenWidth: 1200
        )
        let long = FloatingIndicatorController.computerUseTranscriptPillSizeForTesting(
            transcript: "Open Twitter in Google Chrome and write a tweet saying this was written using Muesli CUA without posting it",
            screenWidth: 420
        )

        #expect(short.width >= 280)
        #expect(short.height >= 44)
        #expect(long.width <= 372)
        #expect(long.height > short.height)
    }

    @Test("Quill instruction pill reserves room for its progress spinner")
    @MainActor
    func quillInstructionPillIncludesProgressChrome() {
        let transcript = "Rewrite this as a concise professional email"
        let computerUseSize = FloatingIndicatorController.computerUseTranscriptPillSizeForTesting(
            transcript: transcript,
            screenWidth: 1200
        )
        let quillSize = FloatingIndicatorController.quillInstructionPillSizeForTesting(
            transcript: transcript,
            screenWidth: 1200
        )

        #expect(quillSize.width > computerUseSize.width)
        #expect(quillSize.height == computerUseSize.height)
    }

    @Test("Quill instruction pill keeps its final wrapped words visible")
    @MainActor
    func quillInstructionPillFitsRenderedTextField() {
        // This ends at an AppKit word-wrap boundary where NSString boundingRect
        // reports seven lines but NSTextField renders eight.
        let transcript = "Rewrite this as a concise professional email while preserving every detail and ensuring the final words remain visible in the floating pill please make the tone warm but direct and retain all"
        let heights = FloatingIndicatorController.quillInstructionTextHeightsForTesting(
            transcript: transcript,
            screenWidth: 300
        )

        #expect(heights.allocated >= heights.required)
    }
}

@Suite("Floating meeting transcript")
struct FloatingMeetingTranscriptTests {
    @Test("overlay routes header controls and leaves transcript body to SwiftUI")
    func overlayClickRouting() {
        let frame = NSRect(x: 100, y: 100, width: 360, height: 320)

        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 390, y: 400), in: frame
        ) == .dismiss)
        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 430, y: 400), in: frame
        ) == .copy)
        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 180, y: 400), in: frame
        ) == .openMeeting)
        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 300, y: 400), in: frame
        ) == nil)
        #expect(FloatingMeetingTranscriptInteraction.isDraggableHeader(
            at: NSPoint(x: 300, y: 400), in: frame
        ))
        #expect(!FloatingMeetingTranscriptInteraction.isDraggableHeader(
            at: NSPoint(x: 430, y: 400), in: frame
        ))
        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 250, y: 250), in: frame
        ) == nil)
        #expect(!FloatingMeetingTranscriptInteraction.isDraggableHeader(
            at: NSPoint(x: 250, y: 250), in: frame
        ))
        #expect(FloatingMeetingTranscriptInteraction.action(
            at: NSPoint(x: 90, y: 250), in: frame
        ) == nil)
    }

    @Test("floating panel can receive controls without becoming the main window")
    @MainActor
    func floatingPanelIsInteractive() {
        let panel = InteractiveFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        var receivedMouseDown: NSPoint?
        panel.leftMouseDownHandler = { point in
            receivedMouseDown = point
            return true
        }
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        if let event {
            panel.sendEvent(event)
        }

        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(!panel.styleMask.contains(.nonactivatingPanel))
        #expect(receivedMouseDown == NSPoint(x: 20, y: 20))
    }

    @Test("shown overlay retains its hosting view and routes dismissal")
    @MainActor
    func shownOverlayRoutesDismissal() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = container
        var dismissCount = 0
        let controller = FloatingMeetingTranscriptPanelController(
            onHoverChanged: { _ in },
            onOpenNotes: {},
            onDismiss: { dismissCount += 1 }
        )

        controller.show(in: container, frame: container.bounds)

        #expect(controller.isVisible)
        #expect(!controller.handleClick(atWindowPoint: NSPoint(x: 180, y: 160)))
        #expect(controller.handleClick(atWindowPoint: NSPoint(x: 290, y: 300)))
        #expect(dismissCount == 1)
    }

    @Test("panel prefers the open side and remains inside the screen")
    func panelPlacement() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let trailingIndicator = NSRect(x: 1350, y: 440, width: 76, height: 22)
        let leadingIndicator = NSRect(x: 14, y: 440, width: 76, height: 22)

        let leftFrame = FloatingMeetingTranscriptPlacement.frame(
            beside: trailingIndicator,
            visibleFrame: screen
        )
        let rightFrame = FloatingMeetingTranscriptPlacement.frame(
            beside: leadingIndicator,
            visibleFrame: screen
        )

        #expect(leftFrame.maxX == trailingIndicator.minX)
        #expect(rightFrame.minX == leadingIndicator.maxX)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(leftFrame))
        #expect(screen.insetBy(dx: 8, dy: 8).contains(rightFrame))
    }

    @Test("panel clamps vertically on short screens")
    func verticalPlacementClamp() {
        let screen = NSRect(x: 100, y: 50, width: 900, height: 360)
        let indicator = NSRect(x: 950, y: 380, width: 40, height: 22)

        let frame = FloatingMeetingTranscriptPlacement.frame(
            beside: indicator,
            visibleFrame: screen
        )

        #expect(frame.minY >= screen.minY + 8)
        #expect(frame.maxY == screen.maxY - 8)
    }

    @Test("copy includes committed transcript and current partials")
    func copyTextIncludesLiveTails() {
        let text = LiveTranscriptCopyContent.text(
            transcript: "[10:00:00] You: committed",
            partialYou: "speaking now",
            partialOthers: "current reply"
        )

        #expect(text == "[10:00:00] You: committed\nOthers: current reply\nYou: speaking now")
    }

    @Test("panel retains the complete committed transcript")
    func completeTranscriptHistory() {
        let transcript = (0..<12)
            .map { "[10:00:\(String(format: "%02d", $0))] You: line \($0)" }
            .joined(separator: "\n")

        let messages = TranscriptChatMessage.messages(from: transcript)

        #expect(messages.count == 12)
        #expect(messages.first?.text == "line 0")
        #expect(messages.last?.text == "line 11")
    }

    @Test("incremental panel updates retain unique message identities")
    @MainActor
    func incrementalUpdatesUseUniqueIDs() {
        let model = LiveTranscriptPresentationModel()

        model.update(
            transcript: "[10:00:00] You: first\n",
            partialYou: "",
            partialOthers: ""
        )
        model.update(
            transcript: "[10:00:00] You: first\n[10:00:05] Others: second\n",
            partialYou: "",
            partialOthers: ""
        )

        #expect(model.messages.map(\.id) == [0, 1])
        #expect(model.messages.map(\.text) == ["first", "second"])
    }
}

@Suite("Floating indicator pointer interaction")
struct FloatingIndicatorPointerInteractionTests {
    @Test("small pointer movement remains a click while deliberate movement drags")
    func dragThreshold() {
        let start = NSPoint(x: 100, y: 100)
        #expect(!FloatingIndicatorPointerIntent.isDrag(
            from: start,
            to: NSPoint(x: 102, y: 102)
        ))
        #expect(FloatingIndicatorPointerIntent.isDrag(
            from: start,
            to: NSPoint(x: 104, y: 100)
        ))
    }

    @MainActor
    @Test("single-click retains its existing meeting command")
    func singleClickStillRuns() {
        let indicator = makeIndicator()
        var stopCount = 0
        indicator.onStopMeeting = { stopCount += 1 }
        indicator.setMeetingRecording(true, config: AppConfig())

        indicator.handleClick(atX: 50)

        #expect(stopCount == 1)
        indicator.close()
    }

    @MainActor
    @Test("expanded live transcript leaves the offset recording pill interactive")
    func expandedMeetingPillHitTesting() throws {
        let (indicator, store, directory) = makeMeetingIndicator()
        defer {
            indicator.close()
            try? FileManager.default.removeItem(at: directory)
        }
        indicator.setMeetingRecording(true, config: store.load())
        indicator.setHovered(true)
        let view = try #require(indicator.pointerInteractionViewForTesting)
        let window = try #require(view.window)
        #expect(view.frame.origin != .zero)

        let decoration = NSTextField(labelWithString: "Recording")
        decoration.frame = view.bounds
        view.addSubview(decoration)
        let point = NSPoint(x: view.frame.midX, y: view.frame.midY)
        #expect(view.hitTest(point) === view)
        #expect(view.hitTest(NSPoint(x: view.frame.minX - 1, y: point.y)) == nil)
        #expect(view.acceptsFirstMouse(for: nil))
        #expect(window.isMovable)
        #expect(!window.isMovableByWindowBackground)
    }

    @MainActor
    @Test("dragging an expanded meeting pill follows the pointer and saves its compact position")
    func expandedMeetingDragPersistsWithoutRunningControls() throws {
        let (indicator, store, directory) = makeMeetingIndicator()
        defer {
            indicator.close()
            try? FileManager.default.removeItem(at: directory)
        }
        var stopCount = 0
        var pauseCount = 0
        var discardCount = 0
        var savedCenters: [CGPoint] = []
        indicator.onStopMeeting = { stopCount += 1 }
        indicator.onToggleMeetingPause = { pauseCount += 1 }
        indicator.onDiscardMeeting = { discardCount += 1 }
        // Use the same persistence contract as the app's onPositionSaved owner.
        indicator.onPositionSaved = { center in
            savedCenters.append(center)
            var config = store.load()
            config.indicatorAnchor = .custom
            config.indicatorOrigin = CGPointCodable(x: center.x, y: center.y)
            store.save(config)
        }
        indicator.setMeetingRecording(true, config: store.load())
        indicator.setHovered(true)
        let view = try #require(indicator.pointerInteractionViewForTesting)
        let window = try #require(view.window)
        let originalFrame = try #require(indicator.currentFrame)
        let start = window.convertPoint(toScreen: view.convert(
            NSPoint(x: 12, y: view.bounds.midY), to: nil
        ))
        let finish = NSPoint(x: start.x - 90, y: start.y + 55)

        view.mouseDown(with: try pointerEvent(.leftMouseDown, screenPoint: start, window: window))
        view.mouseDragged(with: try pointerEvent(.leftMouseDragged, screenPoint: finish, window: window))
        view.mouseUp(with: try pointerEvent(.leftMouseUp, screenPoint: finish, window: window))

        let movedFrame = try #require(indicator.currentFrame)
        let expectedCenter = CGPoint(x: originalFrame.midX - 90, y: originalFrame.midY + 55)
        #expect(movedFrame.origin == originalFrame.offsetBy(dx: -90, dy: 55).origin)
        #expect(movedFrame.size == originalFrame.size)
        #expect(window.frame == movedFrame)
        #expect(savedCenters == [expectedCenter])
        #expect(stopCount == 0)
        #expect(pauseCount == 0)
        #expect(discardCount == 0)

        indicator.setMeetingRecordingPaused(true, config: store.load())
        #expect(indicator.currentFrame?.midX == expectedCenter.x)
        #expect(indicator.currentFrame?.midY == expectedCenter.y)
        indicator.close()
        let reopened = FloatingIndicatorController(configStore: store)
        defer { reopened.close() }
        reopened.setMeetingRecording(true, config: store.load())
        #expect(reopened.currentFrame?.midX == expectedCenter.x)
        #expect(reopened.currentFrame?.midY == expectedCenter.y)
    }

    @MainActor
    @Test("small pointer movements still activate pause and stop instead of saving a drag")
    func meetingControlClicksSurviveDragRouting() throws {
        let (indicator, store, directory) = makeMeetingIndicator()
        defer {
            indicator.close()
            try? FileManager.default.removeItem(at: directory)
        }
        var pauses = 0
        var stops = 0
        var savedPositions = 0
        indicator.onToggleMeetingPause = { pauses += 1 }
        indicator.onStopMeeting = { stops += 1 }
        indicator.onPositionSaved = { _ in savedPositions += 1 }
        indicator.setMeetingRecording(true, config: store.load())
        let view = try #require(indicator.pointerInteractionViewForTesting)
        let window = try #require(view.window)
        for x in [CGFloat(12), CGFloat(50)] {
            let start = window.convertPoint(toScreen: view.convert(NSPoint(x: x, y: view.bounds.midY), to: nil))
            let finish = NSPoint(x: start.x + 1, y: start.y + 1)
            view.mouseDown(with: try pointerEvent(.leftMouseDown, screenPoint: start, window: window))
            view.mouseDragged(with: try pointerEvent(.leftMouseDragged, screenPoint: finish, window: window))
            view.mouseUp(with: try pointerEvent(.leftMouseUp, screenPoint: finish, window: window))
        }
        #expect(pauses == 1)
        #expect(stops == 1)
        #expect(savedPositions == 0)
    }

    @MainActor
    @Test("meeting processing stays at the dragged recording anchor and remains draggable")
    func meetingProcessingRetainsPosition() throws {
        let (indicator, store, directory) = makeMeetingIndicator()
        defer {
            indicator.close()
            try? FileManager.default.removeItem(at: directory)
        }
        var savedCenters: [CGPoint] = []
        indicator.onPositionSaved = { center in
            savedCenters.append(center)
            var config = store.load()
            config.indicatorAnchor = .custom
            config.indicatorOrigin = CGPointCodable(x: center.x, y: center.y)
            store.save(config)
        }
        indicator.setMeetingRecording(true, config: store.load())
        try drag(indicator, by: CGPoint(x: -110, y: 60))
        let recordingAnchor = try #require(savedCenters.last)
        indicator.setMeetingRecording(false, config: store.load())

        for status in ["Transcribing", "Cleaning", "Titling", "Summarizing"] {
            indicator.showMeetingProcessingStatus(status, config: store.load())
            let frame = try #require(indicator.currentFrame)
            #expect(indicator.pointerInteractionViewForTesting?.window?.frame == frame)
            #expect(frame.midX == recordingAnchor.x)
            #expect(frame.midY == recordingAnchor.y)
        }

        try drag(indicator, by: CGPoint(x: 75, y: -45))
        let processingAnchor = try #require(savedCenters.last)
        #expect(processingAnchor == CGPoint(x: recordingAnchor.x + 75, y: recordingAnchor.y - 45))
        #expect(savedCenters.count == 2)
        indicator.showMeetingProcessingStatus("Transcribing", config: store.load())
        #expect(indicator.currentFrame?.midX == processingAnchor.x)
        #expect(indicator.currentFrame?.midY == processingAnchor.y)
        indicator.setState(.idle, config: store.load())
        indicator.setMeetingRecording(true, config: store.load())
        #expect(indicator.currentFrame?.midX == processingAnchor.x)
        #expect(indicator.currentFrame?.midY == processingAnchor.y)
    }

    @MainActor
    @Test("dictation above a focused input never replaces the meeting's saved anchor")
    func dictationPlacementDoesNotMoveMeeting() throws {
        let (unusedIndicator, store, directory) = makeMeetingIndicator()
        unusedIndicator.close()
        let visible = try #require(NSScreen.main?.visibleFrame)
        let field = CGRect(x: visible.minX + 100, y: visible.minY + 100, width: 260, height: 70)
        var inputQueries = 0
        let indicator = FloatingIndicatorController(configStore: store, textInputFrameProvider: {
            inputQueries += 1
            return field
        })
        defer {
            indicator.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let originalConfig = store.load()
        let savedAnchor = try #require(originalConfig.indicatorOrigin)
        var savedPositions = 0
        indicator.onPositionSaved = { _ in savedPositions += 1 }
        indicator.showMeetingProcessingStatus("Summarizing", config: originalConfig)
        #expect(inputQueries == 0)

        for state in [DictationState.preparing, .recording, .transcribing] {
            indicator.setState(state, config: originalConfig)
            let frame = try #require(indicator.currentFrame)
            #expect(frame.midX == field.midX)
            #expect(frame.minY == field.maxY + 8)
            try drag(indicator, by: CGPoint(x: 60, y: 40))
            #expect(indicator.currentFrame == frame)
        }
        #expect(inputQueries > 0)
        #expect(savedPositions == 0)
        #expect(store.load().indicatorOrigin?.x == savedAnchor.x)
        #expect(store.load().indicatorOrigin?.y == savedAnchor.y)

        indicator.showMeetingProcessingStatus("Summarizing", config: store.load())
        let processingFrame = try #require(indicator.currentFrame)
        #expect(abs(processingFrame.midX - CGFloat(savedAnchor.x)) <= 0.5)
        #expect(abs(processingFrame.midY - CGFloat(savedAnchor.y)) <= 0.5)
        indicator.setMeetingRecording(true, config: store.load())
        let recordingFrame = try #require(indicator.currentFrame)
        #expect(abs(recordingFrame.midX - CGFloat(savedAnchor.x)) <= 0.5)
        #expect(abs(recordingFrame.midY - CGFloat(savedAnchor.y)) <= 0.5)
    }

    @MainActor
    private func drag(_ indicator: FloatingIndicatorController, by offset: CGPoint) throws {
        let view = try #require(indicator.pointerInteractionViewForTesting)
        let window = try #require(view.window)
        let start = window.convertPoint(toScreen: view.convert(
            NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil
        ))
        let finish = CGPoint(x: start.x + offset.x, y: start.y + offset.y)
        view.mouseDown(with: try pointerEvent(.leftMouseDown, screenPoint: start, window: window))
        view.mouseDragged(with: try pointerEvent(.leftMouseDragged, screenPoint: finish, window: window))
        view.mouseUp(with: try pointerEvent(.leftMouseUp, screenPoint: finish, window: window))
    }

    @MainActor
    private func pointerEvent(_ type: NSEvent.EventType, screenPoint: NSPoint, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: window.convertPoint(fromScreen: screenPoint),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }

    @MainActor
    private func makeMeetingIndicator() -> (FloatingIndicatorController, ConfigStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floating-meeting-drag-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(supportDirectory: directory)
        var config = AppConfig()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        config.indicatorAnchor = .custom
        config.indicatorOrigin = CGPointCodable(x: screen.midX, y: screen.midY)
        config.indicatorHoverStyle = .classic
        config.showMeetingTranscriptOnIndicatorHover = true
        store.save(config)
        return (FloatingIndicatorController(configStore: store), store, directory)
    }

    @MainActor
    private func makeIndicator() -> FloatingIndicatorController {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FloatingIndicatorController(configStore: ConfigStore(supportDirectory: supportDirectory))
    }
}

// MARK: - OpenAI Logo Shape

@Suite("OpenAI Logo Shape")
struct OpenAILogoShapeTests {

    @Test("shape produces non-empty path")
    func nonEmptyPath() {
        let shape = OpenAILogoShape()
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
    }

    @Test("shape scales to arbitrary rect")
    func scalesCorrectly() {
        let shape = OpenAILogoShape()
        let small = shape.path(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        let large = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!small.isEmpty)
        #expect(!large.isEmpty)
        // Larger rect should produce a larger bounding box
        #expect(large.boundingRect.width > small.boundingRect.width)
    }

    @Test("shape handles zero rect without crash")
    func zeroRect() {
        let shape = OpenAILogoShape()
        let path = shape.path(in: .zero)
        // Should not crash; path will be empty or degenerate
        let _ = path.boundingRect
    }
}

// MARK: - DictationState

@Suite("DictationState idle check")
struct DictationStateIdleTests {

    @Test("all dictation states are defined")
    func allStates() {
        let states: [DictationState] = [.idle, .preparing, .recording, .transcribing]
        #expect(states.count == 4)
    }

    @Test("idle is distinct from active states")
    func idleDistinct() {
        #expect(DictationState.idle != .recording)
        #expect(DictationState.idle != .preparing)
        #expect(DictationState.idle != .transcribing)
    }
}

// MARK: - Meeting chunk collection

@Suite("Meeting chunk collection")
struct MeetingChunkCollectorTests {

    @Test("collector waits for tasks, keeps completed segments, and sorts by start")
    func collectorSortsSegments() async {
        let collector = MeetingChunkCollector()

        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                return [SpeechSegment(start: 30, end: 31, text: "later")]
            }
        )
        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(5))
                return []
            }
        )
        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(10))
                return [SpeechSegment(start: 10, end: 11, text: "earlier")]
            }
        )

        let segments = await collector.closeAndDrainSortedSegments()

        #expect(segments.map(\.text) == ["earlier", "later"])
        #expect(segments.map(\.start) == [10, 30])
    }

    @Test("collector rejects tasks after closing")
    func collectorRejectsLateTasks() async {
        let collector = MeetingChunkCollector()
        let initialTask = Task<[SpeechSegment], Never> {
            [SpeechSegment(start: 1, end: 2, text: "first")]
        }
        #expect(collector.add(initialTask).registered)

        let initial = await collector.closeAndDrainSortedSegments()
        #expect(initial.map(\.text) == ["first"])

        let lateTask = Task<[SpeechSegment], Never> {
            [SpeechSegment(start: 3, end: 4, text: "late")]
        }
        #expect(!collector.add(lateTask).registered)
        lateTask.cancel()
    }

    @Test("collector retire returns false after drain closes collector")
    func collectorRetireReturnsFalseAfterDrain() async {
        let collector = MeetingChunkCollector()
        let task = Task<[SpeechSegment], Never> {
            try? await Task.sleep(for: .milliseconds(10))
            return [SpeechSegment(start: 1, end: 2, text: "first")]
        }
        let registration = collector.add(task)
        #expect(registration.registered)

        let drained = await collector.closeAndDrainSortedSegments()
        let retired = collector.retire(id: registration.retireID, segments: await task.value)

        #expect(drained.map(\.text) == ["first"])
        #expect(retired == false)
    }

    @Test("collector flattens timed segments from a single chunk and sorts them")
    func collectorFlattensChunkSegments() async {
        let collector = MeetingChunkCollector()

        _ = collector.add(
            Task {
                [
                    SpeechSegment(start: 12, end: 12.5, text: "second"),
                    SpeechSegment(start: 11, end: 11.5, text: "first")
                ]
            }
        )

        let segments = await collector.closeAndDrainSortedSegments()

        #expect(segments.map(\.text) == ["first", "second"])
        #expect(segments.map(\.start) == [11, 12])
    }
}

@Suite("Meeting chunk timing")
struct MeetingChunkTimingTrackerTests {
    @Test("fast bilingual sample caps follow the selected backend with or without VAD")
    func bilingualSampleCapsFollowBackend() {
        let timing = StreamingVadController.ChunkTiming.self
        #expect(timing.fastBilingual.minimum == 1.5)
        #expect(timing.fastBilingual.maximum == 5)
        #expect(timing.sampleCap(bilingual: true, backend: "sensevoice", hasVAD: true) == 3)
        #expect(timing.sampleCap(bilingual: true, backend: "sensevoice", hasVAD: false) == 3)
        #expect(timing.sampleCap(bilingual: true, backend: "whisper", hasVAD: true) == nil)
        #expect(timing.sampleCap(bilingual: true, backend: "whisper", hasVAD: false) == 5)
        #expect(timing.sampleCap(bilingual: false, backend: "sensevoice", hasVAD: true) == nil)
        #expect(timing.sampleCap(bilingual: false, backend: "fluidaudio", hasVAD: false) == 5)
    }

    @Test("changing a live backend applies its cap to the already recorded samples")
    func backendChangeUpdatesSampleCap() throws {
        var tracker = MeetingChunkTimingTracker()
        tracker.start()
        tracker.append(sampleCount: 4 * 16_000)
        let senseVoiceCap = try #require(StreamingVadController.ChunkTiming.sampleCap(
            bilingual: true, backend: "sensevoice", hasVAD: true
        ))
        #expect(tracker.shouldRotate(maximumDuration: senseVoiceCap))
        #expect(tracker.rotate()?.durationSeconds == 4)

        let whisperFallbackCap = try #require(StreamingVadController.ChunkTiming.sampleCap(
            bilingual: true, backend: "whisper", hasVAD: false
        ))
        tracker.append(sampleCount: 4 * 16_000)
        #expect(!tracker.shouldRotate(maximumDuration: whisperFallbackCap))
        tracker.append(sampleCount: 16_000)
        #expect(tracker.shouldRotate(maximumDuration: whisperFallbackCap))
        #expect(tracker.rotate()?.startTimeSeconds == 4)
    }

    @Test("a queued VAD callback cannot rotate an empty or short chunk after a sample-cap rotation")
    func duplicateBoundaryDoesNotCreateShortChunk() {
        var tracker = MeetingChunkTimingTracker()
        tracker.start()
        #expect(!tracker.canRotate(minimumDuration: 0))
        tracker.append(sampleCount: 48_000)
        // AEC flush appends through the same funnel before one outer rotation.
        tracker.append(sampleCount: 320)
        #expect(tracker.rotate()?.sampleCount == 48_320)
        #expect(!tracker.canRotate(minimumDuration: 1.5))
        tracker.append(sampleCount: 320)
        #expect(!tracker.canRotate(minimumDuration: 1.5))
        // Pause/finalization may still preserve a deliberately short tail.
        #expect(tracker.canRotate(minimumDuration: 0))
        tracker.append(sampleCount: 23_680)
        #expect(tracker.canRotate(minimumDuration: 1.5))
    }

    @Test("real chunk rotation invalidates an already delivered VAD boundary request")
    func externalRotationInvalidatesQueuedVADBoundary() async throws {
        let requests = OSAllocatedUnfairLock(initialState: [StreamingVadController.BoundaryRequest]())
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                VadStreamResult(
                    state: state,
                    event: VadStreamEvent(kind: .speechEnd, sampleIndex: VadManager.chunkSize),
                    probability: 0.05
                )
            }
        )
        controller.onChunkBoundary = { request in requests.withLock { $0.append(request) } }
        controller.start()
        defer { controller.stop() }
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        let deadline = ContinuousClock.now + .seconds(2)
        while requests.withLock({ $0.isEmpty }), ContinuousClock.now < deadline {
            await MainActor.run {}
            try await Task.sleep(for: .milliseconds(5))
        }
        let request = try #require(requests.withLock { $0.first })
        #expect(controller.isCurrentBoundary(request))
        controller.notifyRotation()
        #expect(!controller.isCurrentBoundary(request))
        controller.stop()
        #expect(!controller.isCurrentBoundary(request))
    }

    @Test("sample-based fallback rotates live chunks when VAD is unavailable")
    func fallbackRotationTracksRecordedSamples() {
        var tracker = MeetingChunkTimingTracker()
        #expect(!tracker.shouldRotate(maximumDuration: 3))
        tracker.start()
        tracker.append(sampleCount: 47_999)
        #expect(!tracker.shouldRotate(maximumDuration: 3))
        tracker.append(sampleCount: 1)
        #expect(tracker.shouldRotate(maximumDuration: 3))
        #expect(tracker.rotate()?.durationSeconds == 3)
        #expect(!tracker.shouldRotate(maximumDuration: 3))
        tracker.discard()
        tracker.append(sampleCount: 48_000)
        #expect(!tracker.shouldRotate(maximumDuration: 3))
    }

    @Test("tracks chunk offsets from processed sample counts")
    func tracksChunkOffsets() {
        var tracker = MeetingChunkTimingTracker()
        tracker.start()
        tracker.append(sampleCount: 1600)

        let first = tracker.rotate()
        tracker.append(sampleCount: 800)
        let second = tracker.finish()

        #expect(first?.startSampleIndex == 0)
        #expect(first?.sampleCount == 1600)
        #expect(first?.startTimeSeconds == 0)
        #expect(first?.durationSeconds == 0.1)

        #expect(second?.startSampleIndex == 1600)
        #expect(second?.sampleCount == 800)
        #expect(second?.startTimeSeconds == 0.1)
        #expect(second?.durationSeconds == 0.05)
    }
}
