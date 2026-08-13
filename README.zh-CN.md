# LessMouse

> 菜单栏上的快捷键教练——它观察你的键盘习惯，发现低效动作，告诉你能救它的快捷键。

**开发中。** 完整文档随首个发布版本提供。英文文档见 [README](README.md)。

## 隐私（全部政策）

LessMouse **绝不记录你输入的内容**。它只统计：

- 你已在使用的快捷键（⌘C、⌥⌫……）的次数，
- 导航类按键（退格、方向键、Home/End……）的次数,
- 检测到的低效模式（如"两秒内连按五次退格"）的次数。

仅聚合计数，本地存储在
`~/Library/Application Support/LessMouse/stats.json`，随时可以打开查看。
代码库**零网络访问、零第三方依赖**——欢迎审计，这正是开源的意义。

## 构建

```bash
swift build
swift test
swift run LessMouse
```

macOS 14+，Swift 5.9+。

## 许可

MIT——见 [LICENSE](LICENSE)。
