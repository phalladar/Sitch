import AppKit
import SitchCore

/// STUB — replaced by the Capture port. Public surface below is the contract other modules use.
/// Coordinates: GLOBAL POINTS, TOP-LEFT origin at the primary display (Quartz display space),
/// the Mac analogue of Windows' physical virtual-screen pixels.
enum CaptureMode: Sendable { case region, window, fullScreen }

struct CaptureResult {
    let image: CGImage
    let kind: CaptureMode
    /// Region captures only: the selected rect, for Recapture Last Region.
    let region: CGRect?
    /// Where on screen the capture came from (all modes) — opens the editor on that display.
    let sourceRect: CGRect?
    /// Pixels per point of the captured display (2 on Retina).
    let pointScale: CGFloat
}

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isMain: Bool
}

@MainActor
final class CaptureController {
    private(set) var isActive = false

    /// Freeze the screens, show the overlays, call `completion` once with the result.
    /// Cancelling (Esc / right-click) never calls it.
    func startInteractive(_ mode: CaptureMode, completion: @escaping @MainActor (CaptureResult) -> Void) {}

    func captureDisplay(_ id: CGDirectDisplayID) async -> CaptureResult? { nil }
    func captureRect(_ rect: CGRect) async -> CaptureResult? { nil }

    static func displays() -> [DisplayInfo] { [] }
}

/// macOS Screen Recording privacy grant (TCC); required before any capture.
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    /// Triggers the system prompt (first time only); returns the current grant.
    @discardableResult static func request() -> Bool { CGRequestScreenCaptureAccess() }
    static func openSystemSettings() {}
}
