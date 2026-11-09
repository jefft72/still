import AVFoundation
import Combine
import Foundation

/// Entirely local soundscapes. Playback always begins with an explicit user action.
@MainActor
final class AmbientAudio: ObservableObject {
  enum Soundscape: String, CaseIterable, Identifiable {
    case rain, shore, ember

    var id: String { rawValue }

    var title: String {
      switch self {
      case .rain: return "Rain"
      case .shore: return "Shore"
      case .ember: return "Ember"
      }
    }

    var subtitle: String {
      switch self {
      case .rain: return "A soft, steady downpour"
      case .shore: return "Slow waves, open water"
      case .ember: return "Warmth after dark"
      }
    }

    var symbol: String {
      switch self {
      case .rain: return "cloud.rain"
      case .shore: return "water.waves"
      case .ember: return "flame"
      }
    }
  }

  @Published var volume: Double = 0.35 {
    didSet { fadeToCurrentSettings() }
  }
  @Published var soundscape: Soundscape = .rain {
    didSet { fadeToCurrentSettings() }
  }
  @Published private(set) var isPlaying = false
  @Published private(set) var errorMessage: String?

  private let engine = AVAudioEngine()
  private var channels: [(Soundscape, AVAudioMixerNode)] = []
  private var fadeTask: Task<Void, Never>?
  private var configurationObserver: NSObjectProtocol?

  init() {
    // Render state belongs exclusively to its source callback. UI changes only
    // touch AVAudioEngine's mixer controls, never the real-time generators.
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    for scene in Soundscape.allCases {
      let generator = SoundscapeGenerator(scene: scene, sampleRate: 48_000)
      let source = AVAudioSourceNode(format: format) { _, _, frames, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frames) {
          let sample = generator.nextSample()
          for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            data[frame] = sample
          }
        }
        return noErr
      }
      let mixer = AVAudioMixerNode()
      mixer.outputVolume = 0
      engine.attach(source)
      engine.attach(mixer)
      engine.connect(source, to: mixer, format: format)
      engine.connect(mixer, to: engine.mainMixerNode, format: format)
      channels.append((scene, mixer))
    }

    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isPlaying else { return }
        // Device changes stop an engine. Resume only previously requested audio.
        self.restartAfterDeviceChange()
      }
    }
  }

  deinit {
    fadeTask?.cancel()
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    engine.stop()
  }

  func start() {
    guard !isPlaying else { return }
    errorMessage = nil
    do {
      if !engine.isRunning {
        for (_, mixer) in channels { mixer.outputVolume = 0 }
        engine.prepare()
        try engine.start()
      }
      isPlaying = true
      fadeToCurrentSettings()
    } catch {
      errorMessage = "Sound is unavailable. Check your audio output and try again."
      isPlaying = false
    }
  }

  func stop() {
    guard isPlaying else { return }
    isPlaying = false
    fadeToCurrentSettings()
  }

  func toggle() {
    if isPlaying { stop() } else { start() }
  }

  private func restartAfterDeviceChange() {
    fadeTask?.cancel()
    for (_, mixer) in channels { mixer.outputVolume = 0 }
    do {
      engine.prepare()
      try engine.start()
      errorMessage = nil
      fadeToCurrentSettings()
    } catch {
      isPlaying = false
      errorMessage = "Your audio output changed. Press play to reconnect."
    }
  }

  private func fadeToCurrentSettings() {
    fadeTask?.cancel()
    guard engine.isRunning else { return }
    let level = Float(volume.isFinite ? min(max(volume, 0), 1) : 0)
    let targets = channels.map { scene, mixer in
      (mixer, mixer.outputVolume, isPlaying && scene == soundscape ? level : 0)
    }
    let shouldPause = !isPlaying
    fadeTask = Task { [weak self] in
      // Smooth equal-time fades also make rapid scene changes interruption-safe.
      for step in 1...30 {
        guard !Task.isCancelled else { return }
        let position = Float(step) / 30
        let eased = position * position * (3 - 2 * position)
        for (mixer, origin, target) in targets {
          mixer.outputVolume = origin + (target - origin) * eased
        }
        do { try await Task.sleep(nanoseconds: 10_000_000) } catch { return }
      }
      if shouldPause { self?.engine.pause() }
    }
  }
}

/// One instance per render callback, with no mutable state shared with the UI.
/// All filtering and noise generation happen without allocation or blocking calls.
private final class SoundscapeGenerator {
  private let scene: AmbientAudio.Soundscape
  private let sampleRate: Double
  private var randomState: UInt64 = 0xA17E_5B93_C642_8D0F
  private var low: Float = 0
  private var mid: Float = 0
  private var slow: Float = 0
  private var crackle: Float = 0
  private var phase: Double = 0

  init(scene: AmbientAudio.Soundscape, sampleRate: Double) {
    self.scene = scene
    self.sampleRate = sampleRate
    // Different streams prevent correlated noise during crossfades.
    switch scene {
    case .rain: randomState = 0xA17E_5B93_C642_8D0F
    case .shore: randomState = 0x8923_BC61_34FA_7E05
    case .ember: randomState = 0x3619_DCE8_724B_A05F
    }
  }

  @inline(__always)
  private func noise() -> Float {
    randomState ^= randomState << 13
    randomState ^= randomState >> 7
    randomState ^= randomState << 17
    return Float(randomState >> 40) / Float(0xFF_FFFF) * 2 - 1
  }

  @inline(__always)
  func nextSample() -> Float {
    let white = noise()
    low += 0.012 * (white - low)
    mid += 0.12 * (white - mid)
    slow += 0.0018 * (white - slow)

    switch scene {
    case .rain:
      // A broad soft wash with a little high-frequency detail.
      return (mid * 0.65 + low * 1.6 + white * 0.09) * 0.65
    case .shore:
      phase += 1 / (sampleRate * 11.5)
      if phase >= 1 { phase -= 1 }
      let swell = Float(0.5 - 0.5 * cos(phase * 2 * .pi))
      let wave = swell * swell
      return (low * 2.5 + mid * 0.45) * (0.2 + wave * 0.75)
    case .ember:
      // Sparse filtered sparks sit above a warm low-frequency bed.
      if white > 0.9999 { crackle = 0.16 + (white - 0.9999) * 800 }
      crackle *= 0.994
      return slow * 3.2 + low * 0.5 + white * crackle
    }
  }
}
