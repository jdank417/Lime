//
//  Theme.swift
//  Lime
//

import AppKit
import SwiftUI

enum Theme {
    static let lime = Color(red: 0.49, green: 0.78, blue: 0.13)
    static let limeLight = Color(red: 0.78, green: 0.94, blue: 0.40)
    static let limeDeep = Color(red: 0.23, green: 0.50, blue: 0.09)
    static let pith = Color(red: 0.95, green: 0.99, blue: 0.84)
    /// Dark green for text on lime.
    static let ink = Color(red: 0.07, green: 0.17, blue: 0.03)
    static let glass = Color(red: 0.06, green: 0.09, blue: 0.05)

    static let gradient = LinearGradient(colors: [limeLight, lime], startPoint: .top, endPoint: .bottom)
}

/// A ring segment between two radii, measured from the center of its frame.
/// Angles run clockwise from 3 o'clock, so -90° is straight up.
struct AnnularSector: Shape {
    var start: Angle
    var end: Angle
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The Lime logo: a lime slice.
struct LimeSlice: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(Theme.limeDeep)
                Circle().inset(by: size * 0.05).fill(Theme.pith)
                ForEach(0..<8) { index in
                    let start = Double(index) * 45 - 90
                    AnnularSector(start: .degrees(start + 4), end: .degrees(start + 41), inner: size * 0.07, outer: size * 0.39)
                        .fill(Theme.gradient)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

enum LimeMark {
    /// Template image of a lime slice for the menu bar.
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 1.5
            ring.stroke()
            for index in 0..<6 {
                let start = CGFloat(index) * 60 + 90 + 7
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: 5.6, startAngle: start, endAngle: start + 46)
                wedge.close()
                wedge.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// A wheel slice with rounded corners and a gap to its neighbours, like a glass segment.
/// Built as a thinner slice grown outward by `corner` in every direction (stroke + union),
/// which rounds every corner by exactly that radius.
struct RoundedSlice: Shape {
    var start: Angle
    var end: Angle
    var inner: CGFloat
    var outer: CGFloat
    var gap: CGFloat = 7
    var corner: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if end.degrees - start.degrees >= 359 {
            var ring = Path()
            ring.addArc(center: center, radius: outer, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            ring.addArc(center: center, radius: inner, startAngle: .degrees(360), endAngle: .zero, clockwise: true)
            return ring
        }
        // Each straight edge moves inward by `offset`; at radius r that's an angle of asin(offset / r).
        let offset = gap / 2 + corner
        let outerR = outer - corner, innerR = inner + corner
        guard outerR > innerR, offset < innerR else { return Path() }
        let outerTrim = asin(offset / outerR), innerTrim = asin(offset / innerR)
        let a0 = start.radians, a1 = end.radians
        guard a1 - a0 > 2 * innerTrim else { return Path() }

        var core = Path()
        core.addArc(center: center, radius: outerR, startAngle: .radians(a0 + outerTrim), endAngle: .radians(a1 - outerTrim), clockwise: false)
        core.addArc(center: center, radius: innerR, startAngle: .radians(a1 - innerTrim), endAngle: .radians(a0 + innerTrim), clockwise: true)
        core.closeSubpath()
        let grown = core.cgPath.copy(strokingWithWidth: corner * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return Path(core.cgPath.union(grown))
    }
}

/// The lime glass backdrop shared by Lime's windows.
struct LimeWindowBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.86, green: 0.97, blue: 0.55), Color(red: 0.56, green: 0.84, blue: 0.24),
                                Color(red: 0.27, green: 0.69, blue: 0.47)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(0.88)
            .background(Color.clear.glassEffect(.regular, in: .rect))
            .ignoresSafeArea()
    }
}

/// Dark green filled button, for the main action of a window.
struct LimeProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Theme.limeDeep.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: .capsule)
    }
}

/// Translucent glass capsule, for secondary buttons.
struct GlassPillButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? AnyShapeStyle(Theme.limeDeep) : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.35)), in: .capsule)
    }
}
