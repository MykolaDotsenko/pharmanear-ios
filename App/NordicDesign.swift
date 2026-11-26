import SwiftUI

struct NordicPalette {
    let dark: Bool
    var paper: Color { dark ? Color(red:0.125,green:0.153,blue:0.141) : Color(red:0.965,green:0.957,blue:0.933) }
    var ink: Color { dark ? Color(red:0.945,green:0.941,blue:0.91) : Color(red:0.125,green:0.169,blue:0.157) }
    var muted: Color { dark ? Color(red:0.741,green:0.788,blue:0.757) : Color(red:0.322,green:0.376,blue:0.353) }
    var pine: Color { dark ? Color(red:0.682,green:0.835,blue:0.741) : Color(red:0.09,green:0.282,blue:0.239) }
    var onPine: Color { dark ? Color(red:0.09,green:0.18,blue:0.14) : .white }
    var line: Color { dark ? Color(red:0.275,green:0.341,blue:0.306) : Color(red:0.831,green:0.847,blue:0.808) }
    var wash: Color { dark ? Color(red:0.188,green:0.247,blue:0.212) : Color(red:0.906,green:0.929,blue:0.894) }
    var water: Color { dark ? Color(red:0.20,green:0.30,blue:0.29) : Color(red:0.804,green:0.863,blue:0.855) }
}

struct NordicButton: ButtonStyle {
    let palette: NordicPalette
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? palette.onPine : palette.pine)
            .padding(.horizontal,16).padding(.vertical,13)
            .frame(minHeight:48)
            .background(primary ? palette.pine : Color.clear, in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(palette.pine,lineWidth:1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:configuration.isPressed)
    }
}

// Decorative contour graphic; intentionally not a map or a simulated location.
struct ContourArt: View {
    let palette: NordicPalette
    private var christmas: Bool {
        let date=Calendar(identifier:.gregorian).dateComponents([.month,.day],from:Date())
        guard let month=date.month,let day=date.day else { return false }
        return (month == 11 && day >= 25) || month == 12 || (month == 1 && day <= 6)
    }
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
            if christmas {
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
                context.stroke(pines,with:.color(palette.pine.opacity(0.72)),style:StrokeStyle(lineWidth:1.25,lineCap:.round,lineJoin:.round))
                let gold=palette.dark ? Color(red:0.83,green:0.71,blue:0.47) : Color(red:0.58,green:0.45,blue:0.26)
                let sx=w*0.87,sy=h*0.22
                var star=Path()
                star.move(to:CGPoint(x:sx-8,y:sy));star.addLine(to:CGPoint(x:sx+8,y:sy))
                star.move(to:CGPoint(x:sx,y:sy-8));star.addLine(to:CGPoint(x:sx,y:sy+8))
                star.move(to:CGPoint(x:sx-4,y:sy-4));star.addLine(to:CGPoint(x:sx+4,y:sy+4))
                star.move(to:CGPoint(x:sx-4,y:sy+4));star.addLine(to:CGPoint(x:sx+4,y:sy-4))
                context.stroke(star,with:.color(gold),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
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
            context.fill(Path(ellipseIn:CGRect(x:center.x-16,y:center.y-16,width:32,height:32)),with:.color(palette.pine))
            var cross=Path()
            cross.move(to:CGPoint(x:center.x-7,y:center.y));cross.addLine(to:CGPoint(x:center.x+7,y:center.y))
            cross.move(to:CGPoint(x:center.x,y:center.y-7));cross.addLine(to:CGPoint(x:center.x,y:center.y+7))
            context.stroke(cross,with:.color(palette.onPine),lineWidth:2)
        }
        .background(palette.wash)
        .overlay(Rectangle().strokeBorder(palette.line,lineWidth:1))
        .frame(height:128)
        .accessibilityHidden(true)
    }
}

