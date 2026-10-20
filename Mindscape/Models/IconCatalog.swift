import AppKit

struct IconChoice: Identifiable, Hashable {
    let symbol: String
    let name: String
    let keywords: [String]

    var id: String { symbol }
}

enum IconCatalog {
    static let all: [IconChoice] = raw.filter {
        NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil
    }

    static func search(_ query: String) -> [IconChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return all }
        return all.filter { choice in
            choice.name.lowercased().contains(trimmed)
                || choice.symbol.lowercased().contains(trimmed)
                || choice.keywords.contains { $0.lowercased().contains(trimmed) }
        }
    }

    private static let raw: [IconChoice] = [
        IconChoice(symbol: "lightbulb.fill", name: "想法", keywords: ["灵感", "点子", "idea"]),
        IconChoice(symbol: "star.fill", name: "重点", keywords: ["收藏", "重要", "star"]),
        IconChoice(symbol: "flag.fill", name: "目标", keywords: ["旗帜", "里程碑", "goal"]),
        IconChoice(symbol: "target", name: "靶心", keywords: ["目标", "聚焦", "target"]),
        IconChoice(symbol: "scope", name: "范围", keywords: ["审视", "检查", "scope"]),
        IconChoice(symbol: "checkmark.circle.fill", name: "完成", keywords: ["任务", "通过", "done"]),
        IconChoice(symbol: "exclamationmark.triangle.fill", name: "风险", keywords: ["警告", "注意", "risk"]),
        IconChoice(symbol: "pin.fill", name: "固定", keywords: ["置顶", "钉住", "pin"]),
        IconChoice(symbol: "heart.fill", name: "喜欢", keywords: ["爱", "收藏", "heart"]),
        IconChoice(symbol: "flame.fill", name: "紧急", keywords: ["火", "热点", "hot"]),
        IconChoice(symbol: "bolt.fill", name: "能量", keywords: ["快速", "灵感", "bolt"]),
        IconChoice(symbol: "bookmark.fill", name: "书签", keywords: ["标记", "保存", "bookmark"]),
        IconChoice(symbol: "bell.fill", name: "提醒", keywords: ["通知", "闹钟", "bell"]),
        IconChoice(symbol: "questionmark.circle.fill", name: "问题", keywords: ["疑问", "帮助", "question"]),
        IconChoice(symbol: "info.circle.fill", name: "信息", keywords: ["说明", "提示", "info"]),
        IconChoice(symbol: "xmark.circle.fill", name: "取消", keywords: ["错误", "关闭", "cancel"]),
        IconChoice(symbol: "plus.circle.fill", name: "添加", keywords: ["新增", "增加", "add"]),
        IconChoice(symbol: "minus.circle.fill", name: "减少", keywords: ["移除", "删除", "minus"]),
        IconChoice(symbol: "arrow.up.circle.fill", name: "上升", keywords: ["提升", "增长", "up"]),
        IconChoice(symbol: "arrow.down.circle.fill", name: "下降", keywords: ["降低", "减少", "down"]),
        IconChoice(symbol: "arrow.right.circle.fill", name: "下一步", keywords: ["前进", "下一步", "next"]),
        IconChoice(symbol: "arrow.left.circle.fill", name: "上一步", keywords: ["返回", "后退", "previous"]),
        IconChoice(symbol: "checkmark.seal.fill", name: "认证", keywords: ["通过", "合格", "seal"]),
        IconChoice(symbol: "shield.fill", name: "安全", keywords: ["防护", "保护", "shield"]),
        IconChoice(symbol: "person.fill", name: "人物", keywords: ["用户", "成员", "person"]),
        IconChoice(symbol: "person.2.fill", name: "团队", keywords: ["协作", "沟通", "team"]),
        IconChoice(symbol: "person.3.fill", name: "群组", keywords: ["多人", "社区", "group"]),
        IconChoice(symbol: "figure.walk", name: "行动", keywords: ["走路", "执行", "action"]),
        IconChoice(symbol: "figure.run", name: "跑步", keywords: ["运动", "速度", "run"]),
        IconChoice(symbol: "face.smiling.fill", name: "心情", keywords: ["开心", "态度", "smile"]),
        IconChoice(symbol: "hand.thumbsup.fill", name: "赞同", keywords: ["点赞", "认可", "like"]),
        IconChoice(symbol: "hand.raised.fill", name: "停止", keywords: ["注意", "举手", "stop"]),
        IconChoice(symbol: "clock.fill", name: "时间", keywords: ["时钟", "耗时", "time"]),
        IconChoice(symbol: "calendar", name: "日历", keywords: ["日期", "计划", "calendar"]),
        IconChoice(symbol: "alarm.fill", name: "闹钟", keywords: ["提醒", "截止", "alarm"]),
        IconChoice(symbol: "hourglass", name: "等待", keywords: ["期限", "进度", "wait"]),
        IconChoice(symbol: "timer", name: "计时", keywords: ["倒计时", "时长", "timer"]),
        IconChoice(symbol: "repeat", name: "重复", keywords: ["循环", "周期", "repeat"]),
        IconChoice(symbol: "book.fill", name: "书", keywords: ["资料", "阅读", "book"]),
        IconChoice(symbol: "doc.text.fill", name: "文档", keywords: ["文件", "报告", "document"]),
        IconChoice(symbol: "folder.fill", name: "目录", keywords: ["文件夹", "归档", "folder"]),
        IconChoice(symbol: "paperclip", name: "附件", keywords: ["链接", "附加", "attach"]),
        IconChoice(symbol: "link", name: "链接", keywords: ["网址", "引用", "link"]),
        IconChoice(symbol: "list.bullet", name: "清单", keywords: ["列表", "要点", "list"]),
        IconChoice(symbol: "checklist", name: "待办", keywords: ["检查", "任务", "checklist"]),
        IconChoice(symbol: "note.text", name: "笔记", keywords: ["记录", "备忘", "note"]),
        IconChoice(symbol: "quote.bubble.fill", name: "引用", keywords: ["金句", "摘录", "quote"]),
        IconChoice(symbol: "text.book.closed.fill", name: "手册", keywords: ["笔记", "资料", "book"]),
        IconChoice(symbol: "gearshape.fill", name: "设置", keywords: ["配置", "参数", "settings"]),
        IconChoice(symbol: "wrench.and.screwdriver.fill", name: "工具", keywords: ["维修", "开发", "tools"]),
        IconChoice(symbol: "hammer.fill", name: "构建", keywords: ["开发", "搭建", "build"]),
        IconChoice(symbol: "terminal.fill", name: "终端", keywords: ["命令", "代码", "terminal"]),
        IconChoice(symbol: "cpu.fill", name: "芯片", keywords: ["技术", "性能", "cpu"]),
        IconChoice(symbol: "externaldrive.fill", name: "存储", keywords: ["硬盘", "数据", "storage"]),
        IconChoice(symbol: "network", name: "网络", keywords: ["连接", "拓扑", "network"]),
        IconChoice(symbol: "wifi", name: "无线", keywords: ["网络", "信号", "wifi"]),
        IconChoice(symbol: "cloud.fill", name: "云", keywords: ["云端", "在线", "cloud"]),
        IconChoice(symbol: "lock.fill", name: "安全", keywords: ["加密", "权限", "lock"]),
        IconChoice(symbol: "key.fill", name: "关键", keywords: ["密码", "钥匙", "key"]),
        IconChoice(symbol: "qrcode", name: "二维码", keywords: ["扫码", "识别", "qr"]),
        IconChoice(symbol: "dollarsign.circle.fill", name: "预算", keywords: ["钱", "成本", "money"]),
        IconChoice(symbol: "chart.bar.fill", name: "数据", keywords: ["图表", "统计", "chart"]),
        IconChoice(symbol: "chart.line.uptrend.xyaxis", name: "增长", keywords: ["趋势", "上升", "growth"]),
        IconChoice(symbol: "chart.pie.fill", name: "占比", keywords: ["饼图", "比例", "pie"]),
        IconChoice(symbol: "briefcase.fill", name: "工作", keywords: ["项目", "业务", "work"]),
        IconChoice(symbol: "building.2.fill", name: "公司", keywords: ["组织", "企业", "company"]),
        IconChoice(symbol: "envelope.fill", name: "邮件", keywords: ["消息", "联系", "mail"]),
        IconChoice(symbol: "phone.fill", name: "电话", keywords: ["联系", "沟通", "phone"]),
        IconChoice(symbol: "creditcard.fill", name: "支付", keywords: ["卡", "费用", "payment"]),
        IconChoice(symbol: "cart.fill", name: "购物", keywords: ["购买", "清单", "cart"]),
        IconChoice(symbol: "tag.fill", name: "标签", keywords: ["分类", "标记", "tag"]),
        IconChoice(symbol: "megaphone.fill", name: "宣传", keywords: ["公告", "通知", "announce"]),
        IconChoice(symbol: "sun.max.fill", name: "太阳", keywords: ["晴天", "天气", "sun"]),
        IconChoice(symbol: "moon.fill", name: "月亮", keywords: ["夜间", "休息", "moon"]),
        IconChoice(symbol: "cloud.rain.fill", name: "下雨", keywords: ["天气", "雨", "rain"]),
        IconChoice(symbol: "leaf.fill", name: "自然", keywords: ["环保", "成长", "leaf"]),
        IconChoice(symbol: "tree.fill", name: "树", keywords: ["成长", "自然", "tree"]),
        IconChoice(symbol: "drop.fill", name: "水滴", keywords: ["水", "液体", "water"]),
        IconChoice(symbol: "snowflake", name: "雪", keywords: ["冷", "冬天", "snow"]),
        IconChoice(symbol: "wind", name: "风", keywords: ["天气", "空气", "wind"]),
        IconChoice(symbol: "mountain.2.fill", name: "挑战", keywords: ["目标", "高峰", "mountain"]),
        IconChoice(symbol: "car.fill", name: "汽车", keywords: ["出行", "交通", "car"]),
        IconChoice(symbol: "airplane", name: "飞机", keywords: ["旅行", "出差", "plane"]),
        IconChoice(symbol: "tram.fill", name: "地铁", keywords: ["交通", "通勤", "metro"]),
        IconChoice(symbol: "bicycle", name: "自行车", keywords: ["骑行", "运动", "bike"]),
        IconChoice(symbol: "map.fill", name: "地图", keywords: ["路线", "规划", "map"]),
        IconChoice(symbol: "location.fill", name: "位置", keywords: ["地点", "定位", "location"]),
        IconChoice(symbol: "house.fill", name: "家", keywords: ["首页", "住所", "home"]),
        IconChoice(symbol: "building.columns.fill", name: "机构", keywords: ["银行", "学校", "bank"]),
        IconChoice(symbol: "globe", name: "全球", keywords: ["世界", "国际化", "globe"]),
        IconChoice(symbol: "sparkles", name: "亮点", keywords: ["闪耀", "新功能", "sparkle"]),
        IconChoice(symbol: "crown.fill", name: "冠军", keywords: ["重要", "王者", "crown"]),
        IconChoice(symbol: "trophy.fill", name: "成就", keywords: ["胜利", "奖项", "trophy"]),
        IconChoice(symbol: "gift.fill", name: "礼物", keywords: ["惊喜", "奖励", "gift"]),
        IconChoice(symbol: "camera.fill", name: "拍照", keywords: ["图片", "相机", "camera"]),
        IconChoice(symbol: "photo.fill", name: "图片", keywords: ["照片", "视觉", "photo"]),
        IconChoice(symbol: "play.fill", name: "开始", keywords: ["播放", "启动", "play"]),
        IconChoice(symbol: "pause.fill", name: "暂停", keywords: ["停下", "休息", "pause"]),
        IconChoice(symbol: "stop.fill", name: "停止", keywords: ["结束", "stop"]),
        IconChoice(symbol: "music.note", name: "音乐", keywords: ["音频", "声音", "music"]),
        IconChoice(symbol: "headphones", name: "耳机", keywords: ["音频", "聆听", "audio"]),
        IconChoice(symbol: "mic.fill", name: "录音", keywords: ["麦克风", "语音", "mic"])
    ]
}
