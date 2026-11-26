import SwiftUI

struct NordicPalette {
    let dark: Bool
    var christmas: Bool {
        let date = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: Date())
        guard let month = date.month, let day = date.day else { return false }
        return (month == 11 && day >= 25) || month == 12 || (month == 1 && day <= 6)
    }

    private func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }

    var paper: Color { christmas ? rgb(dark ? 0x202A24 : 0xFFF8ED) : rgb(dark ? 0x202724 : 0xF6F4EE) }
    var ink: Color { christmas ? rgb(dark ? 0xFFF3DF : 0x302821) : rgb(dark ? 0xF1F0E8 : 0x202B28) }
    var muted: Color { christmas ? rgb(dark ? 0xD3C9B9 : 0x62534A) : rgb(dark ? 0xBDC9C1 : 0x52605A) }
    var pine: Color { christmas ? rgb(dark ? 0xB5D9BD : 0x194B38) : rgb(dark ? 0xAED5BD : 0x17483D) }
    var onPine: Color { dark ? rgb(0x172E24) : .white }
    var line: Color { christmas ? rgb(dark ? 0x59685B : 0xDBCAB5) : rgb(dark ? 0x46574E : 0xD4D8CE) }
    var wash: Color { christmas ? rgb(dark ? 0x34473A : 0xE5EDDF) : rgb(dark ? 0x303F36 : 0xE7EDE4) }
    var water: Color { christmas ? rgb(dark ? 0x315B49 : 0xA8C6B8) : rgb(dark ? 0x334D4B : 0xCDDCDA) }
    var land: Color { christmas ? rgb(dark ? 0x414E38 : 0xE9DFC8) : wash }
    var primary: Color { christmas ? rgb(dark ? 0xAE3E54 : 0x8B263B) : pine }
    var onPrimary: Color { christmas ? rgb(dark ? 0xFFF9EE : 0xFFF8ED) : onPine }
    var festiveInk: Color { christmas ? rgb(dark ? 0xF0A9B5 : 0x8B263B) : pine }
    var gold: Color { christmas ? rgb(dark ? 0xE4BD76 : 0xAA7934) : line }
}

struct NordicButton: ButtonStyle {
    let palette: NordicPalette
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? palette.onPrimary : palette.pine)
            .padding(.horizontal,16).padding(.vertical,13)
            .frame(minHeight:48)
            .background(primary ? palette.primary : Color.clear, in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(primary ? palette.primary : palette.pine,lineWidth:1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:configuration.isPressed)
    }
}

// Decorative contour graphic; intentionally not a map or a simulated location.
struct ContourArt: View {
    let palette: NordicPalette
    var body: some View {
        Canvas { context,size in
            let w=size.width, h=size.height
            var water=Path()
            water.move(to:CGPoint(x:w*0.48,y:0))
            water.addCurve(to:CGPoint(x:w*0.35,y:h),control1:CGPoint(x:w*0.8,y:h*0.30),control2:CGPoint(x:w*0.02,y:h*0.58))
            water.addLine(to:CGPoint(x:w,y:h)); water.addLine(to:CGPoint(x:w,y:0)); water.closeSubpath()
            context.fill(water,with:.color(palette.water))
            for i in 0..<8 {
                let x=CGFloat(i)*w*0.13-w*0.28
                var line=Path()
                line.move(to:CGPoint(x:x,y:-10))
                line.addCurve(to:CGPoint(x:x+w*0.48,y:h+10),control1:CGPoint(x:x+w*0.7,y:h*0.24),control2:CGPoint(x:x+w*0.02,y:h*0.74))
                context.stroke(line,with:.color(palette.pine.opacity(0.30)),lineWidth:0.8)
            }
            // Still, abstract winter details. No animation or network resources.
            if palette.christmas {
                var pines=Path()
                for (x,scale) in [(w*0.13,CGFloat(1)),(w*0.23,CGFloat(0.75))] {
                    let y=h*0.88
                    pines.move(to:CGPoint(x:x,y:y))
                    pines.addLine(to:CGPoint(x:x,y:y-48*scale))
                    for (level,half) in [(CGFloat(12),CGFloat(8)),(23,12),(34,16)] {
                        let top=y-(48-level)*scale
                        pines.move(to:CGPoint(x:x,y:top-8*scale))
                        pines.addLine(to:CGPoint(x:x-half*scale,y:top+3*scale))
                        pines.move(to:CGPoint(x:x,y:top-8*scale))
                        pines.addLine(to:CGPoint(x:x+half*scale,y:top+3*scale))
                    }
                }
                context.stroke(pines,with:.color(palette.pine),style:StrokeStyle(lineWidth:1.25,lineCap:.round,lineJoin:.round))
                let gold = palette.gold
                let sx=w*0.87,sy=h*0.22
                var star=Path()
                star.move(to:CGPoint(x:sx-8,y:sy));star.addLine(to:CGPoint(x:sx+8,y:sy))
                star.move(to:CGPoint(x:sx,y:sy-8));star.addLine(to:CGPoint(x:sx,y:sy+8))
                star.move(to:CGPoint(x:sx-4,y:sy-4));star.addLine(to:CGPoint(x:sx+4,y:sy+4))
                star.move(to:CGPoint(x:sx-4,y:sy+4));star.addLine(to:CGPoint(x:sx+4,y:sy-4))
                context.stroke(star,with:.color(gold),style:StrokeStyle(lineWidth:1.8,lineCap:.round))
                var snow=Path()
                snow.move(to:CGPoint(x:w*0.05,y:h*0.91))
                snow.addQuadCurve(to:CGPoint(x:w*0.34,y:h*0.91),control:CGPoint(x:w*0.20,y:h*0.84))
                context.stroke(snow,with:.color(palette.paper.opacity(0.9)),lineWidth:1.5)
            }
            let center=CGPoint(x:w*0.68,y:h*0.48)
            for r in [CGFloat(28),CGFloat(44)] {
                let ring=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2))
                context.stroke(ring,with:.color(palette.pine.opacity(0.48)),lineWidth:1)
            }
            context.fill(Path(ellipseIn:CGRect(x:center.x-16,y:center.y-16,width:32,height:32)),with:.color(palette.primary))
            var cross=Path()
            cross.move(to:CGPoint(x:center.x-7,y:center.y));cross.addLine(to:CGPoint(x:center.x+7,y:center.y))
            cross.move(to:CGPoint(x:center.x,y:center.y-7));cross.addLine(to:CGPoint(x:center.x,y:center.y+7))
            context.stroke(cross,with:.color(palette.onPrimary),lineWidth:2)
        }
        .background(palette.land)
        .overlay(Rectangle().strokeBorder(palette.gold,lineWidth:1))
        .frame(height:128)
        .accessibilityHidden(true)
    }
}

