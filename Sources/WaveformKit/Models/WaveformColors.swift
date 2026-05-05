import SwiftUI

public struct WaveformColors: Sendable, Equatable {
    public var played: Color
    public var unplayed: Color
    public var playedGradient: Gradient?
    public var unplayedGradient: Gradient?

    public init(
        played: Color = .accentColor,
        unplayed: Color = Color.gray.opacity(0.35),
        playedGradient: Gradient? = nil,
        unplayedGradient: Gradient? = nil
    ) {
        self.played = played
        self.unplayed = unplayed
        self.playedGradient = playedGradient
        self.unplayedGradient = unplayedGradient
    }
}
