# =============================================================================
# CodX vs Claude Opus 4.6 - Cosine Similarity Benchmark (V4)
# 50 questions across 5 domains
# Both scored by same cosine metric (local embedding model)
# No external scorer - zero cost scoring
# =============================================================================

param(
    [string]$CodXBaseUrl     = "https://www.solvatex.com/codx/api/v1",
    [string]$CodXApiKey      = $env:CODX_API_KEY,
    [string]$OpenRouterKey   = $env:OPENROUTER_API_KEY,
    [string]$OutputDir       = "C:\Users\Berkani\Desktop\Benchmark",
    [string]$OutputFile      = "codx_vs_opus_cosine.csv",
    [int]$StartFromQuestion  = 1,
    [int]$EndAtQuestion      = 50,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BenchmarkDate  = (Get-Date -Format "yyyy-MM-dd")
$OutputPath     = Join-Path $OutputDir $OutputFile
$LogPath        = Join-Path $OutputDir ("opus_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

$OpusModel      = "anthropic/claude-opus-4-6"
$OpenRouterUrl  = "https://openrouter.ai/api/v1/chat/completions"

# Claude Opus 4.6 pricing on OpenRouter (USD per 1M tokens)
$OpusInputPricePerM  = 5.0
$OpusOutputPricePerM = 25.0

# =============================================================================
# MISSION PROMPTS
# =============================================================================

$MissionPrompts = @{
    "Generate Code"  = "You are an expert software engineer. Generate clean, well-documented, production-ready code based on the request."
    "Security Audit" = "You are an expert security auditor. Analyze the following code or system for security vulnerabilities, provide severity ratings, and suggest fixes."
    "System Audit"   = "You are an expert system architect. Analyze the following system and provide a comprehensive audit covering architecture, performance, scalability, and recommendations."
    "Debug & Fix"    = "You are an expert debugger. Analyze the following code and error, identify the root cause, and provide a complete fixed version with explanation of what was wrong and why the fix works."
    "Code Review"    = "You are an expert code reviewer. Review the following code and provide detailed feedback on quality, best practices, performance, security, and maintainability. Suggest specific improvements."
}

# =============================================================================
# QUESTIONS (same 50 as V3 for comparability)
# =============================================================================

$Benchmark = @{
    "Generate Code" = @(
        "Q1  [Easy] Write a function that checks if two strings are anagrams of each other."
        "Q2  [Easy] Build a CLI tool that converts CSV to JSON."
        "Q3  [Easy] Implement a stack using two queues."
        "Q4  [Medium] Build a REST API endpoint that paginates and filters a product catalog."
        "Q5  [Medium] Implement a thread-safe bounded blocking queue in Java."
        "Q6  [Medium] Write a recursive descent parser for arithmetic expressions with operator precedence."
        "Q7  [Hard] Implement a B-tree with insert, delete, and range query operations."
        "Q8  [Hard] Build a real-time collaborative text editor backend using operational transforms."
        "Q9  [Hard] Implement a consistent hashing ring with virtual nodes and replication."
        "Q10 [Hard] Build an event sourcing framework with snapshots and replay."
    )
    "Security Audit" = @(
        "Q11 [Easy] Audit a file upload endpoint for unrestricted file type vulnerabilities."
        "Q12 [Easy] Review a password reset flow for account enumeration risks."
        "Q13 [Easy] Check an API response for excessive data exposure in error messages."
        "Q14 [Medium] Audit an OAuth2 implementation for token leakage via redirect URI manipulation."
        "Q15 [Medium] Review a GraphQL API for introspection abuse and nested query DoS."
        "Q16 [Medium] Audit a WebSocket connection handler for origin validation and message injection."
        "Q17 [Hard] Review a multi-tenant SaaS application for cross-tenant data leakage."
        "Q18 [Hard] Audit a cryptographic key management system for key rotation and storage flaws."
        "Q19 [Hard] Analyze a microservices mesh for service-to-service authentication bypass."
        "Q20 [Hard] Full security assessment of a payment processing webhook handler."
    )
    "System Audit" = @(
        "Q21 [Easy] Evaluate DNS configuration for redundancy and failover."
        "Q22 [Easy] Audit a cron job scheduler for silent failure detection."
        "Q23 [Easy] Review a health check endpoint for accuracy and depth."
        "Q24 [Medium] Audit a message queue system for message loss and ordering guarantees."
        "Q25 [Medium] Review a caching layer for cache stampede and thundering herd problems."
        "Q26 [Medium] Audit a blue-green deployment pipeline for rollback safety."
        "Q27 [Hard] Review a distributed tracing implementation for observability gaps."
        "Q28 [Hard] Audit a multi-region active-active database replication strategy."
        "Q29 [Hard] Review a chaos engineering framework for blast radius containment."
        "Q30 [Hard] Full audit of a zero-downtime migration strategy for a 10TB database."
    )
    "Debug & Fix" = @(
        "Q31 [Easy] Fix a timezone conversion bug that shows wrong times for UTC offsets."
        "Q32 [Easy] Fix a CSS flexbox layout that breaks on mobile viewport widths."
        "Q33 [Easy] Fix a pagination bug that skips records when items are deleted mid-page."
        "Q34 [Medium] Fix a connection pool exhaustion causing intermittent HTTP 503 errors."
        "Q35 [Medium] Fix a circular dependency between three Python modules causing ImportError."
        "Q36 [Medium] Fix a React useEffect hook that causes an infinite re-render loop with stale closures."
        "Q37 [Hard] Debug a distributed transaction that leaves phantom records across two databases."
        "Q38 [Hard] Fix a garbage collection pause causing latency spikes in a Java gRPC service."
        "Q39 [Hard] Debug a split-brain scenario in a Redis Sentinel cluster after network partition."
        "Q40 [Hard] Fix a data corruption bug caused by concurrent schema migrations on a live PostgreSQL database."
    )
    "Code Review" = @(
        "Q41 [Easy] Review a Python class for Single Responsibility Principle violations."
        "Q42 [Easy] Review a REST controller for proper HTTP status code usage."
        "Q43 [Easy] Review a logging implementation for sensitive data leakage in log output."
        "Q44 [Medium] Review a database migration script for backward compatibility and rollback safety."
        "Q45 [Medium] Review an async event handler for proper backpressure and error propagation."
        "Q46 [Medium] Review a feature flag implementation for race conditions and stale state."
        "Q47 [Hard] Review a custom ORM query builder for N+1 queries and connection management."
        "Q48 [Hard] Review a rate limiting middleware for distributed bypass and clock skew issues."
        "Q49 [Hard] Review a CQRS implementation for eventual consistency edge cases."
        "Q50 [Hard] Full architecture review of a serverless event-driven order processing pipeline."
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

function Invoke-Opus {
    param([string]$SystemPrompt, [string]$UserPrompt)
    $reqBody = @{
        model = $OpusModel
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
        -Body $bodyBytes -TimeoutSec 180
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
Write-Log " CodX vs Claude Opus 4.6 (V4)"
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

$csvHeader = "test_id,domain,level,prompt_summary,codx_score,codx_time_s,codx_cost_usd,opus_score,opus_time_s,opus_cost_usd,winner,date"
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
$opusWins = 0
$ties = 0
$failures = 0
$totalCodxCost = 0.0
$totalOpusCost = 0.0

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

    $opusScore = 0.0
    $opusTime = 0.0
    $opusCost = 0.0
    $opusOk = $false

    # ---- STEP 1: Call CodX ----
    try {
        $sw = Get-Date
        $codxResp = Invoke-CodX -Endpoint $cfg.Endpoint -Prompt $q.Text
        $codxTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        $codxScore = [double]$codxResp.quality_score
        $codxCost = [math]::Round([double]$codxResp.total_cost_usd, 6)
        $codxOk = $true
        $csRound = [math]::Round($codxScore, 4)
        Write-Log "  CodX  : ${codxTime}s | score: $csRound | cost: `$$codxCost" "OK"
    } catch {
        $codxTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        Write-Log "  CodX  : FAILED after ${codxTime}s - $_" "ERROR"
        $failures++
    }

    # ---- STEP 2: Call Claude Opus via OpenRouter ----
    $opusText = ""
    try {
        $sw = Get-Date
        $opusResp = Invoke-Opus -SystemPrompt $sysPrompt -UserPrompt $q.Text
        $opusTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        $opusText = [string]$opusResp.choices[0].message.content

        $inTok = 0
        $outTok = 0
        if ($opusResp.usage) {
            $inTok = [int]$opusResp.usage.prompt_tokens
            $outTok = [int]$opusResp.usage.completion_tokens
        }
        $opusCost = [math]::Round(($inTok * $OpusInputPricePerM + $outTok * $OpusOutputPricePerM) / 1000000, 6)
        Write-Log "  Opus  : ${opusTime}s | tokens: $inTok in / $outTok out | cost: `$$opusCost" "OK"
    } catch {
        $opusTime = [math]::Round(((Get-Date) - $sw).TotalSeconds, 2)
        Write-Log "  Opus CALL FAILED after ${opusTime}s - $_" "ERROR"
        $failures++
    }

    # ---- STEP 3: Score Opus response via CodX /score endpoint ----
    if ($opusText.Length -gt 0) {
        try {
            $scoreResp = Invoke-CodXScore -Prompt $enrichedPrompt -Response $opusText
            $opusScore = [double]$scoreResp.cosine_similarity
            $ssRound = [math]::Round($opusScore, 4)
            Write-Log "  Opus score (cosine): $ssRound" "OK"
            $opusOk = $true
        } catch {
            Write-Log "  SCORE FAILED - $_" "ERROR"
            $failures++
        }
    }

    # ---- STEP 4: Determine winner ----
    $winner = "error"
    if ($codxOk -and $opusOk) {
        $diff = [math]::Abs($codxScore - $opusScore)
        if ($diff -lt 0.005) {
            $winner = "tie"
            $ties++
        } elseif ($codxScore -gt $opusScore) {
            $winner = "CodX"
            $codxWins++
        } else {
            $winner = "Claude Opus"
            $opusWins++
        }
    } elseif ($codxOk) {
        $winner = "CodX"
        $codxWins++
    } elseif ($opusOk) {
        $winner = "Claude Opus"
        $opusWins++
    }

    $c1 = [math]::Round($codxScore, 4)
    $c2 = [math]::Round($opusScore, 4)
    Write-Log "  >>> WINNER: $winner (CodX $c1 vs Opus $c2)" "OK"

    $totalCodxCost += $codxCost
    $totalOpusCost += $opusCost

    # ---- Write CSV row (no architecture secrets) ----
    $maxLen = [math]::Min(55, $q.Text.Length)
    $summary = ($q.Text.Substring(0, $maxLen)) -replace ',',';'
    $cs = [math]::Round($codxScore, 6)
    $os = [math]::Round($opusScore, 6)
    $row = "$($q.Id),$($q.Domain),$($q.Level),$summary,$cs,$codxTime,$codxCost,$os,$opusTime,$opusCost,$winner,$BenchmarkDate"
    Add-Content -Path $OutputPath -Value $row -Encoding UTF8

    Start-Sleep -Seconds 2
}

# =============================================================================
# SUMMARY
# =============================================================================

$totalQuestions = $done
if ($totalQuestions -gt 0) {
    $codxPctRaw = [math]::Round(($codxWins / $totalQuestions) * 100)
    $opusPctRaw = [math]::Round(($opusWins / $totalQuestions) * 100)
} else {
    $codxPctRaw = 0
    $opusPctRaw = 0
}

Write-Log "=============================================="
Write-Log " BENCHMARK V4 COMPLETE"
Write-Log " CodX vs Claude Opus 4.6 (Cosine)"
Write-Log "=============================================="
Write-Log " Questions   : $totalQuestions"
Write-Log " CodX wins   : $codxWins ($codxPctRaw pct)"
Write-Log " Opus wins   : $opusWins ($opusPctRaw pct)"
Write-Log " Ties        : $ties"
Write-Log " Failures    : $failures"
Write-Log " CodX cost   : `$$([math]::Round($totalCodxCost, 4))"
Write-Log " Opus cost   : `$$([math]::Round($totalOpusCost, 4))"
Write-Log "----------------------------------------------"
Write-Log " Results: $OutputPath"
Write-Log " Log    : $LogPath"
Write-Log "=============================================="
