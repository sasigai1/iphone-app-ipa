import Foundation

struct PageTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let desc: String
    let make: () -> Page
}

enum Templates {
    static func b(_ t: BlockType, _ s: String = "", checked: Bool = false) -> Block {
        var x = Block()
        x.type = t
        x.text = s
        x.checked = checked
        return x
    }

    static func page(_ title: String, _ icon: String, cover: Int?, _ blocks: [Block]) -> Page {
        var p = Page()
        p.title = title
        p.icon = icon
        p.cover = cover
        p.blocks = blocks
        return p
    }

    static func row(_ t: String, _ s: TaskStatus, _ pr: Priority, tag: String, days: Int?) -> DBRow {
        var r = DBRow()
        r.title = t
        r.status = s
        r.priority = pr
        r.tag = tag
        if let d = days { r.due = Calendar.current.date(byAdding: .day, value: d, to: Date()) }
        return r
    }

    static func journal() -> Page {
        var callout = b(.callout, "今天的心情：😊  天气：☀️")
        callout.emoji = "🌈"
        return page(Date().journalTitle, "🌤️", cover: 3, [
            callout,
            b(.h2, "今天发生了什么"),
            b(.text, ""),
            b(.h2, "感恩的三件事"),
            b(.numbered, ""), b(.numbered, ""), b(.numbered, ""),
            b(.h2, "明天想做"),
            b(.todo, "")
        ])
    }

    static var all: [PageTemplate] {
        [
            PageTemplate(name: "空白页面", icon: "📄", desc: "从零开始自由书写") {
                var p = Page()
                p.blocks = [Block()]
                return p
            },
            PageTemplate(name: "每日日记", icon: "🌤️", desc: "心情、感恩与今日回顾") {
                journal()
            },
            PageTemplate(name: "周计划", icon: "🗓️", desc: "本周目标与每日安排") {
                page("周计划", "🗓️", cover: 5, [
                    b(.callout, "本周最重要的一件事："),
                    b(.h2, "本周目标"),
                    b(.todo, ""), b(.todo, ""),
                    b(.h2, "每日安排"),
                    b(.toggle, "周一"), b(.toggle, "周二"), b(.toggle, "周三"), b(.toggle, "周四"), b(.toggle, "周五"), b(.toggle, "周末"),
                    b(.h2, "复盘"),
                    b(.text, "")
                ])
            },
            PageTemplate(name: "项目文档", icon: "🚀", desc: "背景、目标、里程碑与表格") {
                var t = b(.table)
                t.table = [["里程碑", "负责人", "日期"], ["", "", ""], ["", "", ""]]
                return page("项目文档", "🚀", cover: 1, [
                    b(.toc),
                    b(.h1, "背景"),
                    b(.text, ""),
                    b(.h1, "目标"),
                    b(.bullet, ""),
                    b(.h1, "里程碑"),
                    t,
                    b(.h1, "参考资料"),
                    b(.bookmark)
                ])
            },
            PageTemplate(name: "会议记录", icon: "🗣️", desc: "议程、讨论与行动项") {
                page("会议记录", "🗣️", cover: 1, [
                    b(.callout, "时间：  参会人："),
                    b(.h2, "议程"),
                    b(.bullet, ""),
                    b(.h2, "讨论要点"),
                    b(.text, ""),
                    b(.h2, "行动项"),
                    b(.todo, ""),
                    b(.divider),
                    b(.quote, "下次会议：")
                ])
            },
            PageTemplate(name: "读书笔记", icon: "📚", desc: "摘录、思考与评分") {
                page("读书笔记", "📚", cover: 7, [
                    b(.callout, "作者：  评分：⭐️⭐️⭐️⭐️⭐️"),
                    b(.h2, "一句话总结"),
                    b(.quote, ""),
                    b(.h2, "精彩摘录"),
                    b(.bullet, ""),
                    b(.h2, "我的思考"),
                    b(.text, "")
                ])
            },
            PageTemplate(name: "旅行计划", icon: "✈️", desc: "行程、清单与预算") {
                page("旅行计划", "✈️", cover: 2, [
                    b(.h2, "行程安排"),
                    b(.toggle, "第一天"), b(.toggle, "第二天"),
                    b(.h2, "行李清单"),
                    b(.todo, "证件"), b(.todo, "充电器"), b(.todo, "换洗衣物"),
                    b(.h2, "预算"),
                    b(.code, "交通：\n住宿：\n餐饮：")
                ])
            },
            PageTemplate(name: "任务看板", icon: "🗂️", desc: "用看板管理任务进度") {
                var p = Page()
                p.title = "任务看板"
                p.icon = "🗂️"
                p.kind = .database
                p.blocks = []
                p.rows = [
                    row("示例任务", .todo, .medium, tag: "工作", days: 3)
                ]
                return p
            }
        ]
    }

    static func seed() -> [Page] {
        var welcome = Page()
        welcome.title = "欢迎使用墨页"
        welcome.icon = "👋"
        welcome.cover = 1
        welcome.isFavorite = true
        var c1 = b(.callout, "墨页是一款块式笔记：每一行都是一个“块”，可以随时转换成标题、列表、待办、引用、代码等。")
        c1.emoji = "✨"
        var t1 = b(.toggle, "点我展开：快捷输入")
        t1.detail = "# 空格 → 一级标题\n## 空格 → 二级标题\n- 空格 → 列表\n1. 空格 → 编号列表\n[] 空格 → 待办\n> 空格 → 引用\n--- → 分割线\n/ → 打开块菜单"
        t1.expanded = false
        welcome.blocks = [
            c1,
            b(.h2, "开始上手"),
            b(.todo, "点击任意文字开始编辑", checked: true),
            b(.todo, "在空行输入 / 打开块菜单"),
            b(.todo, "长按一个块，转换类型、移动或删除"),
            b(.todo, "点右上角 ··· 更换封面和图标"),
            t1,
            b(.h2, "更多功能"),
            b(.bullet, "页面可以无限嵌套，在主页树里展开查看"),
            b(.bullet, "收藏常用页面，最近编辑一目了然"),
            b(.bullet, "数据库页面支持列表和看板两种视图"),
            b(.bullet, "全文搜索、废纸篓、Markdown 导出、面容锁"),
            b(.divider),
            b(.quote, "好记性不如烂笔头。")
        ]

        var board = Page()
        board.title = "我的任务"
        board.icon = "🗂️"
        board.kind = .database
        board.blocks = []
        board.isFavorite = true
        board.rows = [
            row("整理本周笔记", .doing, .high, tag: "学习", days: 1),
            row("写周报", .todo, .medium, tag: "工作", days: 2),
            row("预约体检", .todo, .low, tag: "生活", days: 6),
            row("安装墨页", .done, .medium, tag: "生活", days: nil)
        ]

        var ideas = Page()
        ideas.title = "灵感收集"
        ideas.icon = "💡"
        ideas.parentID = welcome.id
        ideas.blocks = [b(.bullet, "随手记下的点子放在这里"), b(.bullet, "")]

        welcome.blocks.insert({
            var x = b(.page)
            x.linkedPage = ideas.id
            return x
        }(), at: 12)

        return [welcome, board, ideas]
    }
}
