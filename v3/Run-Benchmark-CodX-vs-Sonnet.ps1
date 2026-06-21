# =============================================================================
# CodX vs Claude Sonnet 4.6 - Cosine Similarity Benchmark
# 50 questions across 5 domains
# Both scored by same cosine metric (local embedding model)
# No external scorer - zero cost scoring
# Folder: C:\Users\Berkani\Desktop\Benchmark
# =============================================================================

param(
    [string]$CodXBaseUrl     = "https://www.solvatex.com/codx/api/v1",
    [string]$CodXApiKey      = $env:CODX_API_KEY,
    [string]$OpenRouterKey   = $env:OPENROUTER_API_KEY,
    [string]$OutputDir       = "C:\Users\Berkani\Desktop\Benchmark",
    [string]$OutputFile      = "codx_vs_sonnet_cosine.csv",
    [int]$StartFromQuestion  = 1,
    [int]$EndAtQuestion      = 50,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BenchmarkDate  = (Get-Date -Format "yyyy-MM-dd")
$OutputPath     = Join-Path $OutputDir $OutputFile
$LogPath        = Join-Path $OutputDir ("cosine_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

$SonnetModel    = "anthropic/claude-sonnet-4-6"
$OpenRouterUrl  = "https://openrouter.ai/api/v1/chat/completions"

# Claude Sonnet 4.6 pricing on OpenRouter (USD per 1M tokens)
$SonnetInputPricePerM  = 3.0
$SonnetOutputPricePerM = 15.0

# =============================================================================
# MISSION PROMPTS (identical to CodX engine.py for fair comparison)
# =============================================================================

$MissionPrompts = @{
    "Generate Code"  = "You are an expert software engineer. Generate clean, well-documented, production-ready code based on the request."
    "Security Audit" = "You are an expert security auditor. Analyze the following code or system for security vulnerabilities, provide severity ratings, and suggest fixes."
    "System Audit"   = "You are an expert system architect. Analyze the following system and provide a comprehensive audit covering architecture, performance, scalability, and recommendations."
    "Debug & Fix"    = "You are an expert debugger. Analyze the following code and error, identify the root cause, and provide a complete fixed version with explanation of what was wrong and why the fix works."
    "Code Review"    = "You are an expert code reviewer. Review the following code and provide detailed feedback on quality, best practices, performance, security, and maintainability. Suggest specific improvements."
}

# =============================================================================
# QUESTIONS (same 50 as Race11 benchmark for comparability)
# =============================================================================

$Benchmark = @{
    "Generate Code" = @(
        "Q1  [Easy] Return the first non-repeating character in a string."
        "Q2  [Easy] Group users by country from a list of dictionaries."
        "Q3  [Easy] Fetch weather data with error handling."
        "Q4  [Medium] SQL query for top customers in last 30 days."
        "Q5  [Medium] Implement a Go worker pool."
        "Q6  [Medium] Implement an O(1) LRU cache."
        "Q7  [Hard] Distributed rate limiter using Redis."
        "Q8  [Hard] Kafka consumer with retries and DLQ."
        "Q9  [Hard] Trie with autocomplete support."
        "Q10 [Hard] URL shortener backend API."
    )
    "Security Audit" = @(
        "Q11 [Easy] Identify SQL injection vulnerability."
        "Q12 [Easy] Find hardcoded secret exposure."
        "Q13 [Easy] Review weak authentication logic."
        "Q14 [Medium] Detect path traversal issue."
        "Q15 [Medium] Detect command injection risk."
        "Q16 [Medium] Audit JWT validation logic."
        "Q17 [Hard] Identify SSRF vulnerability."
        "Q18 [Hard] Audit public cloud storage configuration."
        "Q19 [Hard] Review unsafe object deserialization."
        "Q20 [Hard] Full login endpoint security assessment."
    )
    "System Audit" = @(
        "Q21 [Easy] Identify single points of failure."
        "Q22 [Easy] Audit logging strategy."
        "Q23 [Easy] Evaluate backup frequency."
        "Q24 [Medium] Improve microservice resilience."
        "Q25 [Medium] Audit database scaling approach."
        "Q26 [Medium] Review CI/CD pipeline gaps."
        "Q27 [Hard] Kubernetes cluster audit."
        "Q28 [Hard] Incident response readiness review."
        "Q29 [Hard] Event-driven architecture audit."
        "Q30 [Hard] Enterprise architecture modernization."
    )
    "Debug & Fix" = @(
        "Q31 [Easy] Fix off-by-one error."
        "Q32 [Easy] Fix null reference bug."
        "Q33 [Easy] Fix infinite loop."
        "Q34 [Medium] Fix async/await bug."
        "Q35 [Medium] Fix race condition."
        "Q36 [Medium] Fix database connection leak."
        "Q37 [Hard] Resolve deadlock."
        "Q38 [Hard] Fix memory leak."
        "Q39 [Hard] Investigate CrashLoopBackOff."
        "Q40 [Hard] Analyze production outage."
    )
    "Code Review" = @(
        "Q41 [Easy] Improve readability."
        "Q42 [Easy] Remove duplicate logic."
        "Q43 [Easy] Improve error handling."
        "Q44 [Medium] Optimize performance."
        "Q45 [Medium] Review resource management."
        "Q46 [Medium] Improve API design."
        "Q47 [Hard] Review database scalability."
        "Q48 [Hard] Review XSS vulnerability."
        "Q49 [Hard] Review concurrent access bug."
        "Q50 [Hard] Full service review."
    )
}

# =============================================================================
# DOMAIN -> CODX ENDPOINT ROUTING
# =============================================================================

$DomainConfig = @{
    "Generate Code" = @{
        Endpoint    = "/generate"
        AnswerField = "final_output"
    }
    "Security Audit" = @{
        Endpoint    = "/audit/security"
        AnswerField = "audit_report"
    }
    "System Audit" = @{
        Endpoint    = "/audit/system"
        AnswerField = "audit_report"
    }
    "Debug & Fix" = @{
        Endpoint    = "/debug"
        AnswerField = "fix_report"
    }
    "Code Review" = @{
        Endpoint    = "/review"
        AnswerField = "review_report"
    }
}

# =============================================================================
# BUILD FLAT QUESTION LIST
# =============================================================================

$Questions = foreach ($domain in $Benchmark.Keys) {
    foreach ($entry in $Benchmark[$domain]) {
        if ($entry -match '^(Q\d+)\s+\[(Easy|Medium|Hard)\]\s+(.+)$') {
            [PSCustomObject]@{
                Id     = $Matches[1]
                Domain = $domain
                Level  = $Matches[2]
                Text   = $Matches[3].Trim()
            }
        }
    }
}
$Questions = $Questions | Sort-Object { [int]($_.Id -replace 'Q','') }

# =============================================================================
# HELPERS
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        default { "Cyan" }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Invoke-CodX {
    param([string]$Endpoint, [string]$Prompt)
    $url = $CodXBaseUrl + $Endpoint
    if ($Endpoint -like "*/audit/*") {
        $reqBody = @{ code = $Prompt; language = "auto" } | ConvertTo-Json -Depth 4
    } else {
        $reqBody = @{ prompt = $Prompt; language = "auto" } | ConvertTo-Json -Depth 4
    }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($reqBody)
    return Invoke-RestMethod -Uri $url -Method POST `
        -ContentType "application/json; charset=utf-8" `
        -Headers @{ "X-API-Key" = $CodXApiKey } `
        -Body $bodyBytes -TimeoutSec 120
}

function Invoke-Sonnet {
    param([string]$SystemPrompt, [string]$UserPrompt)
    $reqBody = @{
        model = $SonnetModel
        messages = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
        max_tokens = 4096
    } | ConvertTo-Json -Depth 4
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($reqBody)
    return Invoke-RestMethod -Uri $OpenRouterUrl -Method POST `
        -ContentType "application/json; charset=utf-8" `
        -Headers @{ "Authorization" = "Bearer $OpenRouterKey" } `
        -Body $bodyBytes -TimeoutSec 120
}

function Invoke-CodXScore {
    param([string]$Prompt, [string]$Response)
    $url = $CodXBaseUrl + "/score"
    $reqBody = @{ prompt = $Prompt; response = $Response } | ConvertTo-Json -Depth 4 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($reqBody)
    return Invoke-RestMethod -Uri $url -Method POST `
        -ContentType "application/json; charset=utf-8" `
        -Headers @{ "X-API-Key" = $CodXApiKey } `
        -Body $bodyBytes -TimeoutSec 60
}

# =============================================================================
# MAIN
# =============================================================================

Write-Log "=============================================="
Write-Log " CodX vs Claude Sonnet 4.6"
Write-Log " Cosine Similarity Benchmark"
Write-Log " 50 questions - 5 domains"
Write-Log " Scorer: local embedding model (local)"
Write-Log "=============================================="
Write-Log "Output : $OutputPath"
Write-Log "Range  : Q$StartFromQuestion to Q$EndAtQuestion"
if ($DryRun) { Write-Log "MODE   : DRY RUN" "WARN" }

if (-not $DryRun) {
    if (-not $CodXApiKey) {
        Write-Log "Missing env var: CODX_API_KEY" "ERROR"
        exit 1
    }
    if (-not $OpenRouterKey) {
        Write-Log "Missing env var: OPENROUTER_API_KEY" "ERROR"
        exit 1
    }
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$csvHeader = "test_id,domain,level,prompt_summary,codx_score,codx_time_s,codx_cost_usd,sonnet_score,sonnet_time_s,sonnet_cost_usd,winner,date"
if (-not (Test-Path $OutputPath)) {
    $csvHeader | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Created: $OutputFile"
} else {
    Write-Log "Appending to: $OutputFile" "WARN"
}

$toRun = @($Questions | Where-Object {
    $num = [int]($_.Id -replace 'Q','')
    $num -ge $StartFromQuestion -and $num -le $EndAtQuestion
})

Write-Log "Running $($toRun.Count) questions..."

$done = 0
$codxWins = 0
$sonnetWins = 0
$ties = 0
$failures = 0
$totalCodxCost = 0.0
$totalSonnetCost = 0.0

foreach ($q in $toRun) {
    $done++
    $cfg = $DomainConfig[$q.Domain]
    $sysPrompt = $MissionPrompts[$q.Domain]
    $enrichedPrompt = $sysPrompt + "`n`n" + $q.Text

    Write-Log "------------------------------------------"
    Write-Log "[$done/$($toRun.Count)] $($q.Id) - $($q.Domain) - $($q.Level)"
    Write-Log "  Q: $($q.Text)"

    if ($DryRun) { Write-Log "  [DRY RUN] Skipping" "WARN"; continue }

    $codxScore = 0.0
    $codxTime = 0.0
    $codxCost = 0.0
    $codxOk = $false

    $sonnetScore = 0.0
    $sonnetTime = 0.0
    $sonnetCost = 0.0
    $sonnetOk = $false

    # ---- STEP 1: Call CodX ----
    try {
        $sw = Get-Date
        $codxResp = Invoke-CodX -Endpoint $cfg.Endpoint -Prompt $q.Text
        $codxTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        $codxScore = [double]$codxResp.quality_score
        $codxCost = [math]::Round([double]$codxResp.total_cost_usd, 6)
        $codxOk = $true
        $csRound = [math]::Round($codxScore, 4)
        Write-Log "  CodX   : ${codxTime}s | score: $csRound | cost: `$$codxCost" "OK"
    } catch {
        $codxTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        Write-Log "  CodX   : FAILED after ${codxTime}s - $_" "ERROR"
        $failures++
    }

    # ---- STEP 2: Call Claude Sonnet via OpenRouter ----
    $sonnetText = ""
    try {
        $sw = Get-Date
        $sonnetResp = Invoke-Sonnet -SystemPrompt $sysPrompt -UserPrompt $q.Text
        $sonnetTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        $sonnetText = [string]$sonnetResp.choices[0].message.content

        $inTok = 0
        $outTok = 0
        if ($sonnetResp.usage) {
            $inTok = [int]$sonnetResp.usage.prompt_tokens
            $outTok = [int]$sonnetResp.usage.completion_tokens
        }
        $sonnetCost = [math]::Round(($inTok * $SonnetInputPricePerM + $outTok * $SonnetOutputPricePerM) / 1000000, 6)
        Write-Log "  Sonnet : ${sonnetTime}s | tokens: $inTok in / $outTok out | cost: `$$sonnetCost" "OK"
    } catch {
        $sonnetTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        Write-Log "  Sonnet CALL FAILED after ${sonnetTime}s - $_" "ERROR"
        $failures++
    }

    # ---- STEP 3: Score Sonnet's response via CodX /score endpoint ----
    if ($sonnetText.Length -gt 0) {
        try {
            $scoreResp = Invoke-CodXScore -Prompt $enrichedPrompt -Response $sonnetText
            $sonnetScore = [double]$scoreResp.cosine_similarity
            $ssRound = [math]::Round($sonnetScore, 4)
            Write-Log "  Sonnet score (cosine): $ssRound" "OK"
            $sonnetOk = $true
        } catch {
            Write-Log "  SCORE FAILED - $_" "ERROR"
            $failures++
        }
    }

    # ---- STEP 4: Determine winner ----
    $winner = "error"
    if ($codxOk -and $sonnetOk) {
        $diff = [math]::Abs($codxScore - $sonnetScore)
        if ($diff -lt 0.005) {
            $winner = "tie"
            $ties++
        } elseif ($codxScore -gt $sonnetScore) {
            $winner = "CodX"
            $codxWins++
        } else {
            $winner = "Claude Sonnet"
            $sonnetWins++
        }
    } elseif ($codxOk) {
        $winner = "CodX"
        $codxWins++
    } elseif ($sonnetOk) {
        $winner = "Claude Sonnet"
        $sonnetWins++
    }

    $c1 = [math]::Round($codxScore, 4)
    $c2 = [math]::Round($sonnetScore, 4)
    Write-Log "  >>> WINNER: $winner (CodX $c1 vs Sonnet $c2)" "OK"

    $totalCodxCost += $codxCost
    $totalSonnetCost += $sonnetCost

    # ---- Write CSV row ----
    $maxLen = [math]::Min(55, $q.Text.Length)
    $summary = ($q.Text.Substring(0, $maxLen)) -replace ',',';'
    $cs = [math]::Round($codxScore, 6)
    $ss = [math]::Round($sonnetScore, 6)
    $row = "$($q.Id),$($q.Domain),$($q.Level),$summary,$cs,$codxTime,$codxCost,$ss,$sonnetTime,$sonnetCost,$winner,$BenchmarkDate"
    Add-Content -Path $OutputPath -Value $row -Encoding UTF8

    Start-Sleep -Seconds 2
}

# =============================================================================
# SUMMARY
# =============================================================================

$totalQuestions = $done
$codxAvg = 0.0
$sonnetAvg = 0.0
if ($totalQuestions -gt 0) {
    $codxPctRaw = [math]::Round(($codxWins / $totalQuestions) * 100)
    $sonnetPctRaw = [math]::Round(($sonnetWins / $totalQuestions) * 100)
} else {
    $codxPctRaw = 0
    $sonnetPctRaw = 0
}

Write-Log "=============================================="
Write-Log " BENCHMARK COMPLETE"
Write-Log " CodX vs Claude Sonnet 4.6 (Cosine)"
Write-Log "=============================================="
Write-Log " Questions   : $totalQuestions"
Write-Log " CodX wins   : $codxWins ($codxPctRaw pct)"
Write-Log " Sonnet wins : $sonnetWins ($sonnetPctRaw pct)"
Write-Log " Ties         : $ties"
Write-Log " Failures     : $failures"
Write-Log " CodX cost    : `$$([math]::Round($totalCodxCost, 4))"
Write-Log " Sonnet cost  : `$$([math]::Round($totalSonnetCost, 4))"
Write-Log "----------------------------------------------"
Write-Log " Results: $OutputPath"
Write-Log " Log    : $LogPath"
Write-Log "=============================================="
