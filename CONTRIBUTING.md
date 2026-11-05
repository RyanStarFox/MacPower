# 参与修改

## 任务

任务记在 `docs/todo.md`。一条任务只放在一个小节里。空小节留「目前没有。」，标题保留。

每条任务开头写一个或多个标签，紧挨着、不加空格，例如 `- [bug][UI] 说明`。常用标签是 `[bug]`、`[feature]`、`[UI]`。需要别的标签时用同样的方括号写法。已归档的旧任务可以不补标签。

新任务写进「待做」，直接提交并推到 `main`，不开分支，也不开 Pull Request。不是项目成员的，在 Issue 里提出来，或者用 Pull Request 提出来。不保证会加进去。

认领某一条时，开一个新分支，把它剪到「正在做」，写成 `- [标签] 任务说明（姓名）`，署上自己的名字，再用 Pull Request 合并进 `main`。这条做完并合并进 `main` 之后，从「正在做」剪到「已做完归档」的「下一个版本」。

需要开发者账号的写在「有开发者账号之后做」，买到之前不要开工。已发布的版本用版本号做标题，例如 `2.1.2`。还没发布的改动先放在「下一个版本」下面。发布时把「下一个版本」改成确定的版本号，并在它上面重新放一个空的「下一个版本」。

和本项目相关的 skill 都放在 `docs/skills/`。现在有两份：改任务清单看 `macpower-todo.md`，发版看 `macpower-release.md`。

仓库里的这份是远端副本。本机还各有一份，任务清单在 `~/.cursor/skills/macpower-todo/SKILL.md`，发版在 `~/.cursor/skills/macpower-release/SKILL.md`。改 skill 时两处都要改，内容保持一致。只改一边，下次按 skill 做事就会和仓库里的约定分开。

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
