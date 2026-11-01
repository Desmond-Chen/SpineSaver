# 隐私说明

SpineSaver 是一个纯本地的 macOS 菜单栏休息提醒器。它不联网、没有账号、没有云同步。

## 不做什么

- 不发送任何网络请求。
- 不读取键盘输入内容。
- 不申请辅助功能、输入监控或屏幕录制权限。
- 不读取其它应用的内容。
- 不记录健康数据、喝水记录或如厕记录。
- 不做任何形式的身体活动推断。

## 本机保存了什么

| 数据 | 位置 |
| --- | --- |
| 设置（工作分钟数、休息分钟数、提醒方式、登录启动、随机提醒画面） | UserDefaults 域 `com.desmond.spinesaver` |
| 本轮进度与休息快照 | UserDefaults 域 `com.desmond.spinesaver` |
| 使用习惯事件（屏幕计时、提醒、推迟、休息开始/完成/提前结束/取消/放弃、应用退出） | `~/Library/Application Support/SpineSaver/history.jsonl` |

历史记录是事件级 JSONL，`schemaVersion` 为 1，保留到你主动删除为止。

## 你能做什么

- 在"统计…"窗口查看记录范围、导出 CSV 或 JSON（由你选择保存位置）。
- 在"统计…"窗口删除全部历史，需要二次确认。
- 重置设置不会删除历史。
- 删除 `~/Library/Application Support/SpineSaver/history.jsonl` 也能清空历史。

## 记录的边界

这些记录只说明应用内的计时与操作，不能证明你已起身、已休息或做过任何具体动作。导出的文件由你主动保存，应用不会自动发送。
