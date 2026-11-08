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
    [double]$SovitsSpeed = 1.0
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$FallbackEngine = Join-Path $PSScriptRoot 'speak.ps1'

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
    }
    return ($t -replace '[ \t]+', ' ' -replace '\r?\n+', '。').Trim()
}

function Split-Chunks {
    param([string]$Body, [int]$Limit = 180)
    $parts = [regex]::Split($Body, '(?<=[。！？!?；;\n])')
    $chunks = @(); $buf = ''
    foreach ($p in $parts) {
        if (($buf.Length + $p.Length) -gt $Limit -and $buf) { $chunks += $buf; $buf = '' }
        $buf += $p
        while ($buf.Length -gt $Limit) { $chunks += $buf.Substring(0, $Limit); $buf = $buf.Substring($Limit) }
    }
    if ($buf.Trim()) { $chunks += $buf }
    return $chunks
}

function Invoke-Fallback {
    param([string]$Body, [string]$Why)
    if (-not (Test-Path -LiteralPath $FallbackEngine)) { return }
    [Console]::Out.WriteLine("sovits unavailable ($Why), falling back to SAPI")
    $tmp = [IO.Path]::GetTempFileName() + '.txt'
    Set-Content -LiteralPath $tmp -Value $Body -Encoding UTF8
    $sapiRate = [int][math]::Max(-10, [math]::Min(10, [math]::Round($Rate)))
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $FallbackEngine -File $tmp -Volume $Volume -Rate $sapiRate -MaxChars $MaxChars -LongTextMode $LongTextMode -LongTextMessage $LongTextMessage
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
$speed = [double]$SovitsSpeed
if ($Rate -ne 0) { $speed = $speed * (1 + ($Rate / 10.0)) }
$speed = [math]::Max(0.5, [math]::Min(2.0, $speed))

$player = New-Object System.Media.SoundPlayer
foreach ($chunk in (Split-Chunks -Body $body)) {
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
        Invoke-WebRequest -Uri ($SovitsEndpoint.TrimEnd('/') + '/tts') -Method POST -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -OutFile $wavPath -TimeoutSec 180 | Out-Null
        $player.SoundLocation = $wavPath
        $player.PlaySync()
    } catch {
        [Console]::Out.WriteLine("sovits tts failed: $($_.Exception.Message)")
        Invoke-Fallback -Body $chunk -Why 'api error'
        break
    } finally {
        Remove-Item -LiteralPath $wavPath -ErrorAction SilentlyContinue
    }
}
