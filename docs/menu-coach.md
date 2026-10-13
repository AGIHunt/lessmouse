# 菜单教练（Menu Coach）实现说明

> 一个功能的实现笔记：怎么做的、为什么这么做、怎么验证的、还有什么不灵。
> 对应分支 `eval/menu-coach`。

## 它做了什么

用户**用鼠标**点开某个应用的菜单栏、选中一条带快捷键的命令（File → Save，⌘S），
LessMouse 会注意到这个习惯；攒够一天之后，给出一张卡片，把打印在命令旁边、却从来
没人指给用户看的那个快捷键教给用户。用户真的开始按 ⌘S 时，卡片翻成"已采纳"并庆祝——
和键盘那一半走的是同一条路。

四个硬约束决定了整个设计：

1. **不靠手写规则表。** 要覆盖用户日常用的所有应用，手写菜单表第二天就会过期。
2. **不为它弹一次权限框。** 不想用的人不该被打扰，也不该被索要额外权限。
3. **不为它变慢。** 普通点击必须零成本。
4. **默认不欠用户一次选择。** 没要过这个功能的人，不该一觉醒来发现 LessMouse 开始看自己
   每一次点鼠标——所以教练**默认关闭**，在设置里打开（见第 11 节）。

## 实现

### 1. 一条鼠标监听，挂在既有 tap 上

`KeyboardMonitor` 的事件掩码在菜单教练开启时多一个 `.leftMouseDown`：

```swift
var mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
if self.watchesMouse { mask |= 1 << CGEventType.leftMouseDown }
```

`watchesMouse` 由 `settings.isMenuCoachEnabled` 驱动，关闭教练的用户和以前完全一样——
只监听键盘。

### 2. 两次点击才是一次"命令"

一次菜单命令的手势永远是两次点击：先点开菜单，再选中命令。任何一次单独的点击都不说明
问题（点"Edit"不是一个命令），所以 `MenuClickTracker` 记住刚被点开的菜单，把**下一次**
点击对着它做命中测试。

菜单内容是在**第二次**点击时才读的。一个菜单栏有十几个菜单，每次点击全读一遍就是十几次
accessibility 往返。`MenuItemSnapshot.openMenu` 是个闭包而不是数组，就是为了这个：只读
用户真正打开的那一个。

### 3. 快捷键从哪来：读菜单，不建表

`AXMenuAccessibility` 是唯一接触辅助功能 API 的地方。它只读七个属性：
`kAXPositionAttribute`、`kAXSizeAttribute`、`kAXRoleAttribute`、`kAXEnabledAttribute`，
以及快捷键的三件套 `kAXMenuItemCmdVirtualKeyAttribute`、`kAXMenuItemCmdCharAttribute`、
`kAXMenuItemCmdModifiersAttribute`。

**`AXTitle` 不在这个列表里，而且加不进去——`MenuItemSnapshot` 没有字段能装标题。**
菜单栏里全是用户数据（打开的文件名、窗口名、账户名），而叫出一个快捷键一个标题都不需要。
这条边界因此是结构性的，不是承诺。

一个坑：`AXMenuItemCmdModifiers` 里 **⌘ 是隐含的**——0 表示"只有 ⌘"，要说"没有 ⌘"
必须显式给 `kAXMenuItemModifierNoCommand`。读反了，每个菜单都会教"⌘⌘S"。这条有一张
单测表守着。

### 4. 键码属性只回答功能键（真机才暴露的根因）

第一版只读 `AXMenuItemCmdVirtualKey`，真机上于是几乎什么都识别不到：Finder 174 项里
认出 12 项，Chrome 306 项里 5 项，iTerm2 255 项里 3 项。而识别出来的几乎全是特殊键
（⌫、⎋、⇥、方向键、F 键）——每一个字母、数字、标点快捷键都漏了，包括 README 自己的
⌘S 例子。漏掉的分布这么整齐，说明不是某个应用的怪癖。

拿真菜单逐项量，根因是：**`AXMenuItemCmdVirtualKey` 只为功能键和特殊键作答。**

| 命令 | CmdVirtualKey | CmdChar |
|---|---|---|
| ⌘S | `kAXErrorNoValue`（-25212） | `"S"` |
| ⌘2 | `kAXErrorNoValue` | `"2"` |
| ⇧⌘B | `kAXErrorNoValue` | `"B"` |
| ⌘↑ | 126 | U+F700 |
| ⌘F3 | 99 | U+F706 |
| ⌘⌫ | 51 | U+0008 |

AppKit 只在键等效值**不是字符**时才上报虚拟键码。可打印的那绝大多数因此只能从
`AXMenuItemCmdChar` 来——而字符不是键码。

（顺带排除了两个假嫌疑：`KeyWhitelist` 对字母/数字/标点是全的，不是它漏了；`-25212`
是 `kAXErrorNoValue` 而不是权限错误，跟授权无关。）

### 5. 字符怎么变成键码：问键盘布局，不查表

把字符当键码是错的，而且错的正是这个功能的地基。键盘那半边记的是键码（`KeyWhitelist`
就按键码索引），菜单这半边必须叫出**同一个**键码，采纳检测才对得上。Dvorak 布局下产出
"s" 的键是 QWERTY 标 ";" 的那一个，所以菜单印着 ⌘S 时它要的是键码 41，不是 1；键盘
半边按下去时写的是 `cmd+semicolon`。写死一张字符→token 表，非 QWERTY 用户的采纳检测
就永远不响。

`KeyboardLayoutKeys` 因此用当前输入源的真实布局反向查：
`TISCopyCurrentKeyboardLayoutInputSource()` → `kTISPropertyUnicodeKeyLayoutData`（'uchr'）
→ `UCKeyTranslate`。每布局建一次并缓存，128 个键码是零点几毫秒的事，布局只在用户切换
输入源时变。

四个细节是量出来的，不是想出来的：

1. **⇧ 是哪一个 bit 由布局自己说**，而且它不是 Carbon `shiftKey` 常量那个值
   （`Events.h` 里 `shiftKeyBit` 是 9，实测 UCKeyTranslate 认 2）。代码因此枚举所有
   单 bit 状态，不点名任何一个。
2. **同一个字符可能多个键都能产出，偏好必须显式排序，不能靠遍历顺序。** "0" 必须来自
   那个不按修饰键就印 "0" 的键，而不是来自某个印 "§"、在别的修饰状态下顺手产出 "0" 的键；
   而 "*" 必须来自主键盘的 ⇧8，而不是小键盘的 *——后者不在白名单里，教不出来。这两条
   要求方向相反（一个要"未修饰优先"，一个要"主键盘优先"），所以用 `Preference`
   （主键盘 → 未修饰 → 键码小）显式排序取最优，而不是分几趟按顺序扫。这个坑是
   `KeyboardLayoutKeysTests` 先炸出来的。
3. **私用区字符（U+F700–U+F8FF）必须被布局图拒绝。** 功能键和特殊键就是以私用字符的
   形式从菜单过来的（⌘↑ 是 U+F700，F3 是 U+F706），而它们由虚拟键码属性直接点名。
   让布局图认领一个，F 键就会走到字符这条路，落到恰好产出那个字符的键上——排查时 F3
   就是这样变成了右方向键（`"\u{F703}"` 其实是 `NSRightArrowFunctionKey`，不是 F3，
   F3 是 `"\u{F706}"`）。
4. **⇧ 本身要推断，不能只报键码。** 这一条是同一根病因的第二个症状，而且是先有探针
   跑出 `⌘* → cmd+8` 才发现的：菜单印 ⌘* 时，它**声明的是 ⌘，存的是字符 "*"**——
   因为 "*" 没法不按 ⇧ 打出来， shift 就在字符里。只回答"键码 28"就会叫出 `cmd+8`，
   而用户的手写的是 ⇧⌘8、键盘半边记的是 `cmd+shift+8`：一个快捷键两个字符串，
   采纳检测永远不响。所以答案同时带 `needsShift`，读取那边把它并进菜单声明的修饰键。
   受影响的是**所有移位标点命令**——⌘*、⌘?、⌘}、⌘|、⌘!、⌘@、⌘<、⌘>、⌘~、⌘_、⌘+，
   一个都不小。

### 6. 菜单半边也要过键盘半边的那道过滤器

真机复测（辅助功能和输入监控都授了）暴露出两个症状：

| 操作 | 菜单上印着 | 记录下来的 | 卡片教的 |
|---|---|---|---|
| Finder：显示 › 进入全屏幕 | 🌐F | `f` | 按 F |
| Finder：窗口 › 居中 | 🌐⌃C | `ctrl+c` | 按 ⌃C |

单独按 F 不会进入全屏。第一张卡片因此**永远不会被判为"已采纳"**——LessMouse 的键盘统计从来不记录单独的字母。第二张更糟：它会在用户于终端里按 ⌃C 中断程序时被误判为"已采纳"。

同一批测试还发现：如果一个菜单快捷键**不带 ⌘、⌥、⌃**（AX 修饰掩码是 8 或 9，也就是"不带 ⌘"或"⇧，不带 ⌘"），字符 `A` 会被记成 `a` 或 `shift+a`，写进 `stats.json`，并为它生成卡片。而 LessMouse 对隐私的承诺是：单独的字母（包括 ⇧+字母）就是在打字，键盘这边从来不记录。

**两个症状，一个根因：菜单半边从来没有应用键盘半边的那条规则。** `KeySignatureFilter` 的第 2 条——"不带 ⌘/⌥/⌃ 的非导航键是文字，丢掉"——只被键盘半边执行；`Facts.shortcut` 自己另有一套更宽的标准（"读到了修饰掩码，就算有快捷键"）。

而"不带 ⌘/⌥/⌃"在菜单里是**正常读数，不是怪癖**：

- 有些菜单就是只印一个移位字符，不带任何命令修饰键。
- **fn（🌐）快捷键的修饰位不是 ⇧/⌥/⌃ 里的任何一个。** 这一条上一轮判错了，见下。

修法是把那条规则提出来，两半共用一份定义——`KeySignatureFilter.isCommand(key, modifiers:)`。键盘半边对每次按键调它，菜单半边对每条读出来的快捷键调它。`MenuShortcut.isRecordableGesture` 是它的门面，三个生产调用点都走这一道：`AXMenuAccessibility.shortcut(fromKeyCode:character:modifierMask:)`（读取时）和 `MenuRuleFactory` 的 `candidates` / `rule(for:)`（生成卡片时）。

`MenuRuleFactory` 也加这一道，是为了**已经写进 stats.json 的旧数据**：之前版本写下的 `a`、`shift+a` 不再生成卡片，60 天滚动过后自然消失。

实测全矩阵（真 `NSMenu` + 真 accessibility，fn 家族和去掉 fn 的同一快捷键并排）：

| 菜单项 | AppKit 存下的掩码 | AX 掩码 | AX 字符 | 修好前 | 修好后 |
|---|---|---|---|---|---|
| 🌐F | 0 | 8 | F | `f` | 无 |
| 🌐⇧F | 131072 | 9 | F | `shift+f` | 无 |
| 🌐⌃C | 262144 | 12 | C | `ctrl+c` | `ctrl+c` |
| 🌐⌥A | 524288 | 10 | A | `opt+a` | `opt+a` |
| 🌐⌘F | 1048576 | 0 | F | `cmd+f` | `cmd+f` |
| 裸 F | 0 | 8 | F | `f` | 无 |
| 裸 A | 0 | 8 | A | `a` | 无 |
| ⇧A | 131072 | 9 | A | `shift+a` | 无 |
| ⌘F | 1048576 | 0 | F | `cmd+f` | `cmd+f` |
| ⇧⌘F | 1179648 | 1 | F | `cmd+shift+f` | `cmd+shift+f` |
| ⌃C | 262144 | 12 | C | `ctrl+c` | `ctrl+c` |
| ⌥A | 524288 | 10 | A | `opt+a` | `opt+a` |

#### 上一轮的结论错在哪：fn 在 accessibility 这一侧是存在的

上一轮写的是"fn 在 accessibility 这一侧**从未存在过**，包括 LessMouse 的键盘那一半"，
并把 🌐⌃C、🌐⌥A、🌐⌘F 判为"修不掉"。**这个结论只对自造菜单成立，不能当成普遍事实。**

它是这么来的：探针自己用 `NSMenu` 造菜单，而 AppKit 在 `setKeyEquivalentModifierMask:`
时静默丢掉 `NSEvent.ModifierFlags.function`，日志说得很清楚——"…is only supported for
system-provided menu items; will not be used"。**自造菜单因此永远看不到 fn 位。** 拿一个
结构上不可能出现 fn 的实验去证明 fn 不存在，是拿工具的限制当了系统的属性。

真机复测（macOS 27，辅助功能和输入监控都授了）在 Finder 和 Chrome 的系统菜单项上量到：
`AXMenuItemCmdModifiers` 有一个第 5 位（值 16），公开 SDK 里没有它——
`AXAttributeConstants.h` 的常量到 NoCommand 为止，Carbon 的 `kMenu*Modifier` 枚举也到那里
为止。实测读数：

| 应用 | 菜单命令 | 印出来 | CmdChar | CmdModifiers |
|---|---|---|---|---|
| Finder / Chrome | 显示 › 进入全屏幕 | 🌐F | F | 24 |
| Finder / Chrome | 显示 › 进入全屏幕（另一项） | 🌐F | F | 20 |
| Finder / Chrome | 编辑 › 表情与符号 | 🌐E | E | 24 |
| Finder / Chrome | 窗口 › 居中 | 🌐⌃C | C | 28 |
| Finder / Chrome | 窗口 › 填充 | 🌐F | F | 28 |

危险的不是这个未知的位，而是把它读成"没有"之后剩下的东西——**剩下的掩码和一个确实表示
别的意思的掩码逐字节相同**：

| 掩码 | 二进制 | 丢掉第 5 位之后 | 会被教成 |
|---|---|---|---|
| 28 | 11100 | ⌃ \| NoCommand | `ctrl+c` |
| 20 | 10100 | ⌃（⌘ 隐含） | `cmd+ctrl+f` |
| 16 | 10000 | 0 = ⌘ alone | `cmd+f` |
| 24 | 11000 | NoCommand | 无（被"裸字母不是命令"挡掉） |

前三个都是**真实存在、用户真的在按**的快捷键。其中 `ctrl+c` 最坏：用户在中断终端里的
程序时，卡片会被误判为"已采纳"。第 4 行（24）是唯一一个读错了也不出事的那一位，而它
不出事纯属侥幸——它剩下的恰好是"不带 ⌘"，被第 1 轮那条命令过滤器挡住了。**一个只在
别的检查恰好兜住的地方错的掩码，不叫被读对了。**

而这个位还**验不了**：键盘半边的 tap 从来不读 `.maskSecondaryFn`（`CGEventNormalizer`
只建 ⌘/⌥/⌃/⇧ 四个掩码），所以按 🌐⌃C 时键盘半边写下的签名和按 ⌃C 时一模一样，采纳检测
永远不可能确认一张 fn 卡片。宁可漏，不可错。

修法因此不是给这一位起名字，而是**拒绝任何带公开 SDK 四个位之外修饰位的掩码**：

```swift
static func carriesAnUnverifiableModifier(mask: Int) -> Bool {
    let documented = AXMenuItemModifiers(rawValue: 0b1111)
    return !AXMenuItemModifiers(rawValue: UInt32(truncatingIfNeeded: mask))
        .isSubset(of: documented)
}
```

它在翻译的**最前面**执行，任何解码之前。不假设第 5 位是 fn、也不假设只有第 5 位会出现——
`for mask in 16..<256` 全扫过，一个都教不出来。反过来，四个已文档化的位照旧解码
（⌃C、⌥⇧O、Emacs 键都还在），这条过滤器针对的是**读不出来的修饰键**，不是修饰键。

**不影响之前修好的那些。** 过滤器只问"掩码里有没有已文档化之外的位"，一个字都不问键
本身，所以：

- ⌘2（掩码 0 + "2"）→ `cmd+2`，不变
- ⇧⌘B（掩码 1 + "B"）→ `cmd+shift+b`，不变——⇧ 仍由菜单声明
- ⇧⌘M（掩码 1 + "M"）→ `cmd+shift+m`，不变
- ⌘\*、⌘?、⌘+（移位标点）→ `cmd+shift+8`、`cmd+shift+slash`、`cmd+shift+equal`，不变——⇧ 仍由字符推断
- 方向键、F 键、⌫、⇧⌘F5 → 不变
- ⌃Q、⌥A、Emacs 键、⌃⇥ → 不变，而且有测试专门守着

`MenuGestureTests` 里有一条就是拿这批签名逐个断言的
（`theShortcutsTheRetestCheckedSurviveTheMenuReadingPath`）。

### 7. 灰色的命令不计

点了灰色（禁用）的菜单项，命令不会执行，菜单甚至不会关。所以它既不该记一次使用，也不该
清掉挂起的菜单——菜单还开着，下一个点击仍然要能解析。`kAXEnabledAttribute` 对 AppKit
搭出来的每个元素都稳定可读，因此加进属性列表，`MenuItemSnapshot.isEnabled` 透出来，
`resolve` 对禁用项直接返回 nil 而不动 `pending`。

### 8. 读菜单不在主 actor 上

`kill -STOP` 卡住 TextEdit 之后点它的菜单栏，每次点击堵住 LessMouse 主线程约 1.5 秒
（健康应用约 0.1 秒），界面和键盘计数一起停。原因是整个状态机加 accessibility 读取都在
主 actor 上，而读别的应用的菜单就是等它——一个不响应的应用会让 accessibility API 跟着等。

现在状态机和全部读取都在 `MenuClickTracker` 自己的一条串行 `DispatchQueue` 上，结果经
`Task { @MainActor in }` 回主线程。卡住的应用只拖慢教练自己；读取途中到来的点击排队等
它的轮次。串行是因为状态是序列——两次点击乱序解析，两次都解析不对。

菜单栏矩形也一并不在主 actor 上取：`MenuBarGeometry.strip()` 在派发前就算好，因为 AppKit
属于调用方线程。顺带修掉一个 trap——`NSApp` 在没启动过应用的进程里是 nil，直接读会崩；
现在 `NSApp?.mainMenu?.menuBarHeight ?? 24`，而这样的进程本来也没有菜单栏可量。

**队列解决了主线程，没解决"迟到"。** `kill -STOP` 之后每个元素约 1.5 秒，而一个菜单从
点开到选中命令之间用户不会等——排在一个卡死应用后面的点击，等轮到它时菜单早关了，这一次
习惯就丢了，而且没有任何卡片能解释为什么。所以每个元素都设了 messaging timeout：

```swift
static let messagingTimeout: Float = 0.25
```

为什么是 0.25：实测健康应用约 0.1 秒，卡死应用约 1.5 秒/元素，四分之一秒对健康的留足余量，
对卡死的把每次点击的代价压到菜单还在屏幕上的范围内。

**为什么逐元素设，而不是在 application 上设一次：** 从父元素属性里取出来的子元素是一个
**新的对象，带默认 timeout**。只在顶层设一次，走到命令那一层时超时已经失效了——而慢的
读取恰恰发生在那一层。

### 9. 卡片是运行时生成的，不是写死的

`MenuRuleFactory` 把签名变成一张 `SuggestionRule`：

- 阈值：一天内鼠标点了 3 次，且键盘只覆盖了其中不超过 34%——"已经在按了的人不用教"
- 一天最多 3 张，按点击量排序，同量按签名排序（保证同一天里货架不重排）
- id 是 `menu-click:cmd+s`，稳定，所以卡片状态能跨启动存活
- 标题/正文对所有命令是同一套文案，摘要才带参数："You clicked %@ in the menu %ld times today"

引擎因此多了一个 `dynamicRuleFor: (String) -> SuggestionRule?` 注入点：书里的规则是
静态的，菜单教练的规则是运行时发现的，两者在同一个评估里并列出现。

### 10. 存储：又一种货币

`menuCommands: { "cmd+s": 3 }`，按天、按应用分桶，形状和 `combos` 完全一致。鼠标点击和
键盘按键是两种货币，互不混淆：一天 40 次菜单点击、零按键，只会唤醒菜单教练的卡片，
书里那些一张都不会响。老文件没有 `menuCommands` 字段，`decodeIfPresent` 兜住。

### 11. 默认关闭：没要过这个功能的人，一点代价都不付

`isMenuCoachEnabled` **缺省是关的**，用户在设置里打开。上一版默认开启，这一版改回来，
理由是这个功能的成本是**对所有用户**收的：tap 多监听一个 `.leftMouseDown`，LessMouse 就
开始在全系统范围看每一次按下鼠标。没授辅助功能权限的用户付了这份监听，却永远等不到一张
卡片——他们为一个自己没要过的功能付出了成本，而回报是零。

```swift
// A missing key means "never decided", which is off — the user turns the
// coach on in Settings rather than finding it already listening.
self.isMenuCoachEnabled = defaults.object(forKey: Key.menuCoach) == nil
    ? false
    : defaults.bool(forKey: Key.menuCoach)
```

用 `object(forKey:)` 而不是 `bool(forKey:)` 判空：缺省值是"从没决定过"，而 `bool` 会把
缺省读成 `false` 和"明确关掉"混为一谈——虽然这一版两者行为相同，但区分开，以后想给
"从没决定过"一个不同的入口（比如首次引导）时不必改存储语义。

关闭时是**一路关到底**的：`refreshMenuCoachAvailability()` 在关闭时连
`AXIsProcessTrusted()` 都不调——那是一个对别的进程 UI 的查询，没开教练的用户不该被
LessMouse 问起任何别的应用的界面。tap 的掩码也退回只有 keyDown（`KeyboardMonitor.eventMask`
是个纯函数，测试直接断言它，不必真的去建一个 tap）。

权限这一侧照旧只查不弹：`AXIsProcessTrusted()` 只查不请求，没授权时教练休眠，设置页
多一行解释，加一个"打开系统设置"的按钮——一扇门，不是一次敲门。一个 1.5 秒的轮询器
**只在"教练开着且读不到"时**运行，用户从系统设置回来那一行就消失了，然后轮询器自己停掉。

### 12. 界面

- 今日台账多出第四行"菜单命令"，只在教练开启时出现——关掉的人看到的还是原来三行
- 设置里"追踪"模块：暂停行 + 分隔线 + 教练开关 +（读不到时）辅助功能行
- 卡片详情页、庆祝横幅、统计页都通过 `state.rule(withID:)` 解析，动态卡片和书里卡片
  走同一条渲染路径
- **卡片印的符号和菜单里印的一致。** 菜单显示"⌥⌘⎋"，卡片和统计页原来印"⌥⌘esc"。
  改的是 `KeyWhitelist` 里 `esc` 那一项的 `displaySymbol`，存储 token 仍是 `"esc"`——
  磁盘上的签名一个字节都没变。`KeyCap.key(String)` 本来就带字形，`Fmt.signatureDisplay`
  也本来就过 `KeyWhitelist.displayByToken`，所以改一处，卡片键帽、详情页那句话、统计页
  三处同时跟上。其余需要改的只有 `esc` 一个：⇥、⌫、⌦、←、→、↑、↓、↖、↘、⇞、⇟ 和
  F1–F12 早就和菜单印的一样。

### 13. 前台应用的跟踪：通知发到了错误的 NotificationCenter

顺带修掉一个**先于菜单教练存在**的 bug。`AppContextProvider` 观察
`NSWorkspace.didActivateApplicationNotification`，但装在了 `NotificationCenter.default`
上——而 workspace 通知发到的是 `NSWorkspace.shared.notificationCenter`，默认中心
**永远收不到**。实测：装在默认中心时，前台 bundle id / pid 在整个进程生命周期里停在
LessMouse 启动那一刻的那个应用上。

症状不炸不报，只是全错：菜单教练拿**过期的 pid** 去读**别的应用**的菜单；按应用的统计、
按应用的排除名单全部失效；依赖切换应用的卡片（⌘Tab、⌃Tab、⌘\`）一个都不动。

```swift
observer = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, ...)
```

回归测试 `AppContextProviderTests` 故意发**两次**激活通知——一次证明观察者会响，两次证明
它继续响，而"卡在第一个值上不再动"这个症状一次投递是抓不出来的。

## 取舍

| 决定 | 换来了什么 | 代价 |
|---|---|---|
| 默认关闭，用户在设置里打开 | 没要过这个功能的人一点代价都不付：不监听鼠标、不调一次 AX | 授权了的用户也要多点一下开关 |
| 只读 `leftMouseDown` | 拖拽选中命令的手势看不见 | 见"已知限制"第一条 |
| 菜单内容延迟到第二次点击才读 | 普通点击零成本 | 若菜单在两次点击间关闭，这一次不计（宁可漏，不可错） |
| 只看菜单栏区域 | 文档里的点击连 accessibility API 都到不了 | 依赖菜单栏矩形；高度取 AppKit 而非常量 |
| 快捷键走"键码优先，字符兜底"两条路 | 可打印的快捷键全部能教，且和键盘半边同一个键 | 多一个 `KeyboardLayoutKeys`，和一个每布局一次的构建 |
| 字符→键码问真实键盘布局 | Dvorak 等非 QWERTY 用户的采纳检测也响 | 布局数据拿不到时（部分 IME）该命令教不了 |
| 字符同时回答"要不要按着 ⇧" | 移位标点命令（⌘\*、⌘?、⌘}）教的是用户真正按的那一下 | 答案从一个整数变成两个字段；⇧ 的 bit 要认出来而不是假设 |
| ⇧ 的 bit 用语义认（大写字母 + 移动数字键） | 换布局、换 Carbon 常量都不影响；caps lock 和 ⌥ 都被排除 | 每布局多扫 8×128 次翻译，仍然是零点几毫秒 |
| 菜单半边复用键盘半边的命令判定（`isCommand`） | 菜单教得出的每个手势，键盘都记得到；裸字母进不了 stats.json | 读取和生成卡片各多一次函数调用 |
| 掩码里出现已文档化之外的位 → 整条读数作废 | 不会教出一个用户按不出来的快捷键，也不会为一个别的快捷键庆祝 | 带 fn 的快捷键（🌐F、🌐⌃C）教不了，见"已知限制"第 7 条 |
| 缺一个修饰掩码当掩码 0（⌘ alone） | 不漏掉一个 ⌘S——有些应用报键等效值时不报掩码 | 极少见（真机上字符在时掩码总在），代价是几行 |
| 每个 AX 元素都设 messaging timeout | 卡死的应用不再让点击迟到，习惯不再无声丢失 | 慢应用（>0.25s/元素）的命令教不出来，但那种应用本来也点不动 |
| 状态机搬到自己的串行队列 | 被观察的应用卡死不再卡住 LessMouse | 命中结果晚一个队列轮次到达，UI 上是无感的 |
| 菜单栏高度 `NSApp?.mainMenu`，取不到回退 24 | 没有 NSApp 的进程不再 trap | CLI 进程量不到真实高度（但它也没有菜单栏） |
| 一张卡一套文案 | 没有 N 套要维护、要翻译的命令文案 | 摘要得靠格式化参数带出快捷键 |
| 阈值 3 次/天、上限 3 张 | 卡片稀少，出现时确凿 | 重度菜单用户也只看得到前三名 |
| 采纳后卡片保留在货架上 | 统计页的分母稳定，"已采纳"不会因为习惯消失而蒸发 | `rules` 里会留着几张不再触发的卡片 |

## 验证

- **`swift test`：132 个测试 / 14 个套件，全绿。** 其中 62 个是新的：
  - `MenuCoachTests`（16）——两次点击的完整状态机：子菜单、无快捷键的命令、
    过期菜单、点错清空、切应用、没权限、空菜单栏、签名往返、修饰键掩码表，
    **禁用项不计**（含"整菜单全灰"和"灰项之后菜单仍开着"两种），外加两条这一轮补的：
    **tap 只在教练开启时才监听鼠标**（断言掩码本身，不必真去建一个 tap），
    **accessibility 读取必须有界**（0.05s–1s）
  - `AppContextProviderTests`（3）——这一轮新增，守的是上一轮修掉的那个
    NotificationCenter bug：激活通知必须更新前台快照，而且**必须继续更新**（两次投递）
  - `KeyboardLayoutKeysTests`（10）——字符→键码这条新路径的不变量：可打印字符都能落到
    白名单里的键、菜单报的大写字母折成同一个键、移位标点（`>`、`?`、`*`）也找得到键、
    **私用区功能键字符绝不走布局这条路**、字符折叠与缓存稳定，以及两条这次才补上的：
    **移位字符必须把 ⇧ 带进签名**、**未移位字符不得凭空继承一个 ⇧**，外加一条对
    ASCII + Latin-1 全区"菜单半边和键盘半边必须一致"的扫描
  - `MenuGestureTests`（10）——菜单半边能教什么、不能教什么。
    包括 fn 家族按真机读数逐条钉住（🌐F、🌐⇧F → 无；掩码 24/20/28 → 无）、
    裸字母和 ⇧+字母写不进 stats.json、裸导航键仍可教、⌘/⌃/⌥-only 仍可教、
    移位标点仍带 ⇧、缺掩码当 ⌘ alone，
    以及最强的一条：**扫遍白名单里每个键码 × 每个可打印字符 × 全部 32 种掩码
    （0–15 是 SDK 文档化的四位，16–31 是带着 fn 位的那些），
    菜单半边叫得出的每一个签名，键盘半边必须原样记得**——不是等价，是同一个字符串
  - `MenuSuggestionTests`（23）——候选排序/上限/比例/不可绘制、触发器阈值、
    键盘半边压住、采纳、不重复庆祝、永久关闭；存储的计数/分天/旧文件解码；
    以及一条从鼠标点击到庆祝横幅的端到端管线。新增的两条钉住**旧数据**和**默认值**：
    `a`、`shift+a`、`f` 这类签名即使已经在 stats.json 里，也不再生成卡片；
    教练默认关闭，且关闭时不记点击、不出卡片
- **原有 70 个测试一个没删、没改弱**，其中 `PopoverLayoutTests` 顺带覆盖了新界面
  （设置页四个模块都会真实渲染一遍）。
- **改动前先探测过唯一有风险的一步**：把 `.leftMouseDown` 加进 tap 掩码会不会让 tap
  更难创建。独立探针的结论是"不会"——单独 keyDown、单独鼠标、两者合并、全鼠标+键盘
  四种掩码在同一个进程里创建结果一致，且与顺序无关。因此鼠标那半被做成**可开关的**：
  不想要的人看到的行为和以前逐位相同。
- **NotificationCenter 那个 bug 用变异测试确认过**：把
  `NSWorkspace.shared.notificationCenter` 改回 `NotificationCenter.default`，
  `AppContextProviderTests` 三条同时炸；改回来重新全绿。
- **隐私边界由构造保证**：标题字段不存在，单测断言"普通点击 `readCount == 0`"。

### 问题 1 是怎么确认修好的

这个环境拿不到辅助功能权限（`AXIsProcessTrusted()` 是 `false`）。弥补办法建立在一条
macOS 行为上：**一个进程永远能读自己的 UI 元素，不需要授权。** 于是造一个真的
`NSMenu`，往里塞 44 条带真键等效值的命令，然后用**真的** `AXMenuAccessibility` 读它。
探针落在仓库里（`Tools/VerifyMenuCoach.swift`），一条命令就能跑，见"验证工具"一节。

为此 `AXMenuAccessibility` 多了一个 `readMenuBar(pid:)`：就是读取本身，不带信任门。
生产路径从不走它——`MenuClickTracker` 读的应用从来不是自己（`AppState` 已经把自己的
bundle id 滤掉了）。留着它是为了让读取那半能在真数据上被检查，而不是靠一个测试里根本
搭不出来的假 `AXUIElement`。

44 条命令的签名全部正确，其中 10 条是"必须答不出快捷键"的：

```
ok  Save   cmd+s        ok  Escape        cmd+opt+esc     ok  Option A     opt+a
ok  Close  cmd+w        ok  Tab           cmd+tab         ok  Control Q    ctrl+q
ok  Two    cmd+2        ok  F3            cmd+f3          ok  Ctrl Shift P ctrl+shift+p
ok  Bkmk   cmd+shift+b  ok  F5            cmd+shift+f5    ok  No Equiv     nil
ok  Mnm    cmd+shift+m  ok  F1 / F12      cmd+f1/f12      ok  Space        nil
ok  Slash  cmd+slash    ok  Fwd Delete    cmd+delete      ok  Return       nil
ok  Brack  cmd+bracketLeft  ok  Enclosing cmd+up         ok  Globe F      nil
ok  Minus  cmd+shift+minus  ok  Backspace cmd+backspace  ok  Globe ⇧F     nil
ok  Period cmd+shift+period ok  Quote   cmd+quote        ok  Bare A       nil
ok  Semi   cmd+semicolon    ok  Zero    cmd+0            ok  Bare F       nil
ok  BkSlsh cmd+backslash    ok  Grave   cmd+grave        ok  Shift A      nil
ok  Star   cmd+shift+8      ok  Plus    cmd+shift+equal  ok  Greyed Save  cmd+s (isEnabled=n)
ok  Qmark  cmd+shift+slash  ok  Globe ⌃C ctrl+c          ok  Bare Slash / One  nil
```

再往下验一层，才是这个功能的真正承诺：**菜单这半边和键盘这半边必须叫出同一个手势。**

这里有个坑值得记下来。第一版交叉验证是**假的**：它拿菜单自己报的修饰键去喂键盘那条路，
当然逐字节相同，什么都没证。现在的比较换成了一个独立判据——在探针里**直接**问键盘布局
（绕开 `KeyboardLayoutKeys`，那正是被测的代码）"哪个键印这个字符、要不要按着 ⇧"，
再据此构造手势。34 条全部一致，移位标点那几条正是靠这一层抓出来的：

```
agree  Star  cmd+shift+8    keycode 28     agree  Slash  cmd+slash       keycode 44
agree  Plus  cmd+shift+equal keycode 24    agree  Brack  cmd+bracketLeft keycode 33
```

在没有 ⇧ 推断时，这两条会退化成 `cmd+8` 和 `cmd+equal`——和键盘永久错开，采纳检测
对它们永远不响。

禁用项也顺着真状态机走了一遍：点灰色的 Save 什么都不记，紧接着点可用的 Save 照旧
记 `cmd+s`——证明菜单没被误清。同一段还顺带把两个 fn 掩码（24、28）过了一遍真
`MenuClickTracker`，断言它们什么都记不下来。

### 问题 1 第二轮（fn 和裸字母）是怎么确认修好的

这一轮的两个症状都出在"读到了什么"，所以判据也升级成**不变量**而不是用例：菜单半边
叫得出的每一个签名，键盘半边必须原样记得——同一个键、同一组修饰键、同一个字符串。
三个地方各自钉了一层：

1. **纯函数那一层。** 读取里的翻译被收拢成 `AXMenuAccessibility.shortcut(fromKeyCode:character:modifierMask:)`——吃真 accessibility 会报的那三个数，吐签名。于是 `MenuGestureTests` 能拿真机读数直接驱动它：fn 家族逐条（🌐F、🌐⇧F → 无）、裸 A、⇧A、裸标点、裸数字 → 无；⌘/⌃/⌥-only、裸导航键、移位标点 → 照旧。最强的一条扫遍**白名单里每个键码 × 每个可打印 ASCII 字符 × 全部 32 种掩码（含 fn 位）**，对每个非空结果断言键盘半边给出同一个字符串——它守的是没人想到要写下来的那些组合，不只是上面这几个。
2. **旧数据那一层。** `MenuSuggestionTests` 新增一条：`a`、`shift+a`、`f` 即使已经在 stats.json 里也不再生成卡片，而 `cmd+f`、`ctrl+c`、`esc` 照旧。之前版本写下去的东西不会永远缠着用户。
3. **真 accessibility 那一层。** 探针里多了 6 条 fn / 无命令修饰键的命令（共 35 条），以及一段新的检查：把每条读出来的快捷键按 token 反查键码，喂给键盘半边的过滤器，断言它**收下**且字符串相同。这一段在两个半场都跑——自己读自己跑一遍，有权限时前台应用再跑一遍。

修好前后在同一台机器上逐条对照（真 `NSMenu` + 真 accessibility，fn 家族和去掉 fn 的同一个快捷键并排）：

| 菜单项 | AppKit 存下的掩码 | AX 掩码 | AX 字符 | 修好前 | 修好后 |
|---|---|---|---|---|---|
| 🌐F | 0 | 8 | F | `f` | 无 |
| 🌐⇧F | 131072 | 9 | F | `shift+f` | 无 |
| 🌐⌃C | 262144 | 12 | C | `ctrl+c` | `ctrl+c` |
| 🌐⌥A | 524288 | 10 | A | `opt+a` | `opt+a` |
| 🌐⌘F | 1048576 | 0 | F | `cmd+f` | `cmd+f` |
| 裸 F | 0 | 8 | F | `f` | 无 |
| 裸 A | 0 | 8 | A | `a` | 无 |
| ⇧A | 131072 | 9 | A | `shift+a` | 无 |
| ⌘F | 1048576 | 0 | F | `cmd+f` | `cmd+f` |
| ⇧⌘F | 1179648 | 1 | F | `cmd+shift+f` | `cmd+shift+f` |
| ⌃C | 262144 | 12 | C | `ctrl+c` | `ctrl+c` |
| ⌥A | 524288 | 10 | A | `opt+a` | `opt+a` |

**不影响之前修好的那些。** 第一轮的过滤器只问"有没有 ⌘/⌥/⌃"，一个字都不问键本身；
第二轮的过滤器只问"掩码里有没有已文档化之外的位"，也不问键本身。两个都不碰键，所以：

- ⌘2（掩码 0 + "2"）→ `cmd+2`，不变
- ⇧⌘B（掩码 1 + "B"）→ `cmd+shift+b`，不变——⇧ 仍由菜单声明
- ⇧⌘M（掩码 1 + "M"）→ `cmd+shift+m`，不变
- ⌘\*、⌘?、⌘+（移位标点）→ `cmd+shift+8`、`cmd+shift+slash`、`cmd+shift+equal`，不变——⇧ 仍由字符推断
- 方向键、F 键、⌫、⇧⌘F5 → 不变
- ⌃Q、⌥A、Emacs 键、⌃⇥ → 不变，而且有测试专门守着

`MenuGestureTests` 里有一条就是拿这批签名逐个断言的
（`theShortcutsTheRetestCheckedSurviveTheMenuReadingPath`），而且它是直接驱动**原始读取
路径**（`fromKeyCode:character:modifierMask:`）而不是构造好的 `MenuShortcut`。

**还剩的风险：跨进程读取没在这个环境验过。** 自己读自己不需要授权，读别的应用要；
这里没有权限，所以 Finder / Chrome / VS Code 的真实菜单栏没被读过。已知而未验的具体是：

- 别的应用（尤其是非 AppKit 的）上报的 `AXMenuItemCmdChar` 形状是否和 AppKit 一致
- 那里的 `kAXEnabledAttribute` 是否同样稳定可读
- 虚拟键码属性在真实应用里是否也只对功能键作答

### 验证工具：`Tools/VerifyMenuCoach.swift`

一条命令跑完五节，其中三节不需要任何权限：

```sh
swift build
swiftc -o verify-menu-coach -I .build/debug -L .build/debug -lLessMouseCore \
  Tools/VerifyMenuCoach.swift
DYLD_LIBRARY_PATH=.build/debug ./verify-menu-coach
```

| 节 | 内容 | 要权限吗 |
|---|---|---|
| 1 | 自造 `NSMenu` 的 44 条命令，用**真的** `AXMenuAccessibility` 读；再逐条和键盘半边对签名（判据是探针自己直接问键盘布局，绕开被测代码）；再拿真 `MenuClickTracker` 过一遍禁用项和 fn 项 | 不要 |
| 2 | 原始修饰掩码。五个真机量到的掩码（24/20/28）逐个过读取路径，旁边印出"丢掉第 5 位会被教成什么"；外加 `for mask in 16..<256` 全扫 | 不要 |
| 3 | **整条管线**在临时数据目录里跑：模拟鼠标选中 → `stats.json` 落到磁盘 → 卡片出现 → 模拟按 ⌘S → 卡片翻"已采纳" → 擦除。真的 `AppState`、`StatsStore`、`MenuClickTracker`；只有菜单本身是假的（CLI 进程搭不出菜单栏）。**绝不碰 `~/Library` 里的真实数据** | 不要 |
| 4 | 前台应用的**真实菜单栏**：每个菜单、每个子菜单的每一项，独立走一遍 AX（只读那三个快捷键属性，**不读标题**），列出所有带未文档化位的项、它的原始掩码、它会被教成什么 | 要 |
| 5 | `SIGSTOP` 一个 `sleep` 进程，量三次读取耗时，断言不超过 `messagingTimeout` | 要 |

第 4 节是唯一能在真机菜单上看到 fn 位的地方——自造菜单结构上不可能有它。**在有权限的
机器上跑，前台留一个真的应用**（Finder 或 Chrome 会有 fn 位，多数应用没有；没有时工具
会明说"这个应用不用 fn"，而不是报一个假通过）。

第 5 节用 `SIGSTOP` 而不是真的挂起模态框：确定，而且助手进程是个什么都不依赖的
`sleep`，退出前一定 `SIGCONT`。

**它覆盖不到的地方：**

- 真的鼠标按下和真的按键。喂给 tracker 的是合成的 `MenuClick`，喂给状态机的是合成的
  `KeyEvent`。CGEvent tap 在 CLI 进程里建不起来，所以 tap 本身这里没被测；
  `swift test` 断言的是它要的事件掩码。
- fn 位**在 AppKit 里怎么存的**。第 2 节喂的是真机报出来的掩码；要原生看到一个，只有
  系统提供的菜单项，这正是第 4 节存在的理由。
- 没权限时的耗时。第 5 节在这种情况下跳过，并说明为什么跳过。
- accessibility API 不暴露的菜单（全屏游戏、kiosk）。那些读成"没有菜单栏"，
  教练对它们也是这么做的。
- 多显示器、缩放、Retina 下的菜单栏矩形。这里量的是固定的 1440×24。

这台机器（没有辅助功能权限）上的一次完整运行：**113 过 0 败 2 跳过**——跳过的正是第 4、
5 两节，工具明说"这一半没法在这台机器上验"。

## 已知限制

1. **按住拖动再松开的选中方式不计。** tap 只看 `leftMouseDown`，"选中"那一下是
   `leftMouseUp`，监听不到。设计上退而求其次：把**下一次** `leftMouseDown` 对着还开着
   的菜单解析。所以拖拽选中 Save 当次不计（接下来若再点一下文档，命中测试失败、
   清掉挂起状态，也不会误记）。
   **为什么不用"同时监听 mouseUp"补上：** 试过，会把普通点击那条路整个打断。普通点击一个
   菜单栏项时，mouseDown 和 mouseUp **都**落在菜单栏区域内，up 会第二次跑
   `menuBarClick`，把刚挂上的 `pending` 清掉/替换掉，随后落在命令上的那一次 down 就什么都
   解析不出来。唯一可靠的判据是 down 和 up 之间有没有鼠标移动，而要拿到它就得监听
   `mouseMoved`——那是把事件量翻几倍，来换一个少数人的手势。为这个比例不值得。
2. **跨进程的 accessibility 读取未在本环境验证。** 见下一节末尾。自己读自己已充分
   验证；读别的应用只由降级行为保证（读不到 → 教练休眠 → 设置页开门），而这一条是
   被测到的。
3. **不暴露标准菜单栏的应用教不了。** 自己画菜单栏的 Electron/Java 应用、全屏游戏：
   读到空，等于没有，不报错也不打扰。
4. **没有印刷快捷键的命令教不了。** 这是特性不是缺陷，但 Quit、Preferences 这类
   确实点不到。
5. **⌘Space、⌘↩ 教不了。** 空格和回车不在 `KeyWhitelist` 里——那是键盘那一半既有的
   决定（它们太容易和输入框打字混淆），菜单这半边沿用同一个表，没有为它单开。
   **为什么不为菜单这一半单开：** `KeyWhitelist` 是两半**共用**的一张表。往里面加
   return / space 去教 ⇧⌘↩，等于同时让键盘那一半开始为**所有**用户统计 ⌘↩、⌘Space——
   那是改现有功能的行为，不是这个功能该做的事。隐私规则不是这里的门槛（命令过滤器早就
   放过 ⌘↩）；门槛是键盘半边的词汇表该不该为菜单教练长胖。
6. **只有 ⌥/⌃ 才印得出来的字符教不了。** 布局图只认"不按修饰键"和"按着 ⇧"两种状态，
   因为一个键要按着 ⌥ 才出的字符（美式布局上的 å、ç、¡）意味着用户得按住菜单从未
   声明过的修饰键，任何按键都产生不了那个签名。这类命令宁可判为"没有快捷键"，
   也不给一个错的。影响面很小：真有这种快捷键的应用，通常直接把 ⌥ 写进修饰键掩码，
   而那时字符本身是不移位的，照常能教。
7. **带 fn（🌐）的快捷键教不了。** `AXMenuItemCmdModifiers` 会报一个公开 SDK 里没有的
   位（值 16），而键盘半边的 tap 从来不读 `.maskSecondaryFn`，所以按 🌐⌃C 时键盘半边
   写下和按 ⌃C 一模一样的签名——采纳检测永远不可能确认一张 fn 卡片。任何带这一位的
   掩码因此整条作废，而不是"去掉 fn 之后照教"。实测受影响的（Finder / Chrome，macOS 27）：
   🌐F（掩码 24 / 20）、🌐E（24）、🌐⌃C（28）、🌐F（28）。
   **上一版这里写的是"🌐⌃C 会被教成 `ctrl+c`，修不掉"——那个结论是错的**，它只在我用
   `NSMenu` 自造的菜单上成立，而 AppKit 不允许非系统菜单项带 fn。见第 6 节末尾。
8. **菜单打开超过 8 秒再点，按未命中处理。** 宁可漏。
9. **Input Monitoring 被拒时教练也不会工作**——但那是整个 app 都不工作的状态，
   不是这个功能特有的。

## 文件

| 新增 | 作用 |
|---|---|
| `Monitoring/AXMenuAccessibility.swift` | 唯一接触 accessibility API 的地方，七个属性的封闭列表 |
| `Monitoring/KeyboardLayoutKeys.swift` | 字符 → 键码（外加"要不要 ⇧"），问当前键盘布局，每布局一次并缓存 |
| `Monitoring/MenuSnapshot.swift` | `MenuShortcut` / `MenuClick` / `MenuItemSnapshot`，以及读菜单的协议 |
| `Monitoring/MenuClickTracker.swift` | 两次点击的状态机 + 菜单栏矩形 + 自己的读取队列 |
| `Suggestions/MenuRuleFactory.swift` | 运行时卡片的生成、阈值、上限、稳定 id |
| `Tools/VerifyMenuCoach.swift` | 五节验证工具：自造菜单的读取、原始修饰掩码、整条管线（临时数据目录）、前台真实菜单的 fn 位、卡死应用的耗时 |

| 改动 | 改了什么 |
|---|---|
| `Monitoring/KeyboardMonitor.swift` | 掩码加 `.leftMouseDown`（受 `watchesMouse` 控制）；掩码的计算提成纯函数 `eventMask(watchesMouse:)`，测试能直接断言它 |
| `Monitoring/KeyEventSource.swift` | 协议多两个带默认实现的方法，`StubEventSource` 一行没改 |
| `Monitoring/AppContextProvider.swift` | 多报一个 pid；**观察装到 `NSWorkspace.shared.notificationCenter`**（原来是错的 `NotificationCenter.default`），加 `start()` 一次性安装并预热缓存 |
| `Suggestions/SuggestionRule.swift` | `RuleTrigger` 多一个 `menuCommandClicks`；`EngineContext` 多一个 `menuClicksToday` |
| `Suggestions/SuggestionEngine.swift` | `dynamicRuleFor` 注入点 |
| `Models/KeySignature.swift` | 第 2 条规则提出来成为 `isCommand(key, modifiers:)`，两半共用一份定义 |
| `Monitoring/MenuSnapshot.swift` | `MenuShortcut.isRecordableGesture`——上面那个共用的判定，菜单半边的门面 |
| `Monitoring/AXMenuAccessibility.swift` | 每个元素设 messaging timeout；缺掩码当 ⌘ alone；带未文档化修饰位的掩码整条作废 |
| `Models/KeyWhitelist.swift` | `esc` 的 `displaySymbol` 改成 `⎋`（**只改显示，存储 token 仍是 `"esc"`**） |
| `Storage/StatsModels.swift` `Storage/StatsStore.swift` | 又一种货币 `menuCommands`，旧文件照常解码 |
| `State/SettingsStore.swift` | `lm.menuCoach` 开关，**缺省视为关闭** |
| `State/AppState.swift` | 管线接线、`rules` / `rule(withID:)` / 可用性轮询 / 打开设置面板；关闭时连 `AXIsProcessTrusted()` 都不调 |
| `Views/*` | 台账第四行、设置两行、卡片与统计走统一解析路径 |

| 新增测试 | 守的是什么 |
|---|---|
| `Tests/LessMouseTests/MenuGestureTests.swift` | 菜单半边能教什么、不能教什么：fn 家族（含掩码 24/20/28）、裸字母、裸导航键、移位标点、缺掩码，以及"能教的键盘都记得到"的全区扫描 |
| `Tests/LessMouseTests/AppContextProviderTests.swift` | 前台应用快照跟着激活通知走，而且**继续**跟着走（两次投递）——NotificationCenter 那个 bug 的回归 |

---

## 稳定性修复与弹出提示（本地真机体验之后）

真机安装体验中出现了几次闪退、几次"开了却不工作"。逐一定位后修复如下，每一条都配了回归测试（`Tests/LessMouseTests/StabilityAndNoticeTests.swift`），并用"把修复改回去、测试必须变红"验证过测试本身。

| 现象 | 根因 | 修复 |
|---|---|---|
| 中文系统下，出现菜单卡片后闪退（弹窗关着也会） | `rule.menuClick.summary` 中英文参数顺序相反，`%@` 拿到了整数；弹窗内容在关闭后仍每秒重新渲染 | 中文改为 `%2$ld 次 %1$@`；新增测试逐条比对两种语言的参数类型；`rules` 只在真正变化时才重新发布 |
| 在 Chrome 等 app 里点菜单时偶发闪退 | 键盘布局查询（TIS API）在后台读菜单的队列上调用，新版 macOS 只允许主线程调用 | 布局表在主线程构建（启动时、切换输入法时），后台只读缓存 |
| 运行中打开"也教菜单命令"不生效 | `@Published` 在写入新值之前通知订阅者，回调读到的仍是旧值 | 回调直接使用收到的新值 |
| 重新授权"输入监控"后键盘统计不再增长 | 监听被系统停用或权限被撤销后，没人发现，也不会重建 | 每 2 秒检查一次：权限被撤销就转入等待授权，监听失效就重建，启动被拒就退避重试；同时处理"被用户输入停用"这一种情况 |
| 副屏上的 app，菜单点击识别不了 | 只把主屏顶部当作菜单栏 | 每块显示器的菜单栏都算 |
| 其他隐患 | 别的 app 报告的异常键码/修饰键会触发整数转换崩溃；菜单递归无深度上限；卡死的 app 让每一项都等满超时、点击无限排队；监听重启时旧线程可能清掉新监听；启动握手无超时；同时采用两张卡时第一张的庆祝丢失、重启后庆祝也丢失；关闭教练后引擎仍会生成菜单卡片；写盘竞态会丢计数、退出和睡眠前不写盘；菜单栏图标每秒从磁盘重读；打包脚本漏拷资源包导致启动即崩 | 均已修复 |

**弹出提示**：`AppState.notices` 在"出现新建议（含冷却期后再次提醒）"和"建议被采纳"两个时刻各发一次事件；`NoticePresenter` 在菜单栏图标正下方弹出一个不抢焦点的浮动小卡片，点一下打开面板，几秒后自动收起。新建议：图标泛起两圈波纹，旁边是要学的键帽；采纳：勾号弹性放大，一圈光环加几颗光点。系统开启"减少动态效果"时只淡入淡出。设置里有"弹出提示"开关，默认开启（不需要任何权限）。
