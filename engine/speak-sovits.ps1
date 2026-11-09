<#
speak-sovits.ps1 — dsh-speak-plus 的 GPT-SoVITS 引擎适配（可选）

说明：本脚本**不包含** GPT-SoVITS，也不安装它。它只负责把文本 POST 给一个已经在
本机运行的 GPT-SoVITS `api_v2.py` 服务，拿回 wav 并播放。没装/没起服务时自动回退到
内置的 SAPI 引擎。

前置条件（自行安装，插件不提供）：
  * GPT-SoVITS 仓库与 V2ProPlus 权重
  * `python api_v2.py -a 127.0.0.1 -p 9880 -c GPT_SoVITS/configs/tts_infer.yaml`
  * 一段 3～10 秒的参考音频（ref_audio_path）

插件侧配置（cordis.patch.yml）：
  engine: '<插件目录>\engine\speak-sovits.ps1'
  sovitsEndpoint: 'http://127.0.0.1:9880'
  sovitsRefAudio: 'D:\voice\ref.wav'
  sovitsPromptText: '参考音频里说的原话'
  sovitsTextLang: 'zh'
  sovitsPromptLang: 'zh'
  sovitsSpeed: 1
#>
param(
    [string]$File = '',
    [string]$Text = '',
    [int]$Volume = 50,
    [double]$Rate = 0,
    [int]$MaxChars = 0,
    [string]$LongTextMode = 'message',
    [string]$LongTextMessage = '',
    [int]$CleanMarkdownFormatting = 1,
    [int]$ReadInlineCode = 1,
    [string]$CodeBlocks = 'smart',
    [int]$CodeBlockMaxChars = 300,
    [string]$CodeBlockReplacementText = '',
    [int]$FullRead = 0,
    # ---- GPT-SoVITS ----
    [string]$SovitsEndpoint = 'http://127.0.0.1:9880',
    [string]$SovitsRefAudio = '',
    [string]$SovitsPromptText = '',
    [string]$SovitsTextLang = 'zh',
    [string]$SovitsPromptLang = 'zh',
    [double]$SovitsSpeed = 1.0,
    [int]$SovitsChunkChars = 90,
    [string]$SovitsFallbackEngine = '',
    [int]$SovitsFallbackRate = 0,
    [int]$SovitsDebugChunks = 0
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 回退链：显式指定的回退引擎（通常是晓晓）> 同目录 speak.ps1（系统语音）
$FallbackEngine = $SovitsFallbackEngine
if (-not $FallbackEngine -or -not (Test-Path -LiteralPath $FallbackEngine)) {
    $FallbackEngine = Join-Path $PSScriptRoot 'speak.ps1'
}

function Get-Body {
    param([string]$Inline, [string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    return $Inline
}

function Convert-ToSpeechText {
    param([string]$Raw)
    if (-not $Raw) { return '' }
    $t = $Raw
    if ($CleanMarkdownFormatting -eq 1) {
        $t = $t -replace '(?ms)^```.*?^\s*```', ' '
        $t = $t -replace '!\[[^\]]*\]\([^)]*\)', ' '
        $t = $t -replace '\[([^\]]+)\]\([^)]*\)', '$1'
        $t = $t -replace 'https?://\S+', ' '
        $t = $t -replace '[`*_>#~]', ' '
        $t = $t -replace '\|', '，'
    }
    $t = $t -replace '[ \t]+', ' ' -replace '\r?\n+', '。'
    $t = $t -replace '。{2,}', '。' -replace '，。', '。'
    return $t.Trim()
}

function Split-Chunks {
    # 贪心：一直攒到上限，再回退到上限前最近的标点截断；上限前没标点就往后找
    # 最近的标点（最多再找 Limit 字），实在没有才硬切。不会每遇到一个逗号就断一次。
    param([string]$Body, [int]$Limit = 60)
    $chunks = New-Object System.Collections.Generic.List[string]
    $text = $Body.Trim()
    $pattern = '[。！？!?；;…，,、：:\n]'
    $start = 0
    while ($start -lt $text.Length) {
        $remain = $text.Length - $start
        if ($remain -le $Limit) {
            $tail = $text.Substring($start).Trim()
            if ($tail) { $chunks.Add($tail) }
            break
        }
        $window = $text.Substring($start, $Limit)
        $hits = [regex]::Matches($window, $pattern)
        if ($hits.Count -gt 0) {
            $cut = $start + $hits[$hits.Count - 1].Index + 1
        } else {
            $aheadLen = [Math]::Min($Limit, $text.Length - $start - $Limit)
            $ahead = $text.Substring($start + $Limit, $aheadLen)
            $m = [regex]::Match($ahead, $pattern)
            if ($m.Success) { $cut = $start + $Limit + $m.Index + 1 } else { $cut = $start + $Limit }
        }
        $piece = $text.Substring($start, $cut - $start).Trim()
        if ($piece) { $chunks.Add($piece) }
        $start = $cut
    }
    return $chunks
}
function Invoke-Fallback {
    param([string]$Body, [string]$Why)
    if (-not $FallbackEngine -or -not (Test-Path -LiteralPath $FallbackEngine)) { return }
    [Console]::Out.WriteLine("sovits unavailable ($Why), falling back to: $FallbackEngine ($($Body.Length) chars)")
    $tmp = [IO.Path]::GetTempFileName() + '.txt'
    Set-Content -LiteralPath $tmp -Value $Body -Encoding UTF8
    $sapiRate = [int][math]::Max(-10, [math]::Min(10, [math]::Round($SovitsFallbackRate)))
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $FallbackEngine -File $tmp -Volume $Volume -Rate $sapiRate -MaxChars $MaxChars -LongTextMode $LongTextMode -LongTextMessage $LongTextMessage -CleanMarkdownFormatting $CleanMarkdownFormatting -ReadInlineCode $ReadInlineCode -CodeBlocks $CodeBlocks -CodeBlockMaxChars $CodeBlockMaxChars -CodeBlockReplacementText $CodeBlockReplacementText -FullRead $FullRead
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}

$raw = Get-Body -Inline $Text -Path $File
if (-not $raw -or -not $raw.Trim()) { exit 0 }
$body = Convert-ToSpeechText -Raw $raw
if (-not $body) { exit 0 }
if ($MaxChars -gt 0 -and $body.Length -gt $MaxChars -and $LongTextMode -eq 'message' -and $LongTextMessage) {
    $body = $LongTextMessage
}
if (-not $SovitsRefAudio -or -not (Test-Path -LiteralPath $SovitsRefAudio)) {
    Invoke-Fallback -Body $body -Why 'no reference audio configured'
    exit 0
}

# 插件 -Rate（-10..10）叠加到 sovitsSpeed 上
# 语速只由 -SovitsSpeed 决定（宿主已按 -10..10 换算成倍率），不再叠加 -Rate
$speed = [math]::Max(0.5, [math]::Min(2.0, [double]$SovitsSpeed))

$player = New-Object System.Media.SoundPlayer
# 强制成数组：只有一段时函数返回的是字符串，直接索引会取到单个字符
$chunks = @(Split-Chunks -Body $body -Limit ([math]::Max(20, $SovitsChunkChars)))
if ($SovitsDebugChunks -eq 1) {
    [Console]::Out.WriteLine("chunks: " + $chunks.Count)
    $chunks | ForEach-Object { [Console]::Out.WriteLine("  [" + $_.Length + "] " + $_) }
}
for ($chunkIndex = 0; $chunkIndex -lt $chunks.Count; $chunkIndex++) {
    $chunk = $chunks[$chunkIndex]
    $payload = @{
        text              = $chunk
        text_lang         = $SovitsTextLang
        ref_audio_path    = $SovitsRefAudio
        prompt_text       = $SovitsPromptText
        prompt_lang       = $SovitsPromptLang
        media_type        = 'wav'
        streaming_mode    = $false
        speed_factor      = $speed
        text_split_method = 'cut5'
        batch_size        = 1
    } | ConvertTo-Json -Compress

    $wavPath = Join-Path $env:TEMP ("dsh-sovits-{0}.wav" -f ([guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri ($SovitsEndpoint.TrimEnd('/') + '/tts') -Method POST -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -OutFile $wavPath -TimeoutSec 300 | Out-Null
        $player.SoundLocation = $wavPath
        $player.PlaySync()
    } catch {
        [Console]::Out.WriteLine("sovits tts failed: $($_.Exception.Message)")
        # 回退引擎（晓晓/SAPI）不需要按佩丽卡的分段来念：把当前段和剩余段拼起来一次交过去
        $restText = ($chunks[$chunkIndex..($chunks.Count - 1)] -join '')
        Invoke-Fallback -Body $restText -Why 'api error'
        break
    } finally {
        Remove-Item -LiteralPath $wavPath -ErrorAction SilentlyContinue
    }
}
