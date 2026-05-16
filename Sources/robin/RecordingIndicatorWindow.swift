import AppKit
import SwiftUI

@MainActor
final class RecordingIndicatorWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<RecordingIndicatorView>?
    private var recordingStartedAt: Date?
    private var recordingSessionID: UUID?

    func showRecording() {
        if recordingStartedAt == nil {
            recordingStartedAt = Date()
            recordingSessionID = UUID()
        }

        guard let recordingStartedAt, let recordingSessionID else { return }
        show(phase: .recording(startedAt: recordingStartedAt, sessionID: recordingSessionID))
    }

    func showProcessing() {
        let elapsedSeconds = recordingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let sessionID = recordingSessionID ?? UUID()
        recordingStartedAt = nil
        recordingSessionID = nil
        show(phase: .processing(elapsedSeconds: elapsedSeconds, sessionID: sessionID))
    }

    func hide() {
        recordingStartedAt = nil
        recordingSessionID = nil
        window?.orderOut(nil)
    }

    private func show(phase: RecordingIndicatorPhase) {
        setRootView(phase: phase)

        guard let window, let hostingController else { return }

        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: 240, height: 80)
        )
        window.setContentSize(
            NSSize(
                width: ceil(fittingSize.width),
                height: ceil(fittingSize.height)
            )
        )
        position(window)
        window.orderFrontRegardless()
    }

    private func setRootView(phase: RecordingIndicatorPhase) {
        let view = RecordingIndicatorView(phase: phase)

        if let hostingController {
            hostingController.rootView = view
        } else {
            let hostingController = NSHostingController(rootView: view)
            self.hostingController = hostingController
            window = makeWindow(hostingController: hostingController)
        }
    }

    private func makeWindow(hostingController: NSHostingController<RecordingIndicatorView>) -> NSWindow {
        let window = NonActivatingIndicatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.appearance = NSAppearance(named: .aqua)
        window.animationBehavior = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }

    private func position(_ window: NSWindow) {
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let frame = screen.visibleFrame
        let size = window.frame.size
        let bottomPadding: CGFloat = 48
        let origin = NSPoint(
            x: frame.midX - (size.width / 2),
            y: frame.minY + bottomPadding
        )
        window.setFrameOrigin(origin)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

private final class NonActivatingIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum RecordingIndicatorPhase: Equatable {
    case recording(startedAt: Date, sessionID: UUID)
    case processing(elapsedSeconds: Int, sessionID: UUID)

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }

    var timelineStart: Date {
        switch self {
        case .recording(let startedAt, _):
            startedAt
        case .processing:
            .now
        }
    }

    var sessionID: UUID {
        switch self {
        case .recording(_, let sessionID),
             .processing(_, let sessionID):
            sessionID
        }
    }

    func elapsedSeconds(at date: Date) -> Int {
        switch self {
        case .recording(let startedAt, _):
            max(0, Int(date.timeIntervalSince(startedAt)))
        case .processing(let elapsedSeconds, _):
            elapsedSeconds
        }
    }
}

private struct RecordingIndicatorView: View {
    let phase: RecordingIndicatorPhase

    var body: some View {
        TimelineView(.periodic(from: phase.timelineStart, by: 1)) { context in
            let elapsedSeconds = phase.elapsedSeconds(at: context.date)

            HStack(spacing: 2) {
                phaseIndicator
                    .frame(width: 14, height: 14)

                Text(Self.formattedElapsedTime(elapsedSeconds))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(elapsedSeconds)))
                    .animation(.bouncy(duration: 0.34, extraBounce: 0.18), value: elapsedSeconds)
                    .frame(minWidth: 62, alignment: .center)
            }
            .id(phase.sessionID)
            .padding(.leading, 16)
            .padding(.trailing, 11)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        if phase.isProcessing {
            SmallSpinnerView()
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(Color(red: 0.95, green: 0.08, blue: 0.10))
                .frame(width: 7, height: 7)
                .shadow(color: Color(red: 0.95, green: 0.08, blue: 0.10).opacity(0.38), radius: 7)
        }
    }

    private static func formattedElapsedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds / 60) % 60
        let seconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct SmallSpinnerView: View {
    @State private var isVisible = false

    var body: some View {
        NativeSpinnerView()
            .scaleEffect(isVisible ? 1 : 0.6, anchor: .center)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 2)
            .animation(.easeOut(duration: 0.1), value: isVisible)
            .onAppear {
                isVisible = false
                Task { @MainActor in
                    await Task.yield()
                    isVisible = true
                }
            }
    }
}

private struct NativeSpinnerView: NSViewRepresentable {
    func makeNSView(context: Context) -> SpinnerContainerView {
        SpinnerContainerView()
    }

    func updateNSView(_ view: SpinnerContainerView, context: Context) {
        view.startAnimating()
    }
}

private final class SpinnerContainerView: NSView {
    private let indicator = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        appearance = NSAppearance(named: .aqua)
        indicator.appearance = NSAppearance(named: .aqua)
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = true
        indicator.usesThreadedAnimation = true
        indicator.sizeToFit()

        addSubview(indicator)
        startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 14, height: 14)
    }

    override func layout() {
        super.layout()

        indicator.sizeToFit()
        indicator.frame.origin = NSPoint(
            x: (bounds.width - indicator.frame.width) / 2,
            y: (bounds.height - indicator.frame.height) / 2
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startAnimating()
    }

    func startAnimating() {
        indicator.startAnimation(nil)
    }
}
