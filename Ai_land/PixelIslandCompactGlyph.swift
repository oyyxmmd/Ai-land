//
//  PixelIslandCompactGlyph.swift
//  Ai_land
//
//  收起态：十二生肖自绘圆角矢量小头像 + TimelineView 动态（呼吸、眨眼、摆尾等）。
//

import SwiftUI

enum PixelIslandCompactPhase: Equatable {
    case waiting
    case running
    /// `state=waiting_confirm`：警告感，与收起态橙调一致
    case waitingConfirm
    case completed
}

// MARK: - 尺寸（与旧 9×6 像素格外框一致）

private enum IslandCompactGlyphMetrics {
    static let cols = 9
    static let rows = 6
    static let pixel: CGFloat = 3.0
    static let gap: CGFloat = 0.55
    static var width: CGFloat { CGFloat(cols) * pixel + CGFloat(cols - 1) * gap }
    static var height: CGFloat { CGFloat(rows) * pixel + CGFloat(rows - 1) * gap }
}

// MARK: - 入口

struct PixelIslandCompactGlyph: View {
    let phase: PixelIslandCompactPhase
    var zodiac: IslandZodiac = .rat
    
    @Environment(\.aiLandReduceMotion) private var aiLandReduceMotion
    
    var body: some View {
        let avatar = TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: aiLandReduceMotion)) { context in
            ZodiacMiniAvatar(
                zodiac: zodiac,
                phase: phase,
                t: context.date.timeIntervalSinceReferenceDate
            )
        }
        .frame(width: IslandCompactGlyphMetrics.width, height: IslandCompactGlyphMetrics.height)
        
        // 完成态角标会略超出像素格；`drawingGroup` 会按边界裁切，故完成时不做离屏渲染。
        Group {
            if phase == .completed {
                avatar
            } else {
                avatar.drawingGroup(opaque: false)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 调色（沿用 IslandZodiacSprites）

private struct MiniPalette {
    let main: Color
    let light: Color
    let dark: Color
    let accent: Color
    
    init(z: IslandZodiac, phase: PixelIslandCompactPhase) {
        main = z.layerColor(1, phase: phase)
        light = z.layerColor(2, phase: phase)
        dark = z.layerColor(3, phase: phase)
        accent = z.layerColor(4, phase: phase)
    }
}

// MARK: - 单生肖画布

private struct ZodiacMiniAvatar: View {
    let zodiac: IslandZodiac
    let phase: PixelIslandCompactPhase
    let t: TimeInterval
    
    private var pal: MiniPalette { MiniPalette(z: zodiac, phase: phase) }
    
    /// 待确认仍用较明显的上下摆动；运行中改为「奔跑」节奏（横移 + 前倾 + 极小落地感）。
    private var runOrConfirm: Bool { phase == .running || phase == .waitingConfirm }
    private var spd: Double { runOrConfirm ? 7.2 : 2.9 }
    
    private var bob: CGFloat {
        switch phase {
        case .running:
            let stride = t * 15.0
            return CGFloat(sin(stride) * 0.62 + sin(stride * 2) * 0.28)
        case .waitingConfirm:
            return CGFloat(sin(t * spd) * 2.1)
        case .waiting, .completed:
            return CGFloat(sin(t * spd) * 1.05)
        }
    }
    
    private var breathe: CGFloat {
        switch phase {
        case .running:
            return 1.0 + CGFloat(sin(t * 10.2) * 0.042)
        case .waitingConfirm:
            return 1.0 + CGFloat(sin(t * 9.0) * 0.065)
        case .waiting, .completed:
            return 1.0 + CGFloat(sin(t * 4.2) * 0.038)
        }
    }
    
    private var jog: CGFloat {
        switch phase {
        case .running:
            let g = t * 12.5
            return CGFloat(sin(g) * 2.6 + cos(g * 0.5) * 0.95)
        case .waitingConfirm:
            return CGFloat(sin(t * 11.5) * 1.35)
        case .waiting, .completed:
            return 0
        }
    }
    
    /// 奔跑时身体略前倾左右换重心（绕偏下锚点）。
    private var runLeanDegrees: Double {
        guard phase == .running else { return 0 }
        return sin(t * 12.0) * 5.5
    }
    
    private var blink: Bool { Int(t * 2.8) % 11 == 10 }
    
    var body: some View {
        ZStack {
            if phase == .waitingConfirm {
                Circle()
                    .stroke(Color.orange.opacity(0.42 + 0.22 * sin(t * 5.2)), lineWidth: 1.35)
                    .frame(width: 30, height: 30)
                    .scaleEffect(1.0 + 0.05 * sin(t * 4.8))
            }
            Group {
                switch zodiac {
                case .rat: rat
                case .ox: ox
                case .tiger: tiger
                case .rabbit: rabbit
                case .dragon: dragon
                case .snake: snake
                case .horse: horse
                case .goat: goat
                case .monkey: monkey
                case .rooster: rooster
                case .dog: dog
                case .pig: pig
                }
            }
            .rotationEffect(.degrees(runLeanDegrees), anchor: UnitPoint(x: 0.5, y: 0.82))
            .offset(x: jog, y: bob)
            .scaleEffect(breathe)
            .shadow(color: shadowTint.opacity(phase == .completed ? 0.28 : 0.42), radius: 2.8, x: 0, y: 1)
            
            if phase == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white.opacity(0.95), Color(red: 0.28, green: 0.88, blue: 0.48))
                    .offset(x: 12, y: 9)
            }
        }
        .frame(width: IslandCompactGlyphMetrics.width, height: IslandCompactGlyphMetrics.height)
    }
    
    private var shadowTint: Color {
        switch phase {
        case .waiting: return Color(red: 0.5, green: 0.72, blue: 0.95)
        case .running: return IslandTheme.teal
        case .waitingConfirm: return Color.orange.opacity(0.95)
        case .completed: return Color.green
        }
    }
    
    // MARK: 鼠（大圆耳 + 尖吻 + 粗尾摆动，体量与虎/兔相当）
    
    private var rat: some View {
        let tailSwing = sin(t * 5.4) * 16.0
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: 7, y: 6))
                p.addQuadCurve(to: CGPoint(x: -6, y: 9), control: CGPoint(x: 1, y: 11))
            }
            .stroke(pal.dark, style: StrokeStyle(lineWidth: 1.55, lineCap: .round))
            .rotationEffect(.degrees(tailSwing), anchor: UnitPoint(x: 0.88, y: 0.25))
            Ellipse()
                .fill(pal.main)
                .frame(width: 12, height: 7)
                .offset(x: 4, y: 5)
            Circle()
                .fill(pal.main)
                .frame(width: 9, height: 9)
                .offset(x: -2, y: -1)
            Circle()
                .fill(pal.main)
                .frame(width: 5.5, height: 5.5)
                .offset(x: -5, y: -7)
            Circle()
                .fill(pal.main)
                .frame(width: 5.5, height: 5.5)
                .offset(x: 1, y: -7.5)
            Circle()
                .fill(pal.accent.opacity(0.45))
                .frame(width: 2.4, height: 2.4)
                .offset(x: -5, y: -7)
            Circle()
                .fill(pal.accent.opacity(0.45))
                .frame(width: 2.4, height: 2.4)
                .offset(x: 1, y: -7.5)
            Ellipse()
                .fill(pal.light.opacity(0.92))
                .frame(width: 5, height: 3.8)
                .offset(x: -6, y: 1)
            Circle()
                .fill(pal.dark)
                .frame(width: 1.8, height: 1.8)
                .offset(x: -8, y: 1.5)
            EyePair(dark: pal.dark, blink: blink)
                .offset(x: -2, y: -1.5)
        }
    }
    
    // MARK: 牛（宽鼻、双弯角向外上挑）
    
    private var ox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(pal.light.opacity(0.95))
                .frame(width: 15, height: 9)
                .offset(x: 0, y: -2)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(pal.main)
                .frame(width: 16, height: 8)
                .offset(x: 0, y: 6)
            Path { p in
                p.addArc(
                    center: CGPoint(x: -10, y: -2),
                    radius: 9,
                    startAngle: .degrees(155),
                    endAngle: .degrees(235),
                    clockwise: false
                )
            }
            .stroke(pal.dark, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Path { p in
                p.addArc(
                    center: CGPoint(x: 10, y: -2),
                    radius: 9,
                    startAngle: .degrees(305),
                    endAngle: .degrees(25),
                    clockwise: false
                )
            }
            .stroke(pal.dark, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            HStack(spacing: 3.5) {
                Circle().fill(pal.dark.opacity(0.45)).frame(width: 1.6, height: 1.6)
                Circle().fill(pal.dark.opacity(0.45)).frame(width: 1.6, height: 1.6)
            }
            .offset(x: 0, y: 8)
            EyePair(dark: pal.dark, blink: blink)
                .offset(x: 0, y: -1)
        }
    }
    
    // MARK: 虎
    
    private var tiger: some View {
        ZStack {
            Ellipse()
                .fill(pal.main)
                .frame(width: 15, height: 11)
                .offset(x: 1, y: 3)
            Circle()
                .fill(pal.main)
                .frame(width: 11, height: 11)
                .offset(x: -4, y: -2)
            Triangle()
                .fill(pal.dark)
                .frame(width: 3, height: 4)
                .offset(x: -7, y: -7)
            Triangle()
                .fill(pal.dark)
                .frame(width: 3, height: 4)
                .offset(x: -3, y: -8)
            Triangle()
                .fill(pal.dark)
                .frame(width: 3, height: 4)
                .offset(x: 1, y: -7)
            Ellipse().fill(pal.light).frame(width: 6, height: 4).offset(x: 3, y: 1)
            EyePair(dark: pal.dark, blink: blink).offset(x: -4, y: -2)
        }
    }
    
    // MARK: 兔
    
    private var rabbit: some View {
        let ear = CGFloat(sin(t * 4) * 2)
        return ZStack {
            Ellipse()
                .fill(pal.main)
                .frame(width: 5, height: 13)
                .offset(x: -5, y: -9 + ear)
            Ellipse()
                .fill(pal.main)
                .frame(width: 5, height: 13)
                .offset(x: 2, y: -9 - ear * 0.6)
            Circle()
                .fill(pal.light)
                .frame(width: 12, height: 12)
                .offset(x: 0, y: 2)
            Ellipse().fill(pal.accent.opacity(0.6)).frame(width: 4, height: 3).offset(x: 5, y: 3)
            EyePair(dark: pal.dark, blink: blink).offset(x: -1, y: 1)
        }
    }
    
    // MARK: 龙（小号：盘绕 C 形身 + 圆头吻 + 单角 + 双鳍 + 一颗珠）
    
    private var dragon: some View {
        let flow = CGFloat(sin(t * 3.4) * 0.75)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: -8, y: 5))
                p.addCurve(
                    to: CGPoint(x: 2, y: -2),
                    control1: CGPoint(x: -7, y: 0.5),
                    control2: CGPoint(x: -3, y: -3.5)
                )
                p.addCurve(
                    to: CGPoint(x: 7, y: 3),
                    control1: CGPoint(x: 5, y: -2 + flow * 0.3),
                    control2: CGPoint(x: 7, y: 0)
                )
            }
            .stroke(
                LinearGradient(colors: [pal.light, pal.main], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2.45, lineCap: .round, lineJoin: .round)
            )
            Triangle()
                .fill(pal.accent.opacity(0.9))
                .frame(width: 2, height: 2.35)
                .offset(x: -5, y: 2.2)
            Triangle()
                .fill(pal.accent.opacity(0.9))
                .frame(width: 2, height: 2.35)
                .offset(x: 0.8, y: -1.2)
            Circle()
                .fill(pal.light)
                .frame(width: 5.2, height: 5.2)
                .offset(x: 4.4, y: -3.6)
            Ellipse()
                .fill(pal.main.opacity(0.96))
                .frame(width: 3.4, height: 2.2)
                .offset(x: 6.5, y: -2.6)
            Path { p in
                p.move(to: CGPoint(x: 2.8, y: -7.2))
                p.addLine(to: CGPoint(x: 3.6, y: -10))
            }
            .stroke(pal.accent, style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
            .offset(x: 4, y: 0)
            Circle()
                .fill(Color.orange.opacity(0.76 + 0.2 * sin(t * 6)))
                .frame(width: 1.85, height: 1.85)
                .offset(x: -6.2, y: 3.8)
            EyePair(dark: pal.dark, blink: blink)
                .scaleEffect(0.76)
                .offset(x: 4.1, y: -4)
        }
    }
    
    // MARK: 蛇（小号：∞ 式盘绕 + 圆头 + 双点眼 + 短分叉舌）
    
    private var snake: some View {
        let sl = CGFloat(sin(t * 4) * 1.1)
        let tong = CGFloat(0.3 + 0.35 * sin(t * 7))
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: 6.5, y: -2.5))
                p.addCurve(
                    to: CGPoint(x: -2, y: 5.5),
                    control1: CGPoint(x: 4.5, y: 2.5 + sl * 0.12),
                    control2: CGPoint(x: 0, y: 6.5)
                )
                p.addCurve(
                    to: CGPoint(x: -6.5, y: -1),
                    control1: CGPoint(x: -5.5, y: 4.5),
                    control2: CGPoint(x: -7.5, y: 1.5)
                )
            }
            .stroke(
                LinearGradient(colors: [pal.light, pal.main], startPoint: .topTrailing, endPoint: .bottomLeading),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            Circle()
                .fill(pal.main)
                .frame(width: 4.2, height: 4.2)
                .offset(x: 6.8, y: -2.6)
            Path { p in
                p.move(to: CGPoint(x: 8.8, y: -1.2))
                p.addLine(to: CGPoint(x: 10.8, y: -2 - tong))
                p.move(to: CGPoint(x: 8.8, y: 0.2))
                p.addLine(to: CGPoint(x: 10.8, y: 1.2 + tong))
            }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            Circle()
                .fill(pal.dark)
                .frame(width: 1.05, height: 1.05)
                .offset(x: 7.6, y: -3.2)
            Circle()
                .fill(pal.dark)
                .frame(width: 1.05, height: 1.05)
                .offset(x: 7.6, y: -2)
        }
    }
    
    // MARK: 马（小号：马头侧影「逗号」+ 两笔鬃毛 + 立耳 + 吻部高光）
    
    private var horse: some View {
        let mane = CGFloat(sin(t * 4.6) * 0.55)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: -5.2, y: 4.2))
                p.addQuadCurve(to: CGPoint(x: 0.8, y: -2.8), control: CGPoint(x: -4.8, y: -0.2))
                p.addQuadCurve(to: CGPoint(x: 6.5, y: 0.2), control: CGPoint(x: 4, y: -4.2))
                p.addQuadCurve(to: CGPoint(x: 6.2, y: 4), control: CGPoint(x: 7.2, y: 2.5))
                p.addQuadCurve(to: CGPoint(x: 0.8, y: 5.2), control: CGPoint(x: 4.2, y: 5.8))
                p.addQuadCurve(to: CGPoint(x: -5.2, y: 4.2), control: CGPoint(x: -2.2, y: 5.8))
                p.closeSubpath()
            }
            .fill(pal.main)
            Path { p in
                p.move(to: CGPoint(x: -1.8, y: -3.5))
                p.addQuadCurve(to: CGPoint(x: -3.8, y: -7.2 + mane), control: CGPoint(x: -1.5, y: -5.5))
                p.move(to: CGPoint(x: 0.6, y: -3.8))
                p.addQuadCurve(to: CGPoint(x: -0.8, y: -7.4 - mane * 0.4), control: CGPoint(x: 1.2, y: -5.6))
            }
            .stroke(pal.dark.opacity(0.82), style: StrokeStyle(lineWidth: 1.05, lineCap: .round))
            Triangle()
                .fill(pal.main)
                .frame(width: 2.6, height: 3.8)
                .offset(x: -2.6, y: -5.8)
            Triangle()
                .fill(pal.main)
                .frame(width: 2.6, height: 3.8)
                .offset(x: 0.6, y: -5.8)
            Ellipse()
                .fill(pal.light.opacity(0.9))
                .frame(width: 4.2, height: 2.4)
                .offset(x: 4.8, y: 1.8)
            EyePair(dark: pal.dark, blink: blink)
                .scaleEffect(0.8)
                .offset(x: 1.2, y: -1)
        }
    }
    
    // MARK: 羊
    
    private var goat: some View {
        ZStack {
            Circle()
                .fill(pal.light)
                .frame(width: 12, height: 12)
                .offset(x: 0, y: 2)
            Path { p in
                p.move(to: CGPoint(x: -6, y: -4))
                p.addQuadCurve(to: CGPoint(x: -9, y: -11), control: CGPoint(x: -11, y: -7))
            }
            .stroke(pal.dark, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 4, y: -4))
                p.addQuadCurve(to: CGPoint(x: 9, y: -10), control: CGPoint(x: 11, y: -6))
            }
            .stroke(pal.dark, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            Ellipse().fill(pal.main.opacity(0.9)).frame(width: 6, height: 4).offset(x: 4, y: 4)
            EyePair(dark: pal.dark, blink: blink).offset(x: -1, y: 1)
        }
    }
    
    // MARK: 猴
    
    private var monkey: some View {
        let tilt = CGFloat(sin(t * 5) * 4)
        return ZStack {
            Circle()
                .fill(pal.main)
                .frame(width: 13, height: 13)
                .offset(x: 0, y: 1)
            Circle().fill(pal.main).frame(width: 5, height: 5).offset(x: -8, y: 0).rotationEffect(.degrees(Double(tilt)))
            Circle().fill(pal.main).frame(width: 5, height: 5).offset(x: 8, y: 0).rotationEffect(.degrees(-Double(tilt)))
            Ellipse()
                .fill(pal.light.opacity(0.95))
                .frame(width: 9, height: 8)
                .offset(x: 0, y: 2)
            EyePair(dark: pal.dark, blink: blink).offset(x: 0, y: 0)
        }
    }
    
    // MARK: 鸡
    
    private var rooster: some View {
        ZStack {
            Ellipse()
                .fill(pal.main)
                .frame(width: 13, height: 11)
                .offset(x: 0, y: 3)
            Path { p in
                p.move(to: CGPoint(x: -2, y: -8))
                p.addLine(to: CGPoint(x: 0, y: -14))
                p.addLine(to: CGPoint(x: 2, y: -8))
                p.addLine(to: CGPoint(x: 4, y: -13))
                p.addLine(to: CGPoint(x: 5, y: -7))
            }
            .fill(pal.accent)
            Triangle()
                .fill(Color.orange.opacity(0.95))
                .frame(width: 5, height: 4)
                .offset(x: 8, y: 2)
            EyePair(dark: pal.dark, blink: blink).offset(x: -1, y: 2)
        }
    }
    
    // MARK: 狗（圆头、下垂大耳、前伸吻部与鼻）
    
    private var dog: some View {
        let flop = CGFloat(sin(t * 4.2) * 4)
        return ZStack {
            Circle()
                .fill(pal.main)
                .frame(width: 12, height: 12)
                .offset(x: -2, y: 1)
            Ellipse()
                .fill(pal.light.opacity(0.95))
                .frame(width: 11, height: 7)
                .offset(x: 7, y: 3)
            Circle()
                .fill(pal.dark.opacity(0.35))
                .frame(width: 2.2, height: 2.2)
                .offset(x: 12, y: 3)
            Path { p in
                p.move(to: CGPoint(x: -10, y: -4))
                p.addQuadCurve(to: CGPoint(x: -11, y: 6), control: CGPoint(x: -14, y: 1))
                p.addQuadCurve(to: CGPoint(x: -6, y: 8), control: CGPoint(x: -9, y: 8))
            }
            .fill(pal.dark.opacity(0.88))
            .rotationEffect(.degrees(Double(flop) * 0.12))
            Path { p in
                p.move(to: CGPoint(x: 4, y: -4))
                p.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 9, y: 1))
                p.addQuadCurve(to: CGPoint(x: -1, y: 8), control: CGPoint(x: 2, y: 8))
            }
            .fill(pal.dark.opacity(0.88))
            .rotationEffect(.degrees(-Double(flop) * 0.1))
            EyePair(dark: pal.dark, blink: blink)
                .offset(x: -2, y: -1)
        }
    }
    
    // MARK: 猪
    
    private var pig: some View {
        let curl = CGFloat(sin(t * 4) * 8)
        return ZStack {
            Ellipse()
                .fill(pal.main)
                .frame(width: 15, height: 12)
                .offset(x: 0, y: 2)
            Ellipse()
                .stroke(pal.dark.opacity(0.55), lineWidth: 1)
                .frame(width: 7, height: 5)
                .offset(x: 6, y: 3)
            Path { p in
                let start = Angle.degrees(20 + Double(curl))
                let end = Angle.degrees(200 + Double(curl) * 0.5)
                p.addArc(center: CGPoint(x: -10, y: 6), radius: 4, startAngle: start, endAngle: end, clockwise: false)
            }
            .stroke(pal.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            EyePair(dark: pal.dark, blink: blink).offset(x: -2, y: 0)
        }
    }
}

// MARK: - 小组件

private struct EyePair: View {
    let dark: Color
    let blink: Bool
    
    var body: some View {
        HStack(spacing: 3.2) {
            Capsule()
                .fill(dark)
                .frame(width: blink ? 2.2 : 2, height: blink ? 0.6 : 2)
            Capsule()
                .fill(dark)
                .frame(width: blink ? 2.2 : 2, height: blink ? 0.6 : 2)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
