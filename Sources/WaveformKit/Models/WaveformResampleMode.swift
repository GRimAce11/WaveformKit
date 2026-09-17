import Foundation

/// How a summary's amplitude bins are pooled when there are more of them than there are bars
/// to draw.
///
/// A `WaveformSummary` is decoded at a fixed resolution — 200 bins by default — and a view may
/// ask for any number of bars. Squeezing 200 bins into 60 bars means each bar has to stand for
/// several bins, and this decides how.
///
/// ```swift
/// WaveformView(summary: s, currentTime: t, style: .bars(count: 60), resampleMode: .peak)
/// ```
public enum WaveformResampleMode: String, Sendable, Equatable, Hashable, Codable, CaseIterable {

    /// Each bar is the **loudest** bin it covers.
    ///
    /// The default. Keeps drum hits, plosives, and other short transients visible when a long
    /// file is squeezed into a few hundred bars — the detail that makes a waveform recognisable
    /// as *this* recording rather than a generic blob.
    case peak

    /// Each bar is the **mean** of the bins it covers.
    ///
    /// Smoother and flatter. Because the decoder has already reduced every bin to an RMS value,
    /// this is an average of averages, so peaks erode quickly as the bar count drops. Choose it
    /// when you want an even, low-contrast shape — an ambient level meter rather than a
    /// scrubbable timeline. This was the only behaviour before 0.6.0.
    case mean
}
