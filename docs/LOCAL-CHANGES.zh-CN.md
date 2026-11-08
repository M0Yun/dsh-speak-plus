# 本地增强（相对上游 dsh-speak 1.8.4）

这个包是 [dsh-speak](https://github.com/Alan2Z/dsh-speak) 1.8.4 的本地增强分支。上游的
朗读能力、设置页、WebSocket 状态、引擎脚本全部保留，下面这些是新增或修改的部分。所有新
行为默认关闭或保守取值，不配置时与上游完全一致。

## 新增能力

### 0. GPT-SoVITS 引擎适配（可选，需自行安装）

插件带 `engine/speak-sovits.ps1`，但**不打包 GPT-SoVITS**，只调用本机已运行的
`api_v2`（默认 127.0.0.1:9880）。配置 `sovitsEndpoint` / `sovitsRefAudio` /
`sovitsPromptText` / `sovitsTextLang` / `sovitsPromptLang` / `sovitsSpeed`。
参考音频没配或服务没起时自动回退 SAPI。详见 README「GPT-SoVITS」一节。

### 1. 中间过程成段朗读（`queueAllMessages` 模式的修正）

上游开启 `queueAllMessages` 后，每条 assistant 消息都会立即独立入队。模型在工具调用之间
往往只吐一两句话，于是朗读被切成很碎的片段。

本分支把连续到达的正文先攒起来，安静 `interimMergeMs` 毫秒后作为**一段完整文本**播报：

| 配置 | 默认 | 说明 |
| --- | --- | --- |
| `interimMode` | `queue` | `queue`：回合内各段排队读完，互不打断；`replace`：每段新内容立刻顶掉正在播的 |
| `interimMergeMs` | `800` | 攒多久合并成一段，`0` = 不合并 |
| `interimMaxBacklog` | `180` | 待播正文最多积压多少字；超出时丢弃最旧的，避免越读越落后 |

### 2. 新内容打断（`interruptOnNewMessage` / `interruptOnNewTurn`）

| 配置 | 默认 | 说明 |
| --- | --- | --- |
| `interruptOnNewMessage` | `false` | 打开后启用本分支的打断逻辑（正文之间是否互顶由 `interimMode` 决定） |
| `interruptOnNewTurn` | `false` | `false`：提交消息本身不打断，等新回合真的产出内容时再换手；`true`：按发送就掐断当前朗读 |

### 3. 审批 / 提问播报优先

`approval/asked` 与 `ask_user_question` 的播报是优先项：

- 正在念正文时来了审批/提问 → 立刻打断正文，先念它
- 正在念审批/提问时来了新正文 → 排队等待，绝不打断
- 打断正文时，队列里没播的旧正文一并丢弃（过期内容不再占用时间）

### 4. Alt + S 停止播报

浏览器端在 capture 阶段监听 `Alt+S`，命中后 `POST /dsh-speak/control {action:"stop"}`：
停掉当前子进程、清空待播队列、丢弃攒着还没播的中间片段。设置页「总开关」下方有一行提示。

> DSH 核心的「快捷键」列表只列核心自己的动作，插件无法注册进去；这个键位由插件自己绑定。

### 5. 配置兜底读取（`loadPatchConfig`）

某些 DSH 构建里插件构建配置 schema 会失败（宿主 Node 拒绝从 CJS 加载 ESM 的
`@deepseek-ai/cosmokit`），此时 `Config` 为空，Loader 交给插件的配置也是空的，所有字段
退化成默认值——表现为 `queueAllMessages` 被当成 `false`、自定义 `engine` 不生效。

本分支在启动时直接读本 profile 的 `cordis.patch.yml`，按 mtime 缓存，只取已知键，与 Loader
传入的活配置合并（活配置优先）。挂载时会打一行 `生效配置: ...`，便于排查。

## 与上游的兼容性

- 不配置任何新键时，行为与上游 1.8.4 一致（`interruptOnNewMessage` 默认 false 时走原有 FIFO）
- 保留上游的 `/dsh-speak/control`、`/dsh-speak/ws`、设置页、手动重播
- 上游 `engine/speak.ps1`、`engine/speak.sh` 未改动

## 测试

`_speak-patch\test-interim.js` 是与宿主解耦的行为测试（fake spawn，不发声），覆盖合并、
排队、replace、新回合换手、审批优先、积压上限六个场景：

```
node test-interim.js
```

## 许可证

MIT，继承上游 LICENSE；上游版权归 Alan2Z 所有。
