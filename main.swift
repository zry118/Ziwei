import SwiftUI
import AppKit

// MARK: - 配色

enum Ink {
    // 深空
    static let bgDeep  = Color(red: 0.024, green: 0.024, blue: 0.031)
    static let panel   = Color(red: 0.043, green: 0.041, blue: 0.051)
    static let cell    = Color(red: 0.062, green: 0.059, blue: 0.071)
    static let cellLit = Color(red: 0.106, green: 0.090, blue: 0.071)

    static let gold     = Color(red: 0.847, green: 0.682, blue: 0.416)
    static let goldDim  = Color(red: 0.784, green: 0.631, blue: 0.361)
    static let hairline = Color(red: 0.784, green: 0.631, blue: 0.361).opacity(0.18)

    // 星曜按性质分色
    static let cinnabar = Color(red: 0.855, green: 0.353, blue: 0.278)   // 十四主星
    static let jade     = Color(red: 0.435, green: 0.729, blue: 0.655)   // 六吉
    static let obsidian = Color(red: 0.647, green: 0.663, blue: 0.718)   // 六煞
    static let mauve    = Color(red: 0.706, green: 0.588, blue: 0.769)   // 杂曜

    static let paper = Color(red: 0.906, green: 0.875, blue: 0.812)
    static let dim   = Color(red: 0.545, green: 0.529, blue: 0.584)

    static func hua(_ s: String) -> Color {
        switch s {
        case "禄": return Color(red: 0.404, green: 0.741, blue: 0.478)
        case "权": return Color(red: 0.706, green: 0.529, blue: 0.886)
        case "科": return Color(red: 0.416, green: 0.667, blue: 0.890)
        default:   return Color(red: 0.898, green: 0.361, blue: 0.318)
        }
    }

    static func starColor(_ kind: StarKind) -> Color {
        switch kind {
        case .major: return cinnabar
        case .lucky: return jade
        case .evil:  return obsidian
        case .misc:  return mauve
        }
    }
}

// MARK: - 状态

/// 离屏渲染时用来注入初始生日（屏幕锁着也能出图）
enum RenderConfig {
    static var seed: BirthInput? = nil
    /// 离屏渲染时 AppKit 控件（TextField / Menu）画不出来，会变成禁止符号，
    /// 所以渲染模式下换成纯文本
    static var isRendering = false
}

final class AppModel: ObservableObject {
    @Published var year = 1990 { didSet { refresh() } }
    @Published var month = 1 { didSet { refresh() } }
    @Published var day = 1 { didSet { refresh() } }
    /// 时辰序号：0 早子，1 丑 … 11 亥，12 晚子
    @Published var hourSlot = 6 { didSet { refresh() } }
    @Published var gender: Gender = .male { didSet { refresh() } }
    @Published var lunarInput = false { didSet { refresh() } }
    @Published private(set) var chart: Chart = Paipan.build(BirthInput())
    /// 载入进度，0 → 1。十二宫按对角线顺序依次亮起
    @Published var reveal = RenderConfig.isRendering ? 1.0 : 0.0

    /// 时辰序号 → 小时
    static let slotHours = [0, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23]
    static let slotNames = ["早子时", "丑时", "寅时", "卯时", "辰时", "巳时",
                            "午时", "未时", "申时", "酉时", "戌时", "亥时", "晚子时"]

    init() {
        if let seed = RenderConfig.seed {
            year = seed.year
            month = seed.month
            day = seed.day
            gender = seed.gender
            lunarInput = seed.lunarInput
            hourSlot = seed.hour == 23 ? 12 : hourBranch(seed.hour)
        }
        refresh()
    }

    func refresh() {
        var i = BirthInput()
        i.year = year
        i.month = month
        i.day = day
        i.hour = Self.slotHours[min(max(hourSlot, 0), 12)]
        i.gender = gender
        i.lunarInput = lunarInput
        chart = Paipan.build(i)
    }

    func useNow() {
        let cal = Paipan.solarCal
        let c = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        lunarInput = false
        year = c.year ?? 1990
        month = c.month ?? 1
        day = c.day ?? 1
        let h = c.hour ?? 12
        hourSlot = h == 23 ? 12 : (h == 0 ? 0 : (h + 1) / 2)
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        // 窗口宽度决定排版：窄了就是手机模式，拉宽自动回到宽屏
        GeometryReader { g in
            ZStack {
                Starfield().ignoresSafeArea()
                RadialGradient(colors: [Color.clear, Ink.bgDeep.opacity(0.55), Ink.bgDeep],
                               center: .center, startRadius: 0, endRadius: 700)
                    .ignoresSafeArea()

                if g.size.width >= 880 {
                    HStack(spacing: 0) {
                        SidePanel(model: model)
                            .frame(width: 272)
                        Rectangle().fill(Ink.hairline).frame(width: 1)
                        ChartBoard(model: model)
                            .padding(20)
                    }
                } else {
                    PhoneLayout(model: model)
                }
            }
        }
        .onAppear {
            if !RenderConfig.isRendering {
                withAnimation(.easeOut(duration: 1.1)) { model.reveal = 1.0 }
            }
        }
    }
}

// MARK: - 星图背景

/// 可复现的伪随机，保证每次渲染出的星空一致
final class StarClock: ObservableObject {
    @Published var t: Double = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let tm = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.t += 1.0 / 30.0
        }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct Starfield: View {
    @StateObject private var clock = StarClock()
    let stars: [(x: Double, y: Double, r: Double, base: Double, speed: Double)]

    init() {
        var seed: UInt64 = 20240712
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        stars = (0..<260).map { i in
            (x: next(), y: next(), r: 0.5 + next() * 1.5,
             base: 0.10 + next() * 0.34,
             speed: 0.4 + next() * 1.8 + (i % 3 == 0 ? 0.6 : 0))
        }
    }

    var body: some View {
        Canvas { ctx, size in
            for (i, st) in stars.enumerated() {
                let tw = sin(clock.t * st.speed + Double(i) * 0.7) * 0.5 + 0.5
                let a = st.base * (0.30 + 0.70 * tw)
                let p = CGPoint(x: st.x * size.width, y: st.y * size.height)
                let r = st.r * (0.85 + tw * 0.3)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(a)))
            }
        }
        .onAppear { if !RenderConfig.isRendering { clock.start() } }
        .onDisappear { clock.stop() }
    }
}

// MARK: - 命盘

struct ChartBoard: View {
    @ObservedObject var model: AppModel

    private static let grid: [(row: Int, col: Int, branch: Int)] = [
        (0, 0, 5), (0, 1, 6), (0, 2, 7), (0, 3, 8),
        (1, 0, 4),                          (1, 3, 9),
        (2, 0, 3),                          (2, 3, 10),
        (3, 0, 2), (3, 1, 1), (3, 2, 0), (3, 3, 11),
    ]

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let cw = side / 4
            ZStack(alignment: .topLeading) {
                // offset 不参与布局，必须放个等尺寸占位，否则整盘会偏
                Color.clear.frame(width: side, height: side)
                ForEach(Array(Self.grid.enumerated()), id: \.offset) { idx, item in
                    PalaceCell(palace: model.chart.palaces[item.branch],
                               index: idx, reveal: model.reveal)
                        .frame(width: cw, height: cw)
                        .offset(x: CGFloat(item.col) * cw, y: CGFloat(item.row) * cw)
                }
                CenterInfo(chart: model.chart, reveal: model.reveal)
                    .frame(width: cw * 2, height: cw * 2)
                    .offset(x: cw, y: cw)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PalaceCell: View {
    let palace: Palace
    let index: Int
    let reveal: Double

    /// 宽屏模式一格的基准宽度，字号按实际格宽相对它缩放。
    /// 手机模式一格只有 100pt 上下，不缩字号整行会挤出格子。
    private let refCell: CGFloat = 185

    /// 格子按对角线顺序依次亮起
    private var appear: Double {
        let d = Double(index) * 0.05
        return min(max((reveal - d) / (1 - d), 0), 1)
    }

    var body: some View {
        GeometryReader { g in
            let k = min(1.0, max(0.56, g.size.width / refCell))
            cell(k)
        }
    }

    @ViewBuilder
    private func cell(_ k: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(palace.isMing ? Ink.cellLit : Ink.cell)
                .opacity(0.96)

            // 命宫外发光
            if palace.isMing {
                Rectangle()
                    .fill(Ink.goldDim.opacity(0.10 * appear))
                    .blur(radius: 14)
                    .padding(-8)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5 * k) {
                    Text(palace.name)
                        .font(.system(size: 13 * k, weight: palace.isMing ? .semibold : .regular,
                                      design: .serif))
                        .foregroundStyle(palace.isMing ? Ink.gold : Ink.paper.opacity(0.82))
                    if palace.isShen {
                        Text("身")
                            .font(.system(size: 8.5 * k, design: .serif))
                            .foregroundStyle(Ink.cinnabar)
                            .padding(.horizontal, 3 * k)
                            .overlay(Rectangle().stroke(Ink.cinnabar.opacity(0.5), lineWidth: 0.8))
                    }
                    Spacer(minLength: 2)
                    Text(palace.ganZhi)
                        .font(.system(size: 11 * k, design: .serif))
                        .foregroundStyle(Ink.dim.opacity(0.9))
                }

                Spacer().frame(height: 14 * k)

                FlowRow(spacing: 9 * k) {
                    ForEach(palace.majorStars, id: \.name) { s in
                        starLabel(s, major: true, k: k)
                    }
                }

                Spacer().frame(height: 9 * k)

                FlowRow(spacing: 6 * k) {
                    ForEach(palace.minorStars, id: \.name) { s in
                        starLabel(s, major: false, k: k)
                    }
                }

                Spacer(minLength: 4)

                Text("\(palace.decadeFrom)–\(palace.decadeTo)")
                    .font(.system(size: 10 * k, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.5))
            }
            .padding(10 * k)

            cornerMarks(k)
        }
        .overlay(
            Rectangle().stroke(palace.isMing ? Ink.gold.opacity(0.65 * appear) : Ink.hairline,
                               lineWidth: palace.isMing ? 1.3 : 1)
        )
        .opacity(appear)
    }

    /// 四角装饰短线，像古籍的边框
    private func cornerMarks(_ k: CGFloat) -> some View {
        let len: CGFloat = 13 * k
        let color = Ink.goldDim.opacity(palace.isMing ? 0.55 : 0.28)
        return Canvas { ctx, size in
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: len, y: 0))
                p.move(to: CGPoint(x: size.width - len, y: 0)); p.addLine(to: CGPoint(x: size.width, y: 0))
                p.addLine(to: CGPoint(x: size.width, y: len))
                p.move(to: CGPoint(x: size.width, y: size.height - len))
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.addLine(to: CGPoint(x: size.width - len, y: size.height))
                p.move(to: CGPoint(x: len, y: size.height)); p.addLine(to: CGPoint(x: 0, y: size.height))
                p.addLine(to: CGPoint(x: 0, y: size.height - len))
            }, with: .color(color), lineWidth: 1)
        }
    }

    private func starLabel(_ s: Star, major: Bool, k: CGFloat) -> some View {
        HStack(spacing: 2 * k) {
            Text(s.name)
                .font(.system(size: (major ? 18 : 12) * k,
                              weight: major ? .medium : .regular,
                              design: .serif))
                .foregroundStyle(Ink.starColor(s.kind).opacity(major ? 1.0 : 0.78))
            if let h = s.hua {
                Text(h)
                    .font(.system(size: 9 * k, weight: .medium, design: .serif))
                    .foregroundStyle(Ink.hua(h))
            }
        }
        .fixedSize()
    }
}

/// 简易流式布局：一行放不下就换行
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                x = 0; y += lineH + spacing * 0.55; lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX; y += lineH + spacing * 0.55; lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - 中宫

struct CenterInfo: View {
    let chart: Chart
    let reveal: Double

    /// 中宫基准宽度（宽屏下两格宽），手机模式缩一半
    private let refCenter: CGFloat = 370

    var body: some View {
        GeometryReader { g in
            let k = min(1.0, max(0.62, g.size.width / refCenter))
            body(k)
        }
    }

    @ViewBuilder
    private func body(_ k: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Ink.panel)

            // 中宫背后的淡金光晕
            RadialGradient(colors: [Ink.goldDim.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 200)

            VStack(spacing: 0) {
                Spacer()

                Taichi(size: 74 * k)
                    .opacity(0.9)

                Text("紫 微 命 盤")
                    .font(.system(size: 19 * k, weight: .light, design: .serif))
                    .foregroundStyle(Ink.gold)
                    .tracking(2 * k)
                    .padding(.top, 14 * k)

                Rectangle()
                    .fill(Ink.goldDim.opacity(0.35))
                    .frame(width: 52 * k, height: 1)
                    .padding(.vertical, 12 * k)

                Text(chart.solarText + "　" + hourBranchName(chart.input.hour))
                    .font(.system(size: 12.5 * k, design: .serif))
                    .foregroundStyle(Ink.paper.opacity(0.9))
                Text(chart.lunarText)
                    .font(.system(size: 12.5 * k, design: .serif))
                    .foregroundStyle(Ink.paper.opacity(0.78))
                    .padding(.top, 3 * k)

                // 三个标签在窄中宫里会超宽，改成流式换行
                FlowRow(spacing: 6 * k) {
                    tag(chart.yinYangText, k: k)
                    tag("五行" + chart.bureauName, k: k)
                    tag(chart.isForward ? "大限顺行" : "大限逆行", k: k)
                }
                .padding(.top, 16 * k)

                HStack(spacing: 9 * k) {
                    kv("命主", chart.mingZhu, k: k)
                    kv("身主", chart.shenZhu, k: k)
                }
                .padding(.top, 16 * k)

                HStack(spacing: 20 * k) {
                    kv("命宫", chart.palaces[chart.mingGong].ganZhi, k: k)
                    kv("身宫", chart.palaces[chart.shenGong].ganZhi, k: k)
                }
                .padding(.top, 9 * k)

                Spacer()

                Text("排盘依据：中州派安星诀")
                    .font(.system(size: 9 * k, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.45))
                Spacer().frame(height: 10 * k)
            }
            .padding(.horizontal, 16 * k)
        }
        .overlay(Rectangle().stroke(Ink.hairline, lineWidth: 1))
        .opacity(reveal)
    }

    private func tag(_ s: String, k: CGFloat) -> some View {
        Text(s)
            .font(.system(size: 10 * k, design: .serif))
            .foregroundStyle(Ink.goldDim.opacity(0.85))
            .padding(.horizontal, 8 * k)
            .padding(.vertical, 3.5 * k)
            .overlay(Rectangle().stroke(Ink.goldDim.opacity(0.28), lineWidth: 0.8))
    }

    private func kv(_ k: String, _ v: String, k scale: CGFloat) -> some View {
        HStack(spacing: 5 * scale) {
            Text(k)
                .font(.system(size: 10 * scale, design: .serif))
                .foregroundStyle(Ink.dim.opacity(0.8))
            Text(v)
                .font(.system(size: 12.5 * scale, design: .serif))
                .foregroundStyle(Ink.paper.opacity(0.92))
        }
    }
}

// MARK: - 太极

struct Taichi: View {
    var size: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let r = min(s.width, s.height) / 2
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let full = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)

            let light = Color(red: 0.93, green: 0.91, blue: 0.88)
            let dark = Ink.bgDeep

            // 阴阳鱼由两个半径 r/2 的半圆拼成，不需要裁剪：
            // 上半的浅色半圆与下半的深色半圆互为咬合
            ctx.fill(Path(ellipseIn: full), with: .color(light))
            let upper = CGRect(x: c.x - r / 2, y: c.y - r, width: r, height: r)
            let lower = CGRect(x: c.x - r / 2, y: c.y, width: r, height: r)
            ctx.fill(Path(ellipseIn: upper), with: .color(light))
            ctx.fill(Path(ellipseIn: lower), with: .color(dark))

            // 鱼眼
            let eyeR = r / 6
            let e1 = CGRect(x: c.x - eyeR, y: c.y - r / 2 - eyeR, width: eyeR * 2, height: eyeR * 2)
            let e2 = CGRect(x: c.x - eyeR, y: c.y + r / 2 - eyeR, width: eyeR * 2, height: eyeR * 2)
            ctx.fill(Path(ellipseIn: e1), with: .color(dark))
            ctx.fill(Path(ellipseIn: e2), with: .color(light))

            // 金环
            ctx.stroke(Path(ellipseIn: full.insetBy(dx: 0.5, dy: 0.5)),
                       with: .color(Ink.goldDim.opacity(0.6)), lineWidth: 1.2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 左侧输入

struct SidePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("紫微斗数")
                    .font(.system(size: 20, weight: .light, design: .serif))
                    .foregroundStyle(Ink.gold)
                    .tracking(3)
                Text("命 盘 排 布")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.75))
                    .tracking(2)
                Rectangle()
                    .fill(Ink.goldDim.opacity(0.3))
                    .frame(width: 34, height: 1)
                    .padding(.top, 10)
            }
            .padding(.top, 34)
            .padding(.bottom, 30)

            field("性别") {
                GenderPicker(model: model)
            }

            field("历法") {
                CalendarPicker(model: model)
            }

            field("生日") {
                DateFields(model: model)
            }

            field("时辰") {
                HourPicker(model: model)
            }

            Button {
                model.useNow()
            } label: {
                Text("用 此 刻")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Ink.goldDim.opacity(0.85))
                    .tracking(2)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .overlay(Rectangle().stroke(Ink.goldDim.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            // 图例：星曜按性质分色
            VStack(alignment: .leading, spacing: 7) {
                Text("星曜")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.7))
                    .tracking(2)
                legend("十四主星", Ink.cinnabar)
                legend("六吉星", Ink.jade)
                legend("六煞星", Ink.obsidian)
                legend("杂曜", Ink.mauve)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 5) {
                Text("取法")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.7))
                    .tracking(2)
                Text("晚子时（23:00 后）按次日排；\n闰月按本月算；庚干四化取\n太阳、武曲、太阴、天同。")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.55))
                    .lineSpacing(3)
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(Ink.dim.opacity(0.7))
                .tracking(2)
            content()
        }
        .padding(.bottom, 20)
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(Ink.dim.opacity(0.75))
        }
    }
}

// MARK: - 手机模式

/// 竖屏排版：输入收到顶部，命盘占满宽度，图例横排在底部。
/// 窗口拉宽到 880pt 以上会自动换回左边的宽屏侧栏。
struct PhoneLayout: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("紫微斗数")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(Ink.gold)
                    .tracking(3)
                Text("命盘排布")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.7))
                    .tracking(2)
                Spacer()
                Button { model.useNow() } label: {
                    Text("用此刻")
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(Ink.goldDim.opacity(0.85))
                        .tracking(1)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .overlay(Rectangle().stroke(Ink.goldDim.opacity(0.3), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            FlowRow(spacing: 10) {
                GenderPicker(model: model)
                CalendarPicker(model: model)
                HourPicker(model: model)
                DateFields(model: model)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 14)

            ChartBoard(model: model)
                .padding(.horizontal, 6)
                .aspectRatio(1, contentMode: .fit)

            Spacer(minLength: 14)

            HStack(spacing: 14) {
                legendDot("主星", Ink.cinnabar)
                legendDot("六吉", Ink.jade)
                legendDot("六煞", Ink.obsidian)
                legendDot("杂曜", Ink.mauve)
                Spacer()
                Text("中州派安星诀")
                    .font(.system(size: 9, design: .serif))
                    .foregroundStyle(Ink.dim.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
    }

    private func legendDot(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 9.5, design: .serif))
                .foregroundStyle(Ink.dim.opacity(0.75))
        }
    }
}

// MARK: - 输入控件（宽屏侧栏与手机模式共用）

struct GenderPicker: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Chip("男", on: model.gender == .male) { model.gender = .male }
            Chip("女", on: model.gender == .female) { model.gender = .female }
        }
    }
}

struct CalendarPicker: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Chip("公历", on: !model.lunarInput) { model.lunarInput = false }
            Chip("农历", on: model.lunarInput) { model.lunarInput = true }
        }
    }
}

struct DateFields: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 5) {
            NumBox($model.year, 56); UnitLabel("年")
            NumBox($model.month, 38); UnitLabel("月")
            NumBox($model.day, 38); UnitLabel("日")
        }
    }
}

struct HourPicker: View {
    @ObservedObject var model: AppModel
    var width: CGFloat = 150

    var body: some View {
        Group {
            if RenderConfig.isRendering {
                // ImageRenderer 画不出 AppKit 的 Menu，换成纯文本
                HStack {
                    Text(AppModel.slotNames[min(max(model.hourSlot, 0), 12)])
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Ink.paper)
                    Spacer()
                }
                .padding(.horizontal, 9)
                .frame(width: width, height: 28)
                .background(Ink.cell)
                .overlay(Rectangle().stroke(Ink.hairline, lineWidth: 1))
            } else {
                Menu {
                    ForEach(0..<13, id: \.self) { i in
                        Button(AppModel.slotNames[i]) { model.hourSlot = i }
                    }
                } label: {
                    HStack {
                        Text(AppModel.slotNames[min(max(model.hourSlot, 0), 12)])
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Ink.paper)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Ink.dim)
                    }
                    .padding(.horizontal, 9)
                    .frame(width: width, height: 28)
                    .background(Ink.cell)
                    .overlay(Rectangle().stroke(Ink.hairline, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    init(_ title: String, on: Bool, action: @escaping () -> Void) {
        self.title = title
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(on ? Ink.bgDeep : Ink.paper.opacity(0.7))
                .frame(width: 48, height: 28)
                .background(on ? Ink.goldDim : Ink.cell)
                .overlay(Rectangle().stroke(Ink.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct UnitLabel: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View {
        Text(s)
            .font(.system(size: 10.5, design: .serif))
            .foregroundStyle(Ink.dim.opacity(0.8))
    }
}

struct NumBox: View {
    @Binding var value: Int
    let w: CGFloat

    init(_ value: Binding<Int>, _ w: CGFloat) {
        _value = value
        self.w = w
    }

    var body: some View {
        Group {
            if RenderConfig.isRendering {
                Text("\(String(value))")
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(Ink.paper)
            } else {
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(Ink.paper)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: w, height: 28)
        .background(Ink.cell)
        .overlay(Rectangle().stroke(Ink.hairline, lineWidth: 1))
    }
}

// MARK: - 入口

@main
struct ZiweiApp: App {
    init() {
        let a = CommandLine.arguments
        // 位置参数：Ziwei 1990 1 1 10 M   或   --chart 1990 1 1 10 M
        var base = 1
        if let i = a.firstIndex(of: "--chart") { base = i + 1 }
        if a.count >= base + 4, Int(a[base]) != nil {
            var input = BirthInput()
            input.year = Int(a[base]) ?? 1990
            input.month = Int(a[base + 1]) ?? 1
            input.day = Int(a[base + 2]) ?? 1
            input.hour = Int(a[base + 3]) ?? 12
            if a.count > base + 4 {
                let g = a[base + 4].uppercased()
                input.gender = (g == "F" || g == "女") ? .female : .male
            }
            input.lunarInput = a.contains("--lunar")
            print(Paipan.dump(Paipan.build(input)))
            exit(0)
        }

        // 离屏渲染：Ziwei --render out.png [年 月 日 时 性别]  （加 --wide 出宽屏排版）
        if let i = a.firstIndex(of: "--render"), a.count > i + 1 {
            var seed = BirthInput()
            // 先把 --wide 之类的旗标摘掉，否则位置参数会错位
            let rest = a.filter { $0 != "--wide" }
            let b = rest.firstIndex(of: "--render") ?? 1
            if rest.count >= b + 6 {
                seed.year = Int(rest[b + 2]) ?? 1990
                seed.month = Int(rest[b + 3]) ?? 1
                seed.day = Int(rest[b + 4]) ?? 1
                seed.hour = Int(rest[b + 5]) ?? 12
                if rest.count > b + 6 {
                    let g = rest[b + 6].uppercased()
                    seed.gender = (g == "F" || g == "女") ? .female : .male
                }
            }
            RenderConfig.seed = seed
            RenderConfig.isRendering = true
                let wide = a.contains("--wide")
            MainActor.assumeIsolated {
                let view = ContentView().frame(width: wide ? 1080 : 430,
                                               height: wide ? 780 : 880)
                let r = ImageRenderer(content: view)
                r.scale = 2
                guard let img = r.nsImage,
                      let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    print("渲染失败")
                    return
                }
                try? png.write(to: URL(fileURLWithPath: a[i + 1]))
                print("已写出 \(a[i + 1])")
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("紫微斗数") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        // 默认按手机比例开窗；拉宽到 880pt 以上会自己换回宽屏排版
        .defaultSize(width: 430, height: 880)
        .windowResizability(.contentMinSize)
    }
}
