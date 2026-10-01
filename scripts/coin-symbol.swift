import CoreGraphics
import Foundation

// Coin stack: three flat coins, offset like a real pile (the mockup's draft,
// picked 2026-09-30). Design grid is the 64-unit draft; y grows downward.
let coins: [(CGFloat, CGFloat)] = [(28, 46), (36, 35), (30, 24)]   // bottom -> top, top-face centre
let rx: CGFloat = 19, ry: CGFloat = 6.5, th: CGFloat = 6.5
let minX: CGFloat = 9, maxX: CGFloat = 55, minY: CGFloat = 17.5, maxY: CGFloat = 59

func coinLines(_ cx: CGFloat, _ cy: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    // sides and the lower rim of the bottom face
    p.move(to: CGPoint(x: cx - rx, y: cy))
    p.addLine(to: CGPoint(x: cx - rx, y: cy + th))
    p.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: true,
             transform: CGAffineTransform(a: rx, b: 0, c: 0, d: ry, tx: cx, ty: cy + th))
    p.addLine(to: CGPoint(x: cx + rx, y: cy))
    return p
}
func silhouette(_ cx: CGFloat, _ cy: CGFloat, pad: CGFloat) -> CGPath {
    let a = CGPath(ellipseIn: CGRect(x: cx - rx - pad, y: cy - ry - pad, width: 2 * (rx + pad), height: 2 * (ry + pad)), transform: nil)
    let b = CGPath(rect: CGRect(x: cx - rx - pad, y: cy, width: 2 * (rx + pad), height: th), transform: nil)
    let c = CGPath(ellipseIn: CGRect(x: cx - rx - pad, y: cy + th - ry - pad, width: 2 * (rx + pad), height: 2 * (ry + pad)), transform: nil)
    return a.union(b).union(c)
}

/// The glyph's ink in design units for one stroke width.
func ink(stroke w: CGFloat) -> CGPath {
    var out = CGMutablePath() as CGPath
    for (i, (cx, cy)) in coins.enumerated() {
        var coin = coinLines(cx, cy).copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
        for (ax, ay) in coins[(i + 1)...] { coin = coin.subtracting(silhouette(ax, ay, pad: w * 0.76)) }
        out = out.union(coin)
    }
    return out
}

func svgPath(_ path: CGPath, scale s: CGFloat, dx: CGFloat, dy: CGFloat) -> String {
    var d = ""
    func f(_ v: CGFloat) -> String { String(format: "%.4g", Double(v)) }
    func pt(_ p: CGPoint) -> String { "\(f(p.x * s + dx)) \(f(p.y * s + dy))" }
    path.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M \(pt(pts[0])) "
        case .addLineToPoint: d += "L \(pt(pts[0])) "
        case .addQuadCurveToPoint: d += "Q \(pt(pts[0])) \(pt(pts[1])) "
        case .addCurveToPoint: d += "C \(pt(pts[0])) \(pt(pts[1])) \(pt(pts[2])) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    return d
}

// Template geometry (SF Symbols template writer version 2).
let columns: [(String, CGFloat, CGFloat)] = [   // weight, column centre, stroke at M (units at 100pt)
    ("Ultralight", 559.711, 1.5), ("Thin", 856.422, 2.4), ("Light", 1153.13, 3.6),
    ("Regular", 1449.84, 4.8), ("Medium", 1746.56, 5.5), ("Semibold", 2043.27, 6.2),
    ("Bold", 2339.98, 7.2), ("Heavy", 2636.69, 8.4), ("Black", 2933.4, 9.6)]
let scales: [(String, CGFloat, CGFloat, CGFloat)] = [  // scale, baseline, size factor, stroke factor
    ("S", 696, 0.79, 0.9), ("M", 1126, 1.0, 1.0), ("L", 1556, 1.29, 1.1)]
let heightM: CGFloat = 80          // glyph height at M, cap height is 70.46
let bottomM: CGFloat = 5           // below the baseline, as a round glyph overshoots

var symbols = ""
var marginsM = ""
for (scaleName, baseline, factor, strokeFactor) in scales {
    let s = heightM * factor / (maxY - minY)
    for (weight, centre, strokeM) in columns {
        let w = strokeM * factor * strokeFactor / s          // stroke in design units
        // the ink grows by half a stroke on each side
        let width = (maxX - minX + w) * s
        let originX = centre - width / 2
        let dx = -(minX - w / 2) * s
        let dy = -(maxY + w / 2) * s + bottomM * factor
        let d = svgPath(ink(stroke: w), scale: s, dx: dx, dy: dy)
        symbols += "  <g id=\"\(weight)-\(scaleName)\" transform=\"matrix(1 0 0 1 \(originX) \(baseline))\">\n   <path d=\"\(d)\"/>\n  </g>\n"
        if weight == "Regular" && scaleName == "M" {
            let left = originX - 4, right = originX + width + 4
            marginsM = """
              <rect height="119.336" id="left-margin" style="fill:#00AEEF;stroke:none;opacity:0.4;" width="8" x="\(left - 8)" y="1030.79"/>
              <rect height="119.336" id="right-margin" style="fill:#00AEEF;stroke:none;opacity:0.4;" width="8" x="\(right)" y="1030.79"/>
            """
        }
    }
}

let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<!--Generator: Casberi scripts/coin-symbol (CoreGraphics), 2026-09-30-->
<!DOCTYPE svg
PUBLIC "-//W3C//DTD SVG 1.1//EN"
       "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--glyph: "coins.stack", point size: 100.000000, template writer version: "2"-->
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
 </g>
 <g id="Guides">
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
\(marginsM)
 </g>
 <g id="Symbols">
\(symbols) </g>
</svg>
"""
print(svg)
