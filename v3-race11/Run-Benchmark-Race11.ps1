# =============================================================================
# CodX v3 (Race 11) - Benchmark solo
# 50 questions across 5 domains - CodX parallel scoring
# CodX only - no competitor, no external scorer
# Folder: C:\Users\Berkani\Desktop\Benchmark
# =============================================================================

param(
    [string]$CodXBaseUrl     = "https://www.solvatex.com/codx/api/v1",
    [string]$CodXApiKey      = $env:CODX_API_KEY,
    [string]$OutputDir       = "C:\Users\Berkani\Desktop\Benchmark",
    [string]$OutputFile      = "race11_results.csv",
    [int]$StartFromQuestion  = 1,
    [int]$EndAtQuestion      = 50,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CodXVersion    = "v3 Race11"
$BenchmarkDate  = (Get-Date -Format "yyyy-MM-dd")
$OutputPath     = Join-Path $OutputDir $OutputFile
$LogPath        = Join-Path $OutputDir ("race11_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

# =============================================================================
# QUESTIONS
# =============================================================================

$Benchmark = @{
    "Generate Code" = @(
        "Q1  [Easy] Return the first non-repeating character in a string.",
        "Q2  [Easy] Group users by country from a list of dictionaries.",
        "Q3  [Easy] Fetch weather data with error handling.",
        "Q4  [Medium] SQL query for top customers in last 30 days.",
        "Q5  [Medium] Implement a Go worker pool.",
        "Q6  [Medium] Implement an O(1) LRU cache.",
        "Q7  [Hard] Distributed rate limiter using Redis.",
        "Q8  [Hard] Kafka consumer with retries and DLQ.",
        "Q9  [Hard] Trie with autocomplete support.",
        "Q10 [Hard] URL shortener backend API."
    )
    "Security Audit" = @(
        "Q11 [Easy] Identify SQL injection vulnerability.",
        "Q12 [Easy] Find hardcoded secret exposure.",
        "Q13 [Easy] Review weak authentication logic.",
        "Q14 [Medium] Detect path traversal issue.",
        "Q15 [Medium] Detect command injection risk.",
        "Q16 [Medium] Audit JWT validation logic.",
        "Q17 [Hard] Identify SSRF vulnerability.",
        "Q18 [Hard] Audit public cloud storage configuration.",
        "Q19 [Hard] Review unsafe object deserialization.",
        "Q20 [Hard] Full login endpoint security assessment."
    )
    "System Audit" = @(
        "Q21 [Easy] Identify single points of failure.",
        "Q22 [Easy] Audit logging strategy.",
        "Q23 [Easy] Evaluate backup frequency.",
        "Q24 [Medium] Improve microservice resilience.",
        "Q25 [Medium] Audit database scaling approach.",
        "Q26 [Medium] Review CI/CD pipeline gaps.",
        "Q27 [Hard] Kubernetes cluster audit.",
        "Q28 [Hard] Incident response readiness review.",
        "Q29 [Hard] Event-driven architecture audit.",
        "Q30 [Hard] Enterprise architecture modernization."
    )
    "Debug & Fix" = @(
        "Q31 [Easy] Fix off-by-one error.",
        "Q32 [Easy] Fix null reference bug.",
        "Q33 [Easy] Fix infinite loop.",
        "Q34 [Medium] Fix async/await bug.",
        "Q35 [Medium] Fix race condition.",
        "Q36 [Medium] Fix database connection leak.",
        "Q37 [Hard] Resolve deadlock.",
        "Q38 [Hard] Fix memory leak.",
        "Q39 [Hard] Investigate CrashLoopBackOff.",
        "Q40 [Hard] Analyze production outage."
    )
    "Code Review" = @(
        "Q41 [Easy] Improve readability.",
        "Q42 [Easy] Remove duplicate logic.",
        "Q43 [Easy] Improve error handling.",
        "Q44 [Medium] Optimize performance.",
        "Q45 [Medium] Review resource management.",
        "Q46 [Medium] Improve API design.",
        "Q47 [Hard] Review database scalability.",
        "Q48 [Hard] Review XSS vulnerability.",
        "Q49 [Hard] Review concurrent access bug.",
        "Q50 [Hard] Full service review."
    )
}

# =============================================================================
# DOMAIN -> ENDPOINT ROUTING
# =============================================================================

$DomainConfig = @{
    "Generate Code" = @{
        Endpoint    = "/generate"
        AnswerField = "final_output"
        Models      = "CodX parallel scoring"
    }
    "Security Audit" = @{
        Endpoint    = "/audit/security"
        AnswerField = "audit_report"
        Models      = "CodX parallel scoring"
    }
    "System Audit" = @{
        Endpoint    = "/audit/system"
        AnswerField = "audit_report"
        Models      = "CodX parallel scoring"
    }
    "Debug & Fix" = @{
        Endpoint    = "/debug"
        AnswerField = "fix_report"
        Models      = "CodX parallel scoring"
    }
    "Code Review" = @{
        Endpoint    = "/review"
        AnswerField = "review_report"
        Models      = "CodX parallel scoring"
    }
}

# =============================================================================
# BUILD FLAT $Questions LIST
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

# =============================================================================
# MAIN
# =============================================================================

Write-Log "=============================================="
Write-Log " CodX $CodXVersion - Solo Benchmark"
Write-Log " 50 questions - 5 domains"
Write-Log " Architecture: CodX parallel scoring"
Write-Log "=============================================="
Write-Log "Output : $OutputPath"
Write-Log "Range  : Q$StartFromQuestion to Q$EndAtQuestion"
if ($DryRun) { Write-Log "MODE   : DRY RUN" "WARN" }

if (-not $DryRun -and -not $CodXApiKey) {
    Write-Log "Missing env var: CODX_API_KEY" "ERROR"
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $OutputPath)) {
    "test_id,domain,level,prompt_summary,quality_score,time_s,cost_usd,date" |
        Out-File -FilePath $OutputPath -Encoding UTF8
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
$totalCost = 0.0
$totalTime = 0.0
$failures  = 0

foreach ($q in $toRun) {
    $done++
    $pct = [math]::Round(($done / $toRun.Count) * 100)
    $cfg = $DomainConfig[$q.Domain]

    Write-Log "------------------------------------------"
    Write-Log "[$done/$($toRun.Count)] $($q.Id) - $($q.Domain) - $($q.Level)"
    Write-Log "  Q: $($q.Text)"
    Write-Log "  Endpoint: $($cfg.Endpoint)"
    Write-Log "  Models  : $($cfg.Models)"

    if ($DryRun) { Write-Log "  [DRY RUN] Skipping" "WARN"; continue }

    $url = $CodXBaseUrl + $cfg.Endpoint
    $start = Get-Date

    try {
        if ($cfg.Endpoint -like "*/audit/*") {
            $body = @{ code = $q.Text; language = "auto" } | ConvertTo-Json
        } else {
            $body = @{ prompt = $q.Text; language = "auto" } | ConvertTo-Json
        }

        $resp = Invoke-RestMethod -Uri $url -Method POST -TimeoutSec 120 `
            -Headers @{ "Content-Type" = "application/json"; "X-API-Key" = $CodXApiKey } `
            -Body $body

        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
        $cost    = [math]::Round($resp.total_cost_usd, 6)
        $quality = $resp.quality_score
        Write-Log "  OK: ${elapsed}s | cost: `$$cost | quality: $quality" "OK"

        $totalCost += $cost
        $totalTime += $elapsed

        $summary = ($q.Text.Substring(0, [math]::Min(55, $q.Text.Length))) -replace ',',';'
        $row = "$($q.Id),$($q.Domain),$($q.Level),$summary,$quality,$elapsed,$cost,$BenchmarkDate"
        Add-Content -Path $OutputPath -Value $row -Encoding UTF8

    } catch {
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
        Write-Log "  FAILED ${elapsed}s: $_" "ERROR"
        $failures++

        $summary = ($q.Text.Substring(0, [math]::Min(55, $q.Text.Length))) -replace ',',';'
        $row = "$($q.Id),$($q.Domain),$($q.Level),$summary,0,${elapsed},0,error,$BenchmarkDate"
        Add-Content -Path $OutputPath -Value $row -Encoding UTF8
    }

    Start-Sleep -Seconds 2
}

$avgTime = if ($done -gt 0) { [math]::Round($totalTime / $done, 2) } else { 0 }

Write-Log "=============================================="
Write-Log " BENCHMARK COMPLETE - CodX $CodXVersion"
Write-Log "=============================================="
Write-Log " Questions : $done"
Write-Log " Failures  : $failures"
Write-Log " Total cost: `$$([math]::Round($totalCost, 4))"
Write-Log " Total time: ${totalTime}s"
Write-Log " Avg time  : ${avgTime}s per question"
Write-Log "----------------------------------------------"
Write-Log " Results: $OutputPath"
Write-Log " Log    : $LogPath"
Write-Log "=============================================="
