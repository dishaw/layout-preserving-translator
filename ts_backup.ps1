# =========================================================
# TS Odoo Translate Docker Backup Script
# Creates one all-in-one 7z archive for the odoo-trans project.
# =========================================================

[CmdletBinding()]
param(
    [string]$ProjectRoot   = "D:\odoo-trans",
    [string]$BackupRoot    = "D:\odoo-trans-backups",
    [string]$LocalTemp     = "D:\Odoo_Trans_Temp_Backup",
    [string]$OdooContainer = "odoo_trans_web",
    [string]$DbContainer   = "odoo_trans_db",
    [string]$DbName        = "odoo-translate",
    [string]$DbUser        = "odoo",
    [string]$DbPass        = "odoo",
    [int]$RetentionDays    = 0
)

$ErrorActionPreference = "Stop"

$Date         = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupName   = "ts_backup_$Date"
$StageRoot    = Join-Path $LocalTemp $BackupName
$ProjectStage = Join-Path $StageRoot "project"
$DbStage      = Join-Path $StageRoot "db"
$FsStage      = Join-Path $StageRoot "filestore"
$SqlFile      = Join-Path $DbStage "$DbName.sql"
$FsFile       = Join-Path $FsStage "filestore.tar.gz"
$MetadataFile = Join-Path $StageRoot "metadata.txt"
$ChecksumFile = Join-Path $StageRoot "checksums.sha256"
$LogFile      = Join-Path $StageRoot "backup_log_$Date.txt"
$ArchiveFile  = Join-Path $BackupRoot "$BackupName.7z"
$ArchiveHash  = "$ArchiveFile.sha256"
$ExcludeDirs   = @(".git", ".waylog", "__pycache__")
$ExcludeFiles  = @("*.log", "*.pyc", "ts_backup_*.7z", "Task_Error_Log.txt")

function Get-7Zip {
    $default7z = "C:\Program Files\7-Zip\7z.exe"
    if (Test-Path $default7z) {
        return $default7z
    }

    $cmd = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "7-Zip was not found. Install 7-Zip or add 7z.exe to PATH."
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-CmdChecked {
    param(
        [string]$CommandLine,
        [string]$Description
    )

    Write-Host $Description -ForegroundColor Cyan
    cmd /c $CommandLine
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Add-MetadataLine {
    param([string]$Line)
    Add-Content -LiteralPath $MetadataFile -Value $Line -Encoding UTF8
}

$ZipExe = Get-7Zip
Require-Command "docker"
Require-Command "robocopy"

New-Item -ItemType Directory -Force -Path $LocalTemp, $BackupRoot | Out-Null
if (Test-Path $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ProjectStage, $DbStage, $FsStage | Out-Null

$transcriptStarted = $false
try {
    Start-Transcript -Path $LogFile -Append | Out-Null
    $transcriptStarted = $true

    Write-Host "=== TS backup started: $Date ===" -ForegroundColor Green
    Write-Host "Project root : $ProjectRoot"
    Write-Host "Backup file  : $ArchiveFile"
    Write-Host "Database     : $DbName"

    if (-not (Test-Path $ProjectRoot)) {
        throw "Project root does not exist: $ProjectRoot"
    }

    Write-Host "[1/7] Checking Docker containers..." -ForegroundColor Cyan
    docker inspect $OdooContainer | Out-Null
    docker inspect $DbContainer | Out-Null

    Write-Host "[2/7] Writing metadata..." -ForegroundColor Cyan
    Set-Content -LiteralPath $MetadataFile -Value "TS Odoo Translate Backup - $Date" -Encoding UTF8
    Add-MetadataLine "ProjectRoot: $ProjectRoot"
    Add-MetadataLine "Database: $DbName"
    Add-MetadataLine "OdooContainer: $OdooContainer"
    Add-MetadataLine "DbContainer: $DbContainer"
    Add-MetadataLine "Host: $env:COMPUTERNAME"
    Add-MetadataLine "CreatedAt: $(Get-Date -Format o)"

    try {
        $odooImageId = docker inspect --format='{{.Image}}' $OdooContainer
        $dbImageId = docker inspect --format='{{.Image}}' $DbContainer
        Add-MetadataLine "OdooImageId: $odooImageId"
        Add-MetadataLine "PostgresImageId: $dbImageId"
        Add-MetadataLine "OdooImageDigest: $(docker image inspect --format='{{index .RepoDigests 0}}' $odooImageId 2>$null)"
        Add-MetadataLine "PostgresImageDigest: $(docker image inspect --format='{{index .RepoDigests 0}}' $dbImageId 2>$null)"
    } catch {
        Add-MetadataLine "ImageMetadataWarning: $($_.Exception.Message)"
    }

    Write-Host "[3/7] Exporting database $DbName..." -ForegroundColor Cyan
    $dumpCmd = "docker exec -i -e PGPASSWORD=$DbPass $DbContainer pg_dump -U $DbUser -d `"$DbName`" --clean --if-exists --create --no-owner --no-privileges > `"$SqlFile`""
    Invoke-CmdChecked -CommandLine $dumpCmd -Description "Database dump"

    Write-Host "[4/7] Exporting Odoo filestore..." -ForegroundColor Cyan
    $tarCmd = "docker exec $OdooContainer bash -lc `"if [ -d '/var/lib/odoo/filestore' ]; then tar -czf - -C /var/lib/odoo filestore; else tar -czf - --files-from /dev/null; fi`" > `"$FsFile`""
    Invoke-CmdChecked -CommandLine $tarCmd -Description "Filestore archive"

    Write-Host "[5/7] Copying project files..." -ForegroundColor Cyan
    Write-Host "Excluding dirs : $($ExcludeDirs -join ', ')" -ForegroundColor DarkGray
    Write-Host "Excluding files: $($ExcludeFiles -join ', ')" -ForegroundColor DarkGray
    $robocopyArgs = @(
        $ProjectRoot,
        $ProjectStage,
        "/E",
        "/XD"
    ) + $ExcludeDirs + @(
        "/XF"
    ) + $ExcludeFiles + @(
        "/R:2",
        "/W:2",
        "/NFL",
        "/NDL"
    )
    & robocopy @robocopyArgs | Out-Host
    $robocopyCode = $LASTEXITCODE
    if ($robocopyCode -gt 7) {
        throw "Robocopy failed with exit code $robocopyCode"
    }

    Write-Host "[6/7] Calculating package checksums..." -ForegroundColor Cyan
    "SHA256 checksums for files inside this backup:" | Set-Content -LiteralPath $ChecksumFile -Encoding UTF8
    "Note: the live transcript log is excluded from this internal checksum list because Windows keeps it locked while the backup is running." | Add-Content -LiteralPath $ChecksumFile -Encoding UTF8
    Get-ChildItem -LiteralPath $StageRoot -File -Recurse |
        Where-Object { $_.FullName -ne $ChecksumFile -and $_.FullName -ne $LogFile } |
        Sort-Object FullName |
        ForEach-Object {
            $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            $relative = $_.FullName.Substring($StageRoot.Length + 1).Replace("\", "/")
            Add-Content -LiteralPath $ChecksumFile -Value "$($hash.Hash)  $relative" -Encoding UTF8
        }

    Stop-Transcript | Out-Null
    $transcriptStarted = $false

    Write-Host "[7/7] Creating final archive..." -ForegroundColor Cyan
    if (Test-Path $ArchiveFile) {
        Remove-Item -LiteralPath $ArchiveFile -Force
    }
    & $ZipExe a $ArchiveFile "$StageRoot\*" -t7z -mx9 -mmt=on "-xr!.git" "-xr!.waylog" "-xr!__pycache__" "-xr!*.pyc" "-xr!*.log"
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed with exit code $LASTEXITCODE"
    }

    $finalHash = Get-FileHash -LiteralPath $ArchiveFile -Algorithm SHA256
    "$($finalHash.Hash)  $(Split-Path $ArchiveFile -Leaf)" | Set-Content -LiteralPath $ArchiveHash -Encoding UTF8

    if ($RetentionDays -gt 0) {
        Write-Host "Cleaning backups older than $RetentionDays days in $BackupRoot..." -ForegroundColor Cyan
        $limitDate = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -LiteralPath $BackupRoot -File -Filter "ts_backup_*.7z" |
            Where-Object { $_.LastWriteTime -lt $limitDate } |
            Remove-Item -Force
    }

    Remove-Item -LiteralPath $StageRoot -Recurse -Force

    Write-Host "=== Backup completed successfully ===" -ForegroundColor Green
    Write-Host "Archive : $ArchiveFile"
    Write-Host "SHA256  : $($finalHash.Hash)"
} catch {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
    Write-Host "=== Backup failed ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Stage folder kept for inspection: $StageRoot" -ForegroundColor Yellow
    exit 1
}
