import Foundation

// MARK: - 基础常量

/// 天干
let GAN = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
/// 地支
let ZHI = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
/// 十二宫名，从命宫起逆时针
let PALACE_NAMES = ["命宫", "兄弟", "夫妻", "子女", "财帛", "疾厄",
                    "迁移", "交友", "官禄", "田宅", "福德", "父母"]
/// 五行局
let BUREAU_NAMES = ["", "", "水二局", "木三局", "金四局", "土五局", "火六局"]

/// 纳音五行，索引 = 干支序号 / 2
let NAYIN = ["金", "火", "木", "土", "金", "火", "水", "土", "金", "木",
             "水", "土", "火", "木", "水", "金", "火", "木", "土", "金",
             "火", "水", "土", "金", "木", "水", "土", "火", "木", "水"]

/// 五行 → 局数
let WUXING_BUREAU: [String: Int] = ["水": 2, "木": 3, "金": 4, "土": 5, "火": 6]

/// 时辰地支索引
func hourBranch(_ hour: Int) -> Int {
    // 23:00-00:59 子，01:00-02:59 丑 ……
    ((hour + 1) / 2) % 12
}

func hourBranchName(_ hour: Int) -> String {
    ZHI[hourBranch(hour)] + "时"
}

/// 干支序号（甲子=0 … 癸亥=59）
func sexagenary(_ gan: Int, _ zhi: Int) -> Int {
    ((6 * gan - 5 * zhi) % 60 + 60) % 60
}

/// 公历年 → 年干支（以立春为界的说法这里不采用，紫微斗数用农历年）
func yearGanZhi(_ lunarYear: Int) -> (gan: Int, zhi: Int) {
    // 公元 4 年为甲子年
    let g = ((lunarYear - 4) % 10 + 10) % 10
    let z = ((lunarYear - 4) % 12 + 12) % 12
    return (g, z)
}

// MARK: - 输入

enum Gender: String {
    case male = "男"
    case female = "女"
}

struct BirthInput {
    var year = 1990
    var month = 1
    var day = 1
    var hour = 12
    var minute = 0
    var gender: Gender = .male
    /// 输入的是农历还是公历
    var lunarInput = false
}

// MARK: - 星曜

enum StarKind {
    case major      // 十四主星
    case lucky      // 六吉
    case evil       // 六煞
    case misc       // 杂曜
}

struct Star {
    var name: String
    var kind: StarKind
    /// 四化：禄 / 权 / 科 / 忌
    var hua: String? = nil
}

struct Palace {
    var branch: Int
    var stem: Int
    var name: String
    var stars: [Star] = []
    var decadeFrom: Int = 0
    var decadeTo: Int = 0
    var isMing = false
    var isShen = false

    var ganZhi: String { GAN[stem] + ZHI[branch] }
    var majorStars: [Star] { stars.filter { $0.kind == .major } }
    var minorStars: [Star] { stars.filter { $0.kind != .major } }
}

// MARK: - 命盘

struct Chart {
    var input: BirthInput
    var solarDate: Date = Date()
    var lunarYear = 1990
    var lunarMonth = 1
    var lunarDay = 1
    var isLeapMonth = false
    var yearGan = 0
    var yearZhi = 0
    var hourBranch = 0
    var mingGong = 0
    var shenGong = 0
    var bureau = 2
    var palaces: [Palace] = []
    var mingZhu = ""
    var shenZhu = ""

    var bureauName: String { BUREAU_NAMES[bureau] }
    var yearGanZhiText: String { GAN[yearGan] + ZHI[yearZhi] }
    var lunarText: String {
        "\(GAN[yearGan])\(ZHI[yearZhi])年 \(isLeapMonth ? "闰" : "")\(lunarMonth)月\(lunarDay)日"
    }
    var solarText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: solarDate)
    }
    /// 阳男 / 阴男 / 阳女 / 阴女
    var yinYangText: String {
        let yang = yearGan % 2 == 0
        return (yang ? "阳" : "阴") + input.gender.rawValue
    }
    var isForward: Bool {
        // 阳男阴女顺行
        let yang = yearGan % 2 == 0
        return (yang && input.gender == .male) || (!yang && input.gender == .female)
    }
}

// MARK: - 排盘

enum Paipan {

    static let shanghai: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    static var chineseCal: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = shanghai
        return c
    }()
    static var solarCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = shanghai
        return c
    }()

    /// 公历日期 → 农历（年、月、日、是否闰月）
    static func toLunar(_ date: Date) -> (year: Int, month: Int, day: Int, leap: Bool) {
        let comps = chineseCal.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        // chinese calendar 的 year 是 60 甲子内的序号，不能直接用；
        // 用公历年做基准，农历年比公历年最多差 1，靠月份判断修正
        let gy = solarCal.component(.year, from: date)
        let gm = solarCal.component(.month, from: date)
        let lm = comps.month ?? 1
        // 公历 1 月且农历月 >= 11，说明还在上一年腊月
        var ly = gy
        if gm <= 2 && lm >= 11 { ly = gy - 1 }
        return (ly, lm, comps.day ?? 1, comps.isLeapMonth ?? false)
    }

    /// 农历 → 公历：在附近逐日搜索，比直接构造 DateComponents 可靠
    static func toSolar(lunarYear: Int, month: Int, day: Int, leap: Bool) -> Date? {
        var comps = DateComponents()
        comps.year = lunarYear - 1
        comps.month = 11
        comps.day = 1
        guard let start = solarCal.date(from: comps) else { return nil }
        var d = start
        for _ in 0..<800 {
            let l = toLunar(d)
            if l.year == lunarYear && l.month == month && l.day == day && l.leap == leap {
                return d
            }
            guard let next = solarCal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return nil
    }

    static func build(_ input: BirthInput) -> Chart {
        var chart = Chart(input: input)

        // 1. 定公历时刻
        var date: Date
        if input.lunarInput {
            var comps = DateComponents()
            comps.year = input.year
            comps.month = input.month
            comps.day = input.day
            comps.hour = input.hour
            comps.minute = input.minute
            date = toSolar(lunarYear: input.year, month: input.month,
                           day: input.day, leap: false)
                ?? solarCal.date(from: comps) ?? Date()
            // 补上时分
            date = solarCal.date(bySettingHour: input.hour, minute: input.minute,
                                 second: 0, of: date) ?? date
        } else {
            var comps = DateComponents()
            comps.year = input.year
            comps.month = input.month
            comps.day = input.day
            comps.hour = input.hour
            comps.minute = input.minute
            date = solarCal.date(from: comps) ?? Date()
        }

        // 2. 晚子时（23:00 之后）算次日
        let hb = hourBranch(input.hour)
        if input.hour >= 23 {
            date = solarCal.date(byAdding: .day, value: 1, to: date) ?? date
        }

        chart.solarDate = date
        let lunar = toLunar(date)
        chart.lunarYear = lunar.year
        chart.lunarMonth = lunar.month
        chart.lunarDay = lunar.day
        chart.isLeapMonth = lunar.leap
        chart.hourBranch = hb

        // 3. 年干支
        let ygz = yearGanZhi(chart.lunarYear)
        chart.yearGan = ygz.gan
        chart.yearZhi = ygz.zhi

        // 4. 命宫、身宫
        //    寅宫起正月顺数至生月，再起子时逆数至生时
        let m = chart.lunarMonth
        chart.mingGong = ((2 + (m - 1) - hb) % 12 + 12) % 12
        chart.shenGong = ((2 + (m - 1) + hb) % 12 + 12) % 12

        // 5. 五行局
        chart.bureau = bureau(of: chart.mingGong, yearGan: chart.yearGan)

        // 6. 安星
        chart.palaces = makePalaces(chart)
        chart.mingZhu = mingZhu(chart.mingGong)
        chart.shenZhu = shenZhu(chart.yearZhi)
        return chart
    }

    /// 寅宫天干：甲己之年丙作首
    static func yinStem(_ yearGan: Int) -> Int {
        // 甲(0)/己(5) → 丙(2)；乙(1)/庚(6) → 戊(4)；丙(2)/辛(7) → 庚(6)
        // 丁(3)/壬(8) → 壬(8)；戊(4)/癸(9) → 甲(0)
        let table = [2, 4, 6, 8, 0, 2, 4, 6, 8, 0]
        return table[yearGan]
    }

    static func stemOf(_ branch: Int, yearGan: Int) -> Int {
        // 从寅宫起算，跨过 12 宫再取天干。少这一步 mod 12，
        // 子、丑两宫的天干会算反（寅→子 是 10 格，不是 -2 格）
        let offset = ((branch - 2) % 12 + 12) % 12
        return ((yinStem(yearGan) + offset) % 10 + 10) % 10
    }

    /// 命宫干支 → 纳音 → 五行局
    static func bureau(of branch: Int, yearGan: Int) -> Int {
        let g = stemOf(branch, yearGan: yearGan)
        let seq = sexagenary(g, branch)
        let element = NAYIN[seq / 2]
        return WUXING_BUREAU[element] ?? 2
    }

    /// 紫微星位置：借数法
    /// 商 = ceil(日/局)，借 = 商×局 − 日
    /// 从寅宫起顺数商位，借数为偶数顺行借位、奇数逆行借位
    static func ziweiPos(day: Int, bureau: Int) -> Int {
        let q = (day + bureau - 1) / bureau
        let borrow = q * bureau - day
        var pos = 2 + q - 1
        if borrow == 0 {
            // 原地
        } else if borrow % 2 == 0 {
            pos += borrow
        } else {
            pos -= borrow
        }
        return ((pos % 12) + 12) % 12
    }

    static let MAJOR_NAMES: Set<String> = [
        "紫微", "天机", "太阳", "武曲", "天同", "廉贞",
        "天府", "太阴", "贪狼", "巨门", "天相", "天梁", "七杀", "破军",
    ]

    static func makePalaces(_ chart: Chart) -> [Palace] {
        var palaces = (0..<12).map { b in
            Palace(branch: b, stem: stemOf(b, yearGan: chart.yearGan), name: "")
        }

        // 宫名：命宫起逆时针
        for i in 0..<12 {
            let b = ((chart.mingGong - i) % 12 + 12) % 12
            palaces[b].name = PALACE_NAMES[i]
        }
        palaces[chart.mingGong].isMing = true
        palaces[chart.shenGong].isShen = true

        // 四化表：年干 → [(星, 化)]
        let sihua: [[(String, String)]] = [
            [("廉贞", "禄"), ("破军", "权"), ("武曲", "科"), ("太阳", "忌")],   // 甲
            [("天机", "禄"), ("天梁", "权"), ("紫微", "科"), ("太阴", "忌")],   // 乙
            [("天同", "禄"), ("天机", "权"), ("文昌", "科"), ("廉贞", "忌")],   // 丙
            [("太阴", "禄"), ("天同", "权"), ("天机", "科"), ("巨门", "忌")],   // 丁
            [("贪狼", "禄"), ("太阴", "权"), ("右弼", "科"), ("天机", "忌")],   // 戊
            [("武曲", "禄"), ("贪狼", "权"), ("天梁", "科"), ("文曲", "忌")],   // 己
            [("太阳", "禄"), ("武曲", "权"), ("太阴", "科"), ("天同", "忌")],   // 庚
            [("巨门", "禄"), ("太阳", "权"), ("文曲", "科"), ("文昌", "忌")],   // 辛
            [("天梁", "禄"), ("紫微", "权"), ("左辅", "科"), ("武曲", "忌")],   // 壬
            [("破军", "禄"), ("巨门", "权"), ("太阴", "科"), ("贪狼", "忌")],   // 癸
        ]
        var huaMap: [String: String] = [:]
        for (name, hua) in sihua[chart.yearGan] { huaMap[name] = hua }

        func add(_ name: String, _ kind: StarKind, at b: Int) {
            let idx = ((b % 12) + 12) % 12
            palaces[idx].stars.append(Star(name: name, kind: kind, hua: huaMap[name]))
        }

        // 紫微星系（逆）
        let zw = ziweiPos(day: chart.lunarDay, bureau: chart.bureau)
        add("紫微", .major, at: zw)
        add("天机", .major, at: zw - 1)
        add("太阳", .major, at: zw - 3)
        add("武曲", .major, at: zw - 4)
        add("天同", .major, at: zw - 5)
        add("廉贞", .major, at: zw - 8)

        // 天府星系（顺）
        let tf = ((4 - zw) % 12 + 12) % 12
        add("天府", .major, at: tf)
        add("太阴", .major, at: tf + 1)
        add("贪狼", .major, at: tf + 2)
        add("巨门", .major, at: tf + 3)
        add("天相", .major, at: tf + 4)
        add("天梁", .major, at: tf + 5)
        add("七杀", .major, at: tf + 6)
        add("破军", .major, at: tf + 10)

        // 六吉
        add("左辅", .lucky, at: 4 + chart.lunarMonth - 1)          // 辰起正月顺行
        add("右弼", .lucky, at: 10 - (chart.lunarMonth - 1))       // 戌起正月逆行
        add("文昌", .lucky, at: 10 - chart.hourBranch)             // 戌起子时逆行
        add("文曲", .lucky, at: 4 + chart.hourBranch)              // 辰起子时顺行

        // 天魁天钺（年干）
        let kuiYue: [(Int, Int)] = [
            (1, 7),   // 甲 丑未
            (0, 8),   // 乙 子申
            (11, 9),  // 丙 亥酉
            (11, 9),  // 丁 亥酉
            (1, 7),   // 戊 丑未
            (0, 8),   // 己 子申
            (1, 7),   // 庚 丑未
            (6, 2),   // 辛 午寅
            (3, 5),   // 壬 卯巳
            (3, 5),   // 癸 卯巳
        ]
        add("天魁", .lucky, at: kuiYue[chart.yearGan].0)
        add("天钺", .lucky, at: kuiYue[chart.yearGan].1)

        // 禄存（年干）
        let lucun = [2, 3, 5, 6, 5, 6, 8, 9, 11, 0][chart.yearGan]
        add("禄存", .lucky, at: lucun)
        add("擎羊", .evil, at: lucun + 1)
        add("陀罗", .evil, at: lucun - 1)

        // 火星铃星（年支三合 + 时支）
        let group = chart.yearZhi % 4   // 0=子辰申? 需要按三合局分
        // 寅午戌 / 申子辰 / 巳酉丑 / 亥卯未
        let sanhe: Int
        switch chart.yearZhi {
        case 2, 6, 10: sanhe = 0      // 寅午戌
        case 8, 0, 4:  sanhe = 1      // 申子辰
        case 5, 9, 1:  sanhe = 2      // 巳酉丑
        default:       sanhe = 3      // 亥卯未
        }
        _ = group
        let huoStart = [1, 2, 3, 9][sanhe]     // 丑 / 寅 / 卯 / 酉
        let lingStart = [3, 10, 10, 10][sanhe] // 卯 / 戌 / 戌 / 戌
        add("火星", .evil, at: huoStart + chart.hourBranch)
        add("铃星", .evil, at: lingStart + chart.hourBranch)

        // 天马：申子辰马在寅、巳酉丑马在亥、寅午戌马在申、亥卯未马在巳
        let tianma = [2, 11, 8, 5, 2, 11, 8, 5, 2, 11, 8, 5][chart.yearZhi]
        add("天马", .misc, at: tianma)

        // 红鸾：卯宫起子年逆行至生年支；天喜为红鸾对宫
        let hongluan = ((3 - chart.yearZhi) % 12 + 12) % 12
        add("红鸾", .misc, at: hongluan)
        add("天喜", .misc, at: hongluan + 6)

        // 地空地劫（亥起子时）
        add("地劫", .evil, at: 11 + chart.hourBranch)
        add("地空", .evil, at: 11 - chart.hourBranch)

        // 大限：阳男阴女顺行（命→父母→福德，地支递增）
        //       阴男阳女逆行（命→兄弟→夫妻，地支递减）
        let start = chart.bureau
        for i in 0..<12 {
            let b: Int
            if chart.isForward {
                b = ((chart.mingGong + i) % 12 + 12) % 12
            } else {
                b = ((chart.mingGong - i) % 12 + 12) % 12
            }
            palaces[b].decadeFrom = start + i * 10
            palaces[b].decadeTo = start + i * 10 + 9
        }

        return palaces
    }

    /// 命主（按命宫地支）
    static func mingZhu(_ branch: Int) -> String {
        let table = ["贪狼", "巨门", "禄存", "文曲", "廉贞", "武曲",
                     "破军", "武曲", "廉贞", "文曲", "禄存", "巨门"]
        return table[branch]
    }

    /// 身主（按年支）
    static func shenZhu(_ branch: Int) -> String {
        let table = ["火星", "天相", "天梁", "天同", "文昌", "天机",
                     "火星", "天相", "天梁", "天同", "文昌", "天机"]
        return table[branch]
    }

    // MARK: 文本输出（调试用）

    static func dump(_ chart: Chart) -> String {
        var out = ""
        out += "公历 \(chart.solarText) \(hourBranchName(chart.input.hour))\n"
        out += "农历 \(chart.lunarText) \(hourBranchName(chart.input.hour))\n"
        out += "\(chart.yinYangText)　命宫 \(GAN[stemOf(chart.mingGong, yearGan: chart.yearGan)])\(ZHI[chart.mingGong])"
        out += "　身宫 \(GAN[stemOf(chart.shenGong, yearGan: chart.yearGan)])\(ZHI[chart.shenGong])\n"
        out += "五行\(chart.bureauName)　命主 \(chart.mingZhu)　身主 \(chart.shenZhu)\n"
        out += "大限 \(chart.isForward ? "顺行" : "逆行")\n\n"

        for i in 0..<12 {
            let b = ((chart.mingGong - i) % 12 + 12) % 12
            let p = chart.palaces[b]
            let majors = p.majorStars.map { $0.name + ($0.hua.map { "化\($0)" } ?? "") }
            let minors = p.minorStars.map { $0.name + ($0.hua.map { "化\($0)" } ?? "") }
            out += "\(p.ganZhi) \(p.name)\(p.isShen ? "(身)" : "") [\(p.decadeFrom)-\(p.decadeTo)]"
            out += "  " + majors.joined(separator: " ") + " | " + minors.joined(separator: " ") + "\n"
        }
        return out
    }
}
