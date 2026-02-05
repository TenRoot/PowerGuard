<# PowerGuard - Secure PS Transcription Folder
Hardens C:\Windows\PowerGuard so standard users can't read/tamper with transcripts or upload secrets.
#>

$Root = "C:\Windows\PowerGuard"

New-Item -ItemType Directory -Path $Root -Force | Out-Null

# Remove inheritance and enforce least privilege
icacls $Root /inheritance:r | Out-Null
icacls $Root /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" | Out-Null

# Remove standard users if present
icacls $Root /remove "BUILTIN\Users" 2>$null | Out-Null

# Optional: ensure the folder isn't accidentally world-readable through other principals
# (Leave as-is for lab unless you have a strict policy to remove additional entries)
