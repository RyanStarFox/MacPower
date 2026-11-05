# 参与修改

## 环境

macOS 14 或更高。部署目标是 macOS 14，语言是 Swift 6。

```bash
xcodebuild -project MacPower.xcodeproj -scheme MacPower -destination 'platform=macOS' build
```

## 改动时请注意

- 不要重新格式化 `MacPower/Localizable.xcstrings`，也不要调整已有键的顺序。同一个语言对象里不能出现重复的键。
- 改菜单栏电池图标时，在 Pull Request 里放上修改前和修改后的对比。
- 不要提交令牌或本机配置，例如 `~/.netrc`、百度网盘和阿里云盘的凭据。
