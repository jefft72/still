import SwiftUI

enum Palette {
  static let background = Color(hex: 0xFCFBF8)
  static let panel = Color(hex: 0xF2F1ED)
  static let surface = Color(hex: 0xEAE8E2)
  static let ink = Color(hex: 0x252622)
  static let muted = Color(hex: 0x74766E)
  static let accent = Color(hex: 0xB84B2C)
  static let accentSoft = Color(hex: 0xF6E9E2)
  static let line = Color(hex: 0xE4E2DC)
  static let green = Color(hex: 0x4B7155)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xff) / 255,
      green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
  }
}

struct QuietButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  var selected = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(isEnabled ? 1 : 0.3)
      .foregroundStyle(selected ? Palette.ink : Palette.muted)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(
        selected || configuration.isPressed ? Palette.surface : Color.clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
  }
}

struct PrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(isEnabled ? 1 : 0.3).font(.system(size: 12, weight: .medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 14).frame(height: 32)
      .background(
        Palette.accent.opacity(configuration.isPressed ? 0.8 : 1),
        in: RoundedRectangle(cornerRadius: 6))
  }
}

struct IconButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(isEnabled ? 1 : 0.3).font(.system(size: 13))
      .foregroundStyle(Palette.muted)
      .frame(width: 28, height: 28)
      .background(
        configuration.isPressed ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 5)
      )
      .contentShape(Rectangle())
  }
}

struct StillMark: View {
  var size: CGFloat = 20
  var body: some View {
    HStack(alignment: .bottom, spacing: size * 0.22) {
      RoundedRectangle(cornerRadius: 1).fill(Palette.ink).frame(
        width: size * 0.2, height: size * 0.8)
      VStack(spacing: size * 0.14) {
        Circle().fill(Palette.accent).frame(width: size * 0.22, height: size * 0.22)
        RoundedRectangle(cornerRadius: 1).fill(Palette.ink).frame(
          width: size * 0.2, height: size * 0.44)
      }
    }.frame(width: size, height: size)
  }
}
