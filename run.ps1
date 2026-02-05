using namespace System.Net

# ---------------------------------------------------
# INPUT BINDINGS
# ---------------------------------------------------
param($InputBlob, $CriticalKeywordsBlob, $WarningKeywordsBlob, $TriggerMetadata)

# --- CONFIGURATION ---
# PASTE YOUR TEAMS WORKFLOW URL HERE
$WebhookUrl = "https://YOUR-NEW-WORKFLOW-URL.logic.azure.com/..." 

# --- STEP 0: FIX RAW BYTE INPUT ---
# Converts Azure Byte Array input to String if necessary
if ($InputBlob -is [byte[]]) {
    Write-Host "DEBUG: Input detected as Byte Array. Converting to String..."
    $InputBlob = [System.Text.Encoding]::UTF8.GetString($InputBlob)
}

# --- HELPER: Parse Lists ---
function Get-KeywordList {
    param ($RawContent)
    if (-not $RawContent) { return @() }
    if ($RawContent -is [byte[]]) { $RawContent = [System.Text.Encoding]::UTF8.GetString($RawContent) }
    return $RawContent -split "\r?\n" | Where-Object { $_ -match "\S" } | ForEach-Object { $_.Trim() }
}

$CriticalList = Get-KeywordList -RawContent $CriticalKeywordsBlob
$WarningList  = Get-KeywordList -RawContent $WarningKeywordsBlob
$FileName = $TriggerMetadata.Name

Write-Host "Create Event Triggered: Processing $FileName"

# --- STEP 1: PARSE TRANSCRIPT HEADER ---
if (-not $InputBlob) { Write-Host "File was empty. Skipping."; return }

$Lines = $InputBlob -split "\r?\n"
$Context = @{ User = "Unknown"; RunAs = "Unknown"; Machine = "Unknown" }

for ($i = 0; $i -lt [Math]::Min($Lines.Count, 20); $i++) {
    if ($Lines[$i] -match "^Username:\s*(.+)")   { $Context.User = $matches[1] }
    if ($Lines[$i] -match "^RunAs User:\s*(.+)") { $Context.RunAs = $matches[1] }
    if ($Lines[$i] -match "^Machine:\s*(.+)")    { $Context.Machine = $matches[1] }
}

# --- STEP 2: SCAN CONTENT ---
$Alerts = @()

for ($i = 0; $i -lt $Lines.Count; $i++) {
    $CurrentLine = $Lines[$i]
    
    # Check Critical
    foreach ($Key in $CriticalList) {
        if ($CurrentLine -match [regex]::Escape($Key)) {
            $Alerts += @{ Type="CRITICAL"; Threat=$Key; FullCommand=$CurrentLine.Trim(); LineNumber=$i+1; Color="Attention" }
        }
    }
    # Check Warning
    foreach ($Key in $WarningList) {
        if ($CurrentLine -match [regex]::Escape($Key)) {
             $Alerts += @{ Type="WARNING"; Threat=$Key; FullCommand=$CurrentLine.Trim(); LineNumber=$i+1; Color="Warning" }
        }
    }
}

# --- STEP 3: SEND ADAPTIVE CARDS (TEAMS) ---
if ($Alerts.Count -gt 0) {
    Write-Host "Threats detected: $($Alerts.Count). Sending Webhook..."
    
    foreach ($Alert in $Alerts) {
        $AdaptiveCard = @{
            "type" = "message"
            "attachments" = @(
                @{
                    "contentType" = "application/vnd.microsoft.card.adaptive"
                    "content" = @{
                        "type" = "AdaptiveCard"
                        "version" = "1.2"
                        "body" = @(
                            @{
                                "type" = "TextBlock"
                                "text" = "$($Alert.Type) ALERT: $($Alert.Threat)"
                                "weight" = "Bolder"
                                "size" = "Medium"
                                "color" = $Alert.Color
                            },
                            @{
                                "type" = "FactSet"
                                "facts" = @(
                                    @{ "title" = "Machine"; "value" = $Context.Machine },
                                    @{ "title" = "User"; "value" = $Context.User },
                                    @{ "title" = "RunAs"; "value" = $Context.RunAs },
                                    @{ "title" = "Line"; "value" = [string]$Alert.LineNumber }
                                )
                            },
                            @{
                                "type" = "Container"
                                "items" = @(
                                    @{ "type" = "TextBlock"; "text" = "Command Snippet:"; "weight" = "Bolder" },
                                    @{ "type" = "TextBlock"; "text" = $Alert.FullCommand; "fontType" = "Monospace"; "wrap" = $true; "color" = "Accent" }
                                )
                                "style" = "emphasis"
                                "bleed" = $true
                            }
                        )
                        "$schema" = "http://adaptivecards.io/schemas/adaptive-card.json"
                    }
                }
            )
        }

        try {
            Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($AdaptiveCard | ConvertTo-Json -Depth 10) -ContentType 'application/json'
            Write-Host "Notification sent for $($Alert.Threat)"
        }
        catch {
            Write-Error "Failed to send webhook: $_"
        }
    }
} else {
    Write-Host "Scan Clean. No threats found."
}