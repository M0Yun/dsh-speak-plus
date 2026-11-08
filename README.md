# dsh-speak-plus 🔊

让 DeepSeek Harness 把回答**念出来**——而且中间过程也念，不是只念最后一句。

> 本仓库是 [dsh-speak](https://github.com/Alan2Z/dsh-speak) `1.8.4` 的增强分支（MIT 许可）。
> 上游的朗读、队列、设置页、WebSocket 状态同步全部保留，另外补了五项能力。
> **所有新增行为默认关闭或取保守值，不配置时与上游一致。**

英文文档见 [README.en.md](README.en.md)；上游完整中文文档见 [docs/UPSTREAM-README.zh-CN.md](docs/UPSTREAM-README.zh-CN.md)。

---

## 为什么做这个分支

上游开启 `queueAllMessages` 后，每条 assistant 消息都会立刻独立入队朗读。但模型在工具调用之间
往往只吐一两句话，于是听感是这样的：

```
"收到——"（被切）/ "那就你自己重启。"（被切）/ "6 个场景全过。"（被切）/ …
```

本分支把连续到达的正文先攒成一段再念，并且规定了「什么时候该打断、什么时候不该」，让中间过程
听得清、也不拖得太久。

---

## 功能

| 能力 | 上游 1.8.4 | 本分支 |
|---|---|---|
| 朗读最终回复 | ✅ | ✅ |
| 朗读中间过程 | 逐条、易被切碎 | 合并成段，按序读完 |
| 新内容打断当前朗读 | ❌ | ✅ 可配（默认等新回合出内容才换手） |
| 审批 / 提问优先 | ❌（会被正文顶掉） | ✅ 插队并保护 |
| 停止播报快捷键 | ❌ | ✅ `Alt + S` |
| 括号内容不朗读 | ❌ | ✅ 默认剔除 `（）()`，括号对可配 |
| 配置读取 | 依赖设置 schema | ✅ schema 不可用时回落读 profile 配置 |
| 队列 / 状态同步 / 设置页 / 手动重播 | ✅ | ✅ 全部保留 |

---

## 安装

插件以 DSH bundle 形式挂载，在 profile 的 `cordis.patch.yml` 中配置：

```yaml
- id: dsh-speak-plus
  name: dsh-speak-plus
  config:
    queueAllMessages: true
    interruptOnNewMessage: true
    interimMode: queue
    interimMergeMs: 800
    interimMaxBacklog: 180
    engine: 'C:\Users\<你>\.dsh\profiles\desktop\data\dsh-speak-edge\speak-edge.ps1'  # 可选：自定义引擎
    rate: 8
```

Windows 用系统 SAPI 嗓音（装了 NaturalVoiceSAPIAdapter 可用自然音色），macOS 用系统 `say`。
引擎脚本与上游一致（`engine/speak.ps1`、`engine/speak.sh`），也可以用 `engine` 指向自己的脚本。

---

## 配置项

### 新增（本分支）

| 键 | 默认 | 说明 |
|---|---|---|
| `interruptOnNewMessage` | `false` | 总开关：打开后启用本分支的打断 / 合并逻辑 |
| `interruptOnNewTurn` | `false` | `false`：提交消息不打断，等新回合真的产出内容才换手；`true`：按下发送就掐断 |
| `interimMode` | `queue` | `queue`：回合内各段排队读完、互不打断；`replace`：每段新内容立刻顶掉正在播的 |
| `interimMergeMs` | `800` | 静默多久把碎片合并成一段，`0` = 不合并 |
| `interimMaxBacklog` | `180` | 待播正文最多积压多少字，超出丢弃最旧的 |
| `skipBrackets` | `true` | 括号里的补充说明不朗读 |
| `bracketPairs` | `（）()` | 每两个字符是一对；要处理 `【】` 就写成 `（）()【】` |
| `approvalPrefix` | `审核：` | 审批播报前加的固定前缀，空字符串表示不加 |

### 继承自上游（常用）

| 键 | 默认 | 说明 |
|---|---|---|
| `enabled` | `true` | 总开关，关掉后完全不出声 |
| `automaticSpeech` | `true` | 自动朗读；手动重播始终可用 |
| `queueAllMessages` | `false` | 每条 assistant 消息都入队（中间过程） |
| `throttleMs` | `1500` | 默认模式的合并延迟 |
| `engine` | 空 | 覆盖引擎脚本路径 |
| `rate` / `volume` | `0` / `50` | Windows 为 SAPI 刻度（-10~10） |
| `maxChars` | 安全值 | 超过则只念固定提示语 |
| `longTextMode` / `longTextMessage` | `message` | 超长文本的处理方式 |
| `announceApprovals` / `announceQuestions` | `true` | 审批 / 提问播报 |
| `announceTurnEnd` / `announceCommandDone` / `announceGoalChange` / `announceToolErrors` / `announceTodoWrite` | `false` | 可选事件播报 |

完整列表见上游文档。

---

## 快捷键

**`Alt + S`** —— 立刻停止播报，同时清空待播队列和还没播出的缓冲片段。

> 说明：DSH 核心的「快捷键」列表只列核心自己的动作，没有给插件预留注册入口，所以这个键位由插件
> 自己监听，不会出现在那个列表里。输入框有焦点时同样生效。

---

## GPT-SoVITS（可选，需自行安装）

插件自带引擎适配脚本 `engine/speak-sovits.ps1`，但它**不包含也不安装 GPT-SoVITS**，
只负责调用本机已经在跑的合成服务。

> 外部依赖（自行准备）：
> 1. GPT-SoVITS 本体 + V2ProPlus 权重
> 2. 启动服务：`python api_v2.py -a 127.0.0.1 -p 9880 -c GPT_SoVITS/configs/tts_infer.yaml`
> 3. 一段 3～10 秒的参考音频（就是你要的音色）
>
> 没装或服务没起时，脚本会自动回退到内置 SAPI 引擎，不会哑掉。

```yaml
- id: dsh-speak-plus
  config:
    engine: 'C:\Users\<你>\.dsh\profiles\desktop\node_modules\dsh-speak-plus\engine\speak-sovits.ps1'
    sovitsEndpoint: 'http://127.0.0.1:9880'
    sovitsRefAudio: 'D:\voice\perlica-ref.wav'
    sovitsPromptText: '参考音频里说的那句原话'
    sovitsTextLang: 'zh'
    sovitsPromptLang: 'zh'
    sovitsSpeed: 1
```

| 键 | 默认 | 说明 |
|---|---|---|
| `sovitsEndpoint` | `http://127.0.0.1:9880` | GPT-SoVITS api_v2 地址 |
| `sovitsRefAudio` | 空 | 参考音频路径；为空则回退 SAPI |
| `sovitsPromptText` | 空 | 参考音频对应的文本，填了更稳 |
| `sovitsTextLang` / `sovitsPromptLang` | `zh` | 合成文本 / 参考音频的语种 |
| `sovitsSpeed` | `1` | 语速倍率，会再叠加插件的 `rate` |
| `sovitsChunkChars` | `60` | 每段最大字数；越小首句越快出声，太小会增加请求次数 |
| `sovitsFallbackEngine` | 空 | 佩丽卡失败时用的引擎；留空则回退到 `voiceXiaoxiaoEngine`，再没有才退 SAPI |

**失败回退链**：佩丽卡 → `sovitsFallbackEngine`（一般填晓晓的 `speak-edge.ps1`）→ 内置 `speak.ps1`（系统语音）。
连接失败时把**整段**（当前分句 + 剩余分句）一次性交给回退引擎，不会把佩丽卡的 60 字分段带过去。

**性能**：服务常驻时每句约 1.5～2 秒合成（4060 8G 实测）；首次加载模型约 6 秒，
建议让 `start-api.ps1` 在登录时自启，并在启动脚本后追加一次预热
（`warmup-perlica.ps1`），这样第一句也不会等。

引擎脚本会按句切分（每段 ≤180 字）逐段请求并阻塞播放，符合插件的队列模型。

## 顶栏抽屉：音色与佩丽卡服务

对话页右上角的语音开关旁边有一个 `▾`，点开是抽屉：

- **总开关**（和设置页同一个字段）
- **音色**：`默认`（系统 SAPI）/ `晓晓`（Edge 神经音色）/ `佩丽卡`（本地 GPT-SoVITS）
- **佩丽卡服务**：状态指示点 + 「启动 / 停止」，直接控制本机 `api_v2` 进程

```yaml
- id: dsh-speak-plus
  config:
    voicePreset: perlica                        # default | xiaoxiao | perlica
    voiceDefaultEngine:  '...\engine\speak.ps1'
    voiceXiaoxiaoEngine: '...\data\dsh-speak-edge\speak-edge.ps1'
    voicePerlicaEngine:  '...\engine\speak-sovits.ps1'
    perlicaStartScript:  'D:\Dsh workspace\GPT-SoVITS\start-api.ps1'
    perlicaPort: 9880
```

| 键 | 说明 |
|---|---|
| `voicePreset` | 当前音色；抽屉里切换后会落盘到 `<profile>\data\dsh-speak-plus\voice.json`，重启保留 |
| `voiceDefaultEngine` | 「默认」用的引擎（通常是插件的 `speak.ps1`，系统语音） |
| `voiceXiaoxiaoEngine` | 「晓晓」用的引擎（Edge TTS 脚本） |
| `voicePerlicaEngine` | 「佩丽卡」用的引擎（`speak-sovits.ps1`） |
| `perlicaStartScript` | 「启动」按钮要执行的脚本（`start-api.ps1`） |
| `perlicaPort` | 服务端口，用于探活/停止 |

**启动**会后台拉起脚本并轮询端口，最多等 90 秒（首次要加载 BERT/HuBERT）；
**停止**按端口找到进程并结束，不会误杀其它 Python。
切换音色会先掐掉正在念的那句，避免新旧混在一起。

## 行为说明

**回合内的中间过程**（`interimMode: queue`）：

1. 片段按 `interimMergeMs` 合并成一段，避免一句话被拆成几次播报
2. 段与段之间排队，前一段念完再念下一段，不互相打断
3. 待播积压超过 `interimMaxBacklog` 字时丢弃最旧的，保证不会越听越落后

**换手规则**：

- 你发消息时**不掐断**当前朗读
- 新回合第一段内容要播时，才掐掉上一轮还在念的正文
- 正在念审批 / 提问时，新正文排队等待，不抢占

**配置兜底**：某些 DSH 构建里插件无法加载设置 schema，此时会直接读本 profile 的
`cordis.patch.yml`（按修改时间缓存，只取已知键），与运行时配置合并，运行时优先。
挂载时会打一行 `生效配置: …` 便于排查。

---

## 已知限制

- 设置页依赖 `Config` schema；构建失败时设置页可能不显示，此时改 YAML 即可
- 新回合内容会掐掉**其他会话**正在播的正文（同一套扬声器），不区分来源
- 直接改 `node_modules` 里的插件文件会在重装 / 升级时被覆盖

---

## 目录

```
adapters/dsh/speech-hook.js   宿主端：事件 → 队列 → 引擎
client/client.js              浏览器端：设置页、消息按钮、Alt+S
engine/                       朗读引擎（SAPI / macOS say）
docs/LOCAL-CHANGES.zh-CN.md   本分支相对上游的改动清单
docs/UPSTREAM-README.zh-CN.md 上游完整文档
```

---

## 许可

MIT，继承上游 LICENSE，上游版权归 [Alan2Z](https://github.com/Alan2Z) 所有。
