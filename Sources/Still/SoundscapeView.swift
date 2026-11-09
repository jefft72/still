import SwiftUI

struct SoundscapeView: View {
  @ObservedObject var audio: AmbientAudio
  @State private var expanded = false
  var body: some View {
    HStack(spacing: 10) {
      Button {
        audio.toggle()
      } label: {
        Image(systemName: audio.isPlaying ? "speaker.wave.2" : "speaker.slash")
          .foregroundStyle(audio.isPlaying ? Palette.ink : Palette.muted)
      }.buttonStyle(IconButton()).help(audio.isPlaying ? "Mute sound" : "Play ambient sound")
        .accessibilityLabel(audio.isPlaying ? "Mute sound" : "Play ambient sound")
      Menu {
        ForEach(AmbientAudio.Soundscape.allCases) { sound in
          Button {
            audio.soundscape = sound
            if !audio.isPlaying { audio.start() }
          } label: {
            Label(sound.title, systemImage: sound.symbol)
          }
        }
      } label: {
        HStack(spacing: 5) {
          Text(audio.isPlaying ? audio.soundscape.title : "Background sound")
          Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
      }.tint(Palette.muted).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      if audio.isPlaying {
        Slider(value: $audio.volume, in: 0...1).controlSize(.mini).tint(Palette.accent)
          .frame(width: 78).accessibilityLabel("Ambient volume")
      }
      if audio.errorMessage != nil {
        Button {
          expanded.toggle()
        } label: {
          Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.accent)
        }
        .buttonStyle(.plain).popover(isPresented: $expanded) {
          Text(audio.errorMessage ?? "").padding(16).frame(width: 260)
        }
      }
    }
  }
}
