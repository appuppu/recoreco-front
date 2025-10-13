import SwiftUI

struct WaveformRangeSelectorView: View {
    let totalDuration: Double
    @Binding var startTime: Double
    let rangeLength: Double = 30.0
    @Binding var isPlaying: Bool
    @Binding var currentPlaybackTime: Double

    @State private var isDragging = false
    @GestureState private var dragOffset: CGFloat = 0
    @State private var waveformHeights: [CGFloat] = []

    private let numberOfBars = 100
    private let barSpacing: CGFloat = 2

    var endTime: Double {
        min(startTime + rangeLength, totalDuration)
    }

    var maxStartTime: Double {
        max(0, totalDuration - rangeLength)
    }

    init(totalDuration: Double, startTime: Binding<Double>, isPlaying: Binding<Bool>, currentPlaybackTime: Binding<Double>) {
        self.totalDuration = totalDuration
        self._startTime = startTime
        self._isPlaying = isPlaying
        self._currentPlaybackTime = currentPlaybackTime

        // Generate pseudo-random waveform heights
        var heights: [CGFloat] = []
        for i in 0..<numberOfBars {
            let normalizedPosition = Double(i) / Double(numberOfBars)
            let baseHeight = sin(normalizedPosition * .pi * 4) * 0.3 + 0.5
            let noise = Double.random(in: -0.2...0.2)
            heights.append(CGFloat(max(0.2, min(1.0, baseHeight + noise))))
        }
        self._waveformHeights = State(initialValue: heights)
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - CGFloat(numberOfBars - 1) * barSpacing) / CGFloat(numberOfBars)
            let totalWidth = geometry.size.width
            let rangeWidth = (rangeLength / totalDuration) * totalWidth
            let startOffset = (startTime / totalDuration) * totalWidth

            ZStack(alignment: .leading) {
                // Background waveform
                HStack(spacing: barSpacing) {
                    ForEach(0..<numberOfBars, id: \.self) { index in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: barWidth, height: waveformHeights[index] * geometry.size.height)
                    }
                }

                // Selected range overlay
                HStack(spacing: barSpacing) {
                    ForEach(0..<numberOfBars, id: \.self) { index in
                        let barPosition = CGFloat(index) * (barWidth + barSpacing)
                        let isInRange = barPosition >= startOffset && barPosition < startOffset + rangeWidth

                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(
                                isInRange ?
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.clear]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: barWidth, height: waveformHeights[index] * geometry.size.height)
                    }
                }

                // Range selector handles
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.2))
                    )
                    .frame(width: rangeWidth, height: geometry.size.height)
                    .offset(x: startOffset + dragOffset)
                    .overlay(
                        HStack {
                            // Left handle
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 4, height: geometry.size.height * 0.6)
                                .padding(.leading, 4)

                            Spacer()

                            // Right handle
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 4, height: geometry.size.height * 0.6)
                                .padding(.trailing, 4)
                        }
                        .offset(x: startOffset + dragOffset)
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onChanged { _ in
                                isDragging = true
                            }
                            .onEnded { value in
                                let newOffset = startOffset + value.translation.width
                                let newStartTime = (newOffset / totalWidth) * totalDuration
                                startTime = max(0, min(maxStartTime, newStartTime))
                                isDragging = false
                            }
                    )

                // Playback position indicator
                if isPlaying {
                    let playbackPosition = ((currentPlaybackTime - startTime) / rangeLength) * rangeWidth
                    if playbackPosition >= 0 && playbackPosition <= rangeWidth {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: geometry.size.height)
                            .offset(x: startOffset + playbackPosition)
                    }
                }
            }
        }
    }
}

struct WaveformRangeSelectorContainer: View {
    let totalDuration: Double
    @Binding var startTime: Double
    @Binding var isPlaying: Bool
    @Binding var currentPlaybackTime: Double

    var endTime: Double {
        min(startTime + 30, totalDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Duration info
            HStack {
                Text("再生範囲")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("曲全体: \(formatTime(totalDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Time labels
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("開始")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTime(startTime))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("終了")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTime(endTime))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                }
            }

            // Waveform range selector
            WaveformRangeSelectorView(
                totalDuration: totalDuration,
                startTime: $startTime,
                isPlaying: $isPlaying,
                currentPlaybackTime: $currentPlaybackTime
            )
            .frame(height: 80)
            .cornerRadius(8)

            // Duration indicator
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("30秒")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    WaveformRangeSelectorContainer(
        totalDuration: 210,
        startTime: .constant(30),
        isPlaying: .constant(true),
        currentPlaybackTime: .constant(35)
    )
    .padding()
}
