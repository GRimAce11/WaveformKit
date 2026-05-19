import Foundation

/// System-level events that can affect mic capture **or** file playback mid-session. Delivered
/// to a player or recorder's `onInterruption` callback so the app can react (toast, button-state
/// sync, etc.).
public enum AudioInterruption: Sendable, Equatable {
    /// Another audio source (phone call, Siri, alarm) took over the audio session. The engine
    /// has been paused by the system.
    case began
    /// The interruption ended. `shouldResume` mirrors iOS's hint: when `true`, the OS recommends
    /// resuming. The session auto-resumes only if `autoResumeAfterInterruption` was enabled.
    case ended(shouldResume: Bool)
    /// The audio route changed (headphones unplugged, AirPods connected, etc.). Capture or
    /// playback continues on the new route; apps may pause manually for e.g.
    /// `oldDeviceUnavailable`.
    case audioRouteChanged(reason: RouteChangeReason)

    public enum RouteChangeReason: Sendable, Equatable {
        case oldDeviceUnavailable
        case newDeviceAvailable
        case other
    }
}

/// Source-compatible alias for `AudioInterruption`. The recorder's interruption callback has
/// always used this name; the underlying enum is now shared with `AVAudioEnginePlayer`.
public typealias MicrophoneInterruption = AudioInterruption
