# 参与修改

## 任务

项目成员有待做的事，直接改 `docs/任务.md`，合并进 `main`。一条任务怎么移动，看那份文件的开头。

不是项目成员的，在 Issue 里提出来，或者用 Pull Request 提出来。不保证会加进去。

## 自定义

这个项目最重要的是高度自定义。想把界面改成另一种样子时，增加一种新样式，原来的样式留着。只有原来的样式客观上有问题，才直接改它。

## 改代码

macOS 14 或更高，部署目标是 macOS 14，语言是 Swift 6。

```bash
xcodebuild -project MacPower.xcodeproj -scheme MacPower -destination 'platform=macOS' build
```

- 不要重新格式化 `MacPower/Localizable.xcstrings`，也不要调整已有键的顺序。同一个语言对象里不能出现重复的键。
- 改菜单栏电池图标时，在 Pull Request 里放上修改前和修改后的对比。
- 不要提交令牌或本机配置，例如 `~/.netrc`、百度网盘和阿里云盘的凭据。
- 给用户看的更新说明写在 `MacPower/ReleaseNotes.json`。每个版本只留这一版，11 种语言都要写。任务清单不代替这份说明。
