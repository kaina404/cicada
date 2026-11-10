import SwiftUI
import Combine

@main
struct CicadaWatchApp: App {
  @StateObject private var link = WatchLink()
  var body: some Scene {
    WindowGroup { ControlView(link: link) }
  }
}

struct ControlView: View {
  @ObservedObject var link: WatchLink
  @StateObject private var touch = TouchController()
  @State private var crown = 0.0
  @State private var crownStep = 0
  @GestureState private var touching = false
  @Environment(\.scenePhase) private var phase

  var body: some View {
    GeometryReader { area in
      ZStack {
        RoundedRectangle(cornerRadius: 24)
          .fill(touch.state.holding ? Color.orange.opacity(0.18) : Color.white.opacity(0.08))
        VStack(spacing: 7) {
          Image(systemName: touch.state.holding ? "hand.point.up.left.fill" : "rectangle.on.rectangle")
            .font(.system(size: 30))
            .foregroundStyle(touch.state.holding ? .orange : (link.connected ? .green : .secondary))
          Text(touch.state.holding ? "陪读中" : "Cicada 浮窗").font(.headline)
          Text("滑动移窗 · 长按陪读")
          Text("单击下一句 · 双击上一句")
          Text("转动表冠切句 · 松手暂停")
          Text(link.status).font(.system(size: 10)).padding(.top, 3)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
        if let location = touch.location {
          Circle()
            .fill((touch.state.holding ? Color.orange : Color.green).opacity(0.25))
            .overlay(Circle().stroke(touch.state.holding ? Color.orange : Color.green, lineWidth: 2))
            .frame(width: touch.state.holding ? 32 : 24, height: touch.state.holding ? 32 : 24)
            .position(location)
            .allowsHitTesting(false)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .updating($touching) { _, state, _ in state = true }
          .onChanged { value in
            touch.changed(location: value.location, translation: value.translation, size: area.size, link: link)
          }
          .onEnded { value in touch.ended(translation: value.translation) }
      )
      .accessibilityLabel("Cicada 悬浮回答，滑动移动浮窗，单击下一句，双击上一句，转动表冠切句，长按陪读，抬手暂停")
    }
    .focusable()
    .digitalCrownRotation($crown, from: -10000, through: 10000, by: 1,
                          sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
    .onChange(of: crown) { _, value in
      let step = Int(value.rounded(.towardZero))
      let delta = step - crownStep
      crownStep = step
      for _ in 0..<min(abs(delta), 20) { touch.selectSentence(delta > 0 ? 1 : -1, link: link) }
    }
    .onAppear { touch.restartSession(); link.start() }
    .onDisappear { touch.cancel(); link.stop() }
    .onChange(of: touching) { _, active in if !active { touch.gestureDidFinish() } }
    .onChange(of: link.interruption) { _, _ in touch.cancel() }
    .onChange(of: phase) { _, phase in
      if phase == .active { touch.restartSession(); link.start() }
      else { touch.cancel(); link.stop() }
    }
  }
}
