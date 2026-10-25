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
