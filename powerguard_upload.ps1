<# 
PowerGuardCloud - INTUNE INSTALLER (Creates scheduled task + drops Upload-Transcripts.ps1)
- Drops known-good runner (direct upload, no zip, skip locked)
- Creates scheduled task as SYSTEM
- Schedule controls:
    $TaskRunTime     = "02:15"   # HH:mm (24h)
    $RunIntervalDays = 1         # 1=daily, 2=every 2 days, etc.
- StartWhenAvailable enabled (catch-up if device was off)
- Hardens Upload folder (contains SAS)
- Logs:
    C:\Windows\PowerGuard\Upload\installer.log
    C:\Windows\PowerGuard\Upload\installer.ran
#>

$ErrorActionPreference = 'Stop'

# =========================
# CONFIG (EDIT THESE)
# =========================
$ContainerUrl    = "https://powerguardlogs.blob.core.windows.net/powerguard-ps-transcript"
$SasToken        = '?sv=2024-11-04&ss=bfqt&srt=co&sp=rwdlacupiytfx&se=2026-01-26T21:03:43Z&st=2026-01-12T12:48:43Z&sip=213.8.178.222&spr=https&sig=1JpZCDAD2Fv5nmsl9RyGIfFAVBrxjuCneyqLHpHpMJI%3D'   # <-- paste your container SAS here (must start with '?')  # MUST keep leading '?'

# Schedule controls
$TaskRunTime     = "02:15"   # HH:mm (24-hour)
$RunIntervalDays = 1         # 1=daily, 2=every 2 days, etc.
$RunOnceNow      = $true

# =========================
# PATHS / CONSTANTS
# =========================
$Root         = "C:\Windows\PowerGuard"
$UploadDir    = Join-Path $Root "Upload"
$AzCopyDir    = Join-Path $UploadDir "azcopy"
$AzCopyExe    = Join-Path $AzCopyDir "azcopy.exe"
$TaskName     = "PowerGuard-Upload-PS-Transcripts"
$TaskScript   = Join-Path $UploadDir "Upload-Transcripts.ps1"
$AzCopyZipUrl = "https://aka.ms/downloadazcopy-v10-windows"
$InstallerLog = Join-Path $UploadDir "installer.log"
$InstallerRan = Join-Path $UploadDir "installer.ran"

function Write-InstallerLog([string]$Level, [string]$Message) {
  New-Item -ItemType Directory -Path $UploadDir -Force | Out-Null
  $line = "$(Get-Date -Format o) [$Level] $Message"
  Add-Content -Path $InstallerLog -Value $line -Encoding UTF8
}

# =========================
# VALIDATION
# =========================
if ($SasToken -notmatch '^\?') { throw "SasToken must start with '?'." }
if ($ContainerUrl -notmatch '^https://') { throw "ContainerUrl must start with https://." }
if ($RunIntervalDays -lt 1) { throw "RunIntervalDays must be >= 1." }

try { [void][DateTime]::ParseExact($TaskRunTime, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture) }
catch { throw "TaskRunTime must be HH:mm (24-hour), e.g. 02:15" }

try {
  Write-InstallerLog "INFO" "[Installer] Starting installer. Root=$Root UploadDir=$UploadDir TaskName=$TaskName"
  Write-InstallerLog "INFO" "[Installer] Schedule: RunTime=$TaskRunTime IntervalDays=$RunIntervalDays RunOnceNow=$RunOnceNow"
  Write-InstallerLog "INFO" "[Installer] ContainerUrl=$ContainerUrl (SAS hidden)"

  # Create directories
  New-Item -ItemType Directory -Path $Root -Force | Out-Null
  New-Item -ItemType Directory -Path $UploadDir -Force | Out-Null
  New-Item -ItemType Directory -Path $AzCopyDir -Force | Out-Null

  # Harden Upload folder so standard users can't read scripts/logs containing SAS
  Write-InstallerLog "INFO" "[Installer] Hardening ACL on $UploadDir"
  icacls $UploadDir /inheritance:r | Out-Null
  icacls $UploadDir /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" | Out-Null
  icacls $UploadDir /remove "BUILTIN\Users" 2>$null | Out-Null

  # =========================
  # DROP FIXED RUNNER (NO -WindowStyle)
  # =========================
  Write-InstallerLog "INFO" "[Installer] Writing runner script to $TaskScript"

  $Runner = @"
# ============================================================================
# PowerGuard Upload-Transcripts.ps1 (DIRECT UPLOAD, NO ZIP, SKIP LOCKED)
# ============================================================================
`$ErrorActionPreference = 'Stop'

`$ContainerUrl = '$ContainerUrl'
`$SasToken     = '$SasToken'

`$Root         = '$Root'
`$UploadDir    = '$UploadDir'
`$AzCopyDir    = '$AzCopyDir'
`$AzCopyExe    = '$AzCopyExe'
`$LogFile      = Join-Path `$UploadDir 'upload.log'
`$AzCopyZipUrl = '$AzCopyZipUrl'

function Write-Log([string]`$Level, [string]`$Category, [string]`$Message) {
  New-Item -ItemType Directory -Path `$UploadDir -Force | Out-Null
  `$line = "`$(Get-Date -Format o) [`$Level] [`$Category] `$Message"
  Add-Content -Path `$LogFile -Value `$line -Encoding UTF8
}

function Test-FileNotLocked([string]`$Path) {
  try {
    `$fs = [System.IO.File]::Open(`$Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    `$fs.Close()
    return `$true
  } catch {
    return `$false
  }
}

function Ensure-AzCopy {
  if (Test-Path `$AzCopyExe) {
    Write-Log 'INFO' 'AzCopy' "AzCopy present: `$AzCopyExe"
    return
  }

  Write-Log 'WARN' 'AzCopy' "AzCopy missing. Installing to: `$AzCopyExe"
  New-Item -ItemType Directory -Path `$AzCopyDir -Force | Out-Null

  `$installId = (Get-Date -Format 'yyyyMMdd-HHmmss')
  `$instDir   = Join-Path `$UploadDir "azcopy-install-`$installId"
  New-Item -ItemType Directory -Path `$instDir -Force | Out-Null

  `$zipPath = Join-Path `$instDir 'azcopy.zip'

  Write-Log 'INFO' 'AzCopy' "Downloading AzCopy from: `$AzCopyZipUrl"
  Invoke-WebRequest -Uri `$AzCopyZipUrl -OutFile `$zipPath -UseBasicParsing

  Write-Log 'INFO' 'AzCopy' "Extracting: `$zipPath"
  `$extractDir = Join-Path `$instDir 'extract'
  New-Item -ItemType Directory -Path `$extractDir -Force | Out-Null
  Expand-Archive -Path `$zipPath -DestinationPath `$extractDir -Force

  `$found = Get-ChildItem -Path `$extractDir -Recurse -Filter 'azcopy.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not `$found) {
    Write-Log 'ERROR' 'AzCopy' "Install failed: azcopy.exe not found after extraction. Check: `$extractDir"
    throw "AzCopy install failed: azcopy.exe not found after extraction."
  }

  Copy-Item -Path `$found.FullName -Destination `$AzCopyExe -Force
  if (-not (Test-Path `$AzCopyExe)) {
    throw "AzCopy install verification failed: `$AzCopyExe not found after copy."
  }
  Write-Log 'INFO' 'AzCopy' "AzCopy installed: `$AzCopyExe"
}

try {
  New-Item -ItemType Directory -Path `$UploadDir -Force | Out-Null
  Write-Log 'INFO' 'Startup' "Script start. Root=`$Root UploadDir=`$UploadDir"
  Write-Log 'INFO' 'Startup' "ContainerUrl=`$ContainerUrl (SAS hidden)"
  Write-Log 'INFO' 'Startup' "AzCopyExe=`$AzCopyExe"

  Ensure-AzCopy

  `$hostname = `$env:COMPUTERNAME
  `$cutoff   = (Get-Date).AddHours(-48)

  Write-Log 'INFO' 'Selection' "Selecting files modified since: `$(`$cutoff.ToString('o')) (last 48 hours)"
  Write-Log 'INFO' 'Selection' "Scope: `$Root (recursive), exclude: `$UploadDir"
  Write-Log 'INFO' 'Selection' "Filter: PowerShell_transcript*.txt"

  `$candidates = Get-ChildItem -Path `$Root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
      `$_.FullName -notlike "`$UploadDir\*" -and
      `$_.Name -like "PowerShell_transcript*.txt" -and
      `$_.LastWriteTime -ge `$cutoff
    } | Sort-Object LastWriteTime

  `$candCount = @(`$candidates).Count
  Write-Log 'INFO' 'Selection' "Candidates found: `$candCount"
  if (`$candCount -eq 0) { Write-Log 'INFO' 'Selection' "None found. Exiting."; exit 0 }

  `$runId    = (Get-Date -Format 'yyyyMMdd-HHmmss')
  `$azRunDir = Join-Path `$UploadDir "azcopy-direct-`$runId"
  New-Item -ItemType Directory -Path `$azRunDir -Force | Out-Null

  `$env:AZCOPY_LOG_LOCATION      = `$azRunDir
  `$env:AZCOPY_JOB_PLAN_LOCATION = `$azRunDir
  `$env:AZCOPY_LOG_LEVEL         = "INFO"
  `$env:AZCOPY_SILENT_MODE       = "true"
  `$env:AZCOPY_DISABLE_SYSLOG    = "true"

  Write-Log 'INFO' 'AzCopy' "AzCopy internal logs: `$azRunDir"
  Write-Log 'INFO' 'AzCopy' "AzCopy env: SILENT_MODE=true LOG_LEVEL=INFO"

  `$pv = Start-Process -FilePath `$AzCopyExe -ArgumentList @("version") -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path `$azRunDir "azcopy-version-stdout.log") -RedirectStandardError  (Join-Path `$azRunDir "azcopy-version-stderr.log")

  Write-Log 'INFO' 'AzCopy' "AzCopy version exit code: `$(`$pv.ExitCode)"

  `$uploaded = 0
  `$skippedLocked = 0
  `$failed = 0

  foreach (`$f in `$candidates) {
    `$src = `$f.FullName
    Write-Log 'INFO' 'File' "Consider: `$src | LastWrite=`$(`$f.LastWriteTime.ToString('o')) | Size=`$(`$f.Length)"

    if (-not (Test-FileNotLocked `$src)) {
      `$skippedLocked++
      Write-Log 'WARN' 'File' "SKIP (locked/in-use): `$src"
      continue
    }

    `$dateFolder = `$f.LastWriteTime.ToString('yyyyMMdd')
    `$destBlob   = "`$hostname/`$dateFolder/`$(`$f.Name)"
    `$dest       = "`$ContainerUrl/`$destBlob`$SasToken"

    `$safeName = (`$f.Name -replace '[^a-zA-Z0-9\.\-_]+','_')
    `$stdout = Join-Path `$azRunDir "stdout-`$safeName.log"
    `$stderr = Join-Path `$azRunDir "stderr-`$safeName.log"

    Write-Log 'INFO' 'Upload' "UPLOAD start -> DestBlob=`$destBlob"

    `$argList = @('copy', `$src, `$dest, '--overwrite=true', '--log-level=INFO', '--output-type=text')

    `$p = Start-Process -FilePath `$AzCopyExe -ArgumentList `$argList -Wait -PassThru -NoNewWindow -RedirectStandardOutput `$stdout -RedirectStandardError `$stderr

    Write-Log 'INFO' 'Upload' "AzCopy exit code: `$(`$p.ExitCode) for file: `$src"

    if (`$p.ExitCode -eq 0) {
      `$uploaded++
      Write-Log 'INFO' 'Upload' "SUCCESS: `$src -> `$destBlob"
    } else {
      `$failed++
      `$stderrTail = ""
      if (Test-Path `$stderr) { `$stderrTail = ((Get-Content `$stderr -Tail 120) -join "`n") }
      Write-Log 'ERROR' 'Upload' "FAIL: `$src -> `$destBlob"
      if (`$stderrTail) { Write-Log 'ERROR' 'Upload' "stderr tail:`n`$stderrTail" }
    }
  }

  Write-Log 'INFO' 'Summary' "Run complete. Uploaded=`$uploaded Failed=`$failed SkippedLocked=`$skippedLocked Candidates=`$candCount"
  Write-Log 'INFO' 'Summary' "AzCopy diagnostics: `$azRunDir"
}
catch {
  Write-Log 'ERROR' 'Exception' `$_.Exception.Message
  throw
}
"@

  Set-Content -Path $TaskScript -Value $Runner -Encoding UTF8 -Force

  # Lock runner (contains SAS)
  icacls $TaskScript /inheritance:r | Out-Null
  icacls $TaskScript /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" | Out-Null
  icacls $TaskScript /remove "BUILTIN\Users" 2>$null | Out-Null

  # =========================
  # CREATE / UPDATE SCHEDULED TASK
  # =========================
  Write-InstallerLog "INFO" "[Installer] Creating scheduled task via ScheduledTasks module (no schtasks.exe)"

  try {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
      Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
      Write-InstallerLog "INFO" "[Installer] Existing task removed."
    }
  } catch {
    Write-InstallerLog "WARN" "[Installer] Best-effort remove failed: $($_.Exception.Message)"
  }

  $action    = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TaskScript`""
  $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

  $trigger = $null
  try {
    $trigger = New-ScheduledTaskTrigger -Daily -At $TaskRunTime -DaysInterval $RunIntervalDays
    Write-InstallerLog "INFO" "[Installer] Trigger created: Daily @ $TaskRunTime, DaysInterval=$RunIntervalDays"
  } catch {
    $trigger = New-ScheduledTaskTrigger -Daily -At $TaskRunTime
    Write-InstallerLog "WARN" "[Installer] DaysInterval unsupported; using Daily only. Details: $($_.Exception.Message)"
  }

  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 60)

  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
  Write-InstallerLog "INFO" "[Installer] Task registered: $TaskName"

  if ($RunOnceNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-InstallerLog "INFO" "[Installer] Task started immediately for validation."
  }

  Set-Content -Path $InstallerRan -Value ("OK " + (Get-Date -Format o)) -Encoding ASCII -Force
  Write-InstallerLog "INFO" "[Installer] Installer completed successfully."
}
catch {
  Write-InstallerLog "ERROR" ("[Installer] FAILED: " + $_.Exception.Message)
  throw
}
