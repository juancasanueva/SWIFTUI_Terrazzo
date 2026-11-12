import AppKit
import CoreGraphics

struct DisplayInfo: Equatable {
    var uuid: String
    var name: String
    /// Whole screen, in window-system coordinates (origin at the top left of the main display).
    var frame: CGRect
    /// Below the menu bar and beside the Dock.
    var visibleFrame: CGRect
}

enum Displays {
    static func current() -> [DisplayInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return nil }
            return DisplayInfo(
                uuid: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName,
                frame: flip(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: flip(screen.visibleFrame, primaryHeight: primaryHeight))
        }
    }

    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a window-system rectangle to AppKit coordinates. The conversion is its own inverse.
    static func toAppKit(_ rect: CGRect) -> CGRect {
        flip(rect, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    static func pointerLocation() -> CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    static func movePointer(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // A warp otherwise stops the pointer responding for a moment.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) } ?? displays.first
    }

    /// The display showing most of the rectangle.
    static func display(for frame: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.max { first, second in
            area(first.frame.intersection(frame)) < area(second.frame.intersection(frame))
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

/// Reads Mission Control Spaces. There is no public API; when SkyLight's functions are missing,
/// everything is treated as one Space and tiling keeps working.
final class SpaceReader {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ManagedDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let connection: Int32
    private let currentSpace: CurrentSpace?
    private let spacesForWindows: SpacesForWindows?
    private let managedDisplays: ManagedDisplays?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        connection = load("SLSMainConnectionID", as: MainConnection.self)?() ?? 0
        currentSpace = load("SLSManagedDisplayGetCurrentSpace", as: CurrentSpace.self)
        spacesForWindows = load("SLSCopySpacesForWindows", as: SpacesForWindows.self)
        managedDisplays = load("SLSCopyManagedDisplays", as: ManagedDisplays.self)
    }

    /// Display UUIDs in Mission Control's order; empty when SkyLight doesn't provide it.
    func displayOrder() -> [String] {
        (managedDisplays?(connection)?.takeRetainedValue() as? [String]) ?? []
    }

    func activeSpace(ofDisplay uuid: String) -> UInt64 {
        currentSpace?(connection, uuid as CFString) ?? 0
    }

    func spaces(ofWindow id: WindowID) -> Set<UInt64> {
        guard let spacesForWindows else { return [] }
        let windows = [NSNumber(value: id)] as CFArray
        // 0x7: every Space, current or not.
        guard let result = spacesForWindows(connection, 0x7, windows)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return Set(result.map(\.uint64Value))
    }
}

enum SystemState {
    static var isSessionLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    static var stageManagerEnabled: Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesGetAppBooleanValue("GloballyEnabled" as CFString, domain, nil)
    }
}
