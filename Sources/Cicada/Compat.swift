import AppKit
import SwiftUI

/// SwiftUI that macOS 14 lacks, with what it gets instead.
extension View {
    /// The pointing hand over something clickable.
    @ViewBuilder func linkPointer() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
    }

    /// Where a scroll view's content sits against the chosen edge (15 and later; 14 has
    /// `onLegacyBottomDistance` below).
    @ViewBuilder func onScrollEdgeChange(fromTop: Bool = false, _ action: @escaping (ScrollEdge, ScrollEdge) -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollGeometryChange(for: ScrollEdge.self) { g in
                ScrollEdge(distance: fromTop ? g.contentOffset.y : g.contentSize.height - g.contentOffset.y - g.containerSize.height,
                           height: g.contentSize.height, container: g.containerSize.height)
            } action: { old, new in action(old, new) }
        } else {
            self
        }
    }

    /// The content scrolled (macOS 15 and later).
    @ViewBuilder func onScrolled(_ action: @escaping () -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, _ in action() }
        } else {
            self
        }
    }
}

extension View {
    /// macOS 14: distance from the chosen content marker to the visible edge,
    /// measured by geometry since `onScrollGeometryChange` is 15 and later. Does nothing on 15+.
    @ViewBuilder func onLegacyBottomDistance(fromTop: Bool = false, _ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(macOS 15, *) {
            self
        } else {
            coordinateSpace(name: LegacyScrollEdge.space)
                .background(GeometryReader { g in
                    Color.clear.preference(key: LegacyScrollEdge.Container.self, value: g.size.height)
                })
                .onPreferenceChange(LegacyScrollEdge.Container.self) { LegacyScrollEdge.container = $0 }
                // The lazy stack doesn't draw a marker scrolled far out of view: that's far from the bottom.
                .onPreferenceChange(LegacyScrollEdge.Bottom.self) { y in
                    if !fromTop { action(y < 0 ? .greatestFiniteMagnitude : y - LegacyScrollEdge.container) }
                }
                .onPreferenceChange(LegacyScrollEdge.Top.self) { y in
                    if fromTop { action(y == .greatestFiniteMagnitude ? y : -y) }
                }
        }
    }

    /// Put on the content's first or last view to match the scroll view's chosen edge.
    @ViewBuilder func bottomMarker(fromTop: Bool = false) -> some View {
        if #available(macOS 15, *) {
            self
        } else {
            background(GeometryReader { g in
                if fromTop {
                    Color.clear.preference(key: LegacyScrollEdge.Top.self,
                                           value: g.frame(in: .named(LegacyScrollEdge.space)).minY)
                } else {
                    Color.clear.preference(key: LegacyScrollEdge.Bottom.self,
                                           value: g.frame(in: .named(LegacyScrollEdge.space)).maxY)
                }
            })
        }
    }
}

enum LegacyScrollEdge {
    static let space = "cicada.scroll"
    nonisolated(unsafe) static var container: CGFloat = 0
    struct Container: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    struct Top: PreferenceKey {
        static let defaultValue: CGFloat = .greatestFiniteMagnitude
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
    }
    /// -1 while the marker isn't drawn.
    struct Bottom: PreferenceKey {
        static let defaultValue: CGFloat = -1
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

/// Distance from the followed edge, the content's height and the view's.
struct ScrollEdge: Equatable {
    var distance: CGFloat
    var height: CGFloat
    var container: CGFloat
}
