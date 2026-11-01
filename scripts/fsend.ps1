# ============================================================
# fsend.ps1 - stream files to/from a remote host over SFTP
#
# Pure ASCII on purpose: PowerShell 5.1 parses BOM-less files as
# ANSI, so non-ASCII comments/messages would break the parser.
#
# Why this exists: ssh-mcp's streaming sftp tools are hard-rejected
# on Windows (local-path.js: platform() === 'win32'), which leaves
# only an MCP path that puts file CONTENT into the model context.
# This script keeps the bytes in the SSH channel and prints a
# couple of short lines instead.
#
# Usage:
#   fsend <localFile...> <user@host:remotePath>       upload
#   fsend -Down <user@host:remotePath> <localDir>     download
#   fsend -Verify ...                                 also compare md5
#
# Notes:
#   - BatchMode=yes always: auth failure exits instead of waiting
#     for a password prompt (a hung session is the real cost).
#   - -q kills the progress meter, so output stays a few lines.
#   - Sizes are always cross-checked. md5 only with -Verify,
#     because md5 on multi-GB files runs past the command timeout.
#
# Exit codes: 0 ok, 1 transfer/verify failed, 2 bad usage
# ============================================================
#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Down,
    [switch]$Verify,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgList
)

$ErrorActionPreference = 'Stop'

$script:RemoteTargetPattern = '^[^@\s]+@[^:\s]+:.+$'
$script:SshOptions = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=accept-new')

# Resolve ssh/scp deterministically: the packaged OpenSSH under
# System32 first, PATH second. Avoids picking up a stray copy.
function Get-ToolPath {
    param([string]$Name)
    $sys = Join-Path $env:WINDIR ('System32\OpenSSH\' + $Name + '.exe')
    if (Test-Path -LiteralPath $sys) { return $sys }
    return $Name
}

function Show-Usage {
    Write-Host 'fsend - stream files over SFTP (bytes never enter the model context)'
    Write-Host ''
    Write-Host '  fsend <localFile...> <user@host:remotePath>        upload'
    Write-Host '  fsend -Down <user@host:remotePath> <localDir>      download'
    Write-Host '  fsend -Verify ...                                  also compare md5'
    Write-Host ''
    Write-Host 'examples:'
    Write-Host '  fsend "F:\build\app.war" root@10.0.0.9:/opt/app/'
    Write-Host '  fsend -Down root@10.0.0.9:/var/log/app.log "N:\tmp\"'
}

# Quote a remote path for a shell that ssh runs on the far side.
function ConvertTo-RemoteQuoted {
    param([string]$Path)
    return "'" + ($Path -replace "'", "'\''") + "'"
}

# One ssh round-trip for many paths: sizes in the same order.
# Returns -1 for paths that failed the stat.
function Invoke-RemoteSizes {
    param([string]$RemoteHost, [string[]]$Paths)
    $quoted = @()
    foreach ($p in $Paths) { $quoted += (ConvertTo-RemoteQuoted -Path $p) }
    $cmd = 'stat -c %s ' + ($quoted -join ' ')
    $out = & (Get-ToolPath 'ssh') @script:SshOptions $RemoteHost $cmd 2>&1
    $res = @()
    foreach ($line in $out) {
        $s = ([string]$line).Trim()
        if ($s -match '^\d+$') { $res += [long]$s } else { $res += [long]-1 }
    }
    return $res
}

function Get-RemoteMd5 {
    param([string]$RemoteHost, [string]$Path)
    $cmd = 'md5sum ' + (ConvertTo-RemoteQuoted -Path $Path) + " | cut -d' ' -f1"
    $out = & (Get-ToolPath 'ssh') @script:SshOptions $RemoteHost $cmd 2>&1
    foreach ($line in $out) {
        $s = ([string]$line).Trim()
        if ($s -match '^[0-9a-fA-F]{32}$') { return $s.ToLower() }
    }
    return $null
}

function Get-LocalMd5 {
    param([string]$Path)
    $out = & certutil -hashfile $Path MD5 2>&1
    foreach ($line in $out) {
        $s = ([string]$line).Trim() -replace ' ', ''
        if ($s -match '^[0-9a-fA-F]{32}$') { return $s.ToLower() }
    }
    return $null
}

# Split "user@host:/path" into host and path parts.
function Split-RemoteTarget {
    param([string]$Target)
    $m = [regex]::Match($Target, '^([^@]+@[^:]+):(.*)$')
    return @{ Host = $m.Groups[1].Value; Path = $m.Groups[2].Value }
}

# Join a remote directory and a file name without doubling slashes.
function Join-RemotePath {
    param([string]$Dir, [string]$Leaf)
    $d = $Dir.TrimEnd('/', '\')
    if ([string]::IsNullOrEmpty($d)) { return $Leaf }
    return $d + '/' + $Leaf
}

# Print the first meaningful error line from a failed scp/ssh run.
function Get-FirstErrorLine {
    param($Output)
    foreach ($line in $Output) {
        $s = ([string]$line).Trim()
        if ($s.Length -gt 0) { return $s }
    }
    return 'unknown error'
}

function Invoke-Scp {
    param([string[]]$ScpArgs)
    $out = & (Get-ToolPath 'scp') @ScpArgs 2>&1
    return @{ Code = $LASTEXITCODE; Output = $out }
}

# ---------- argument parsing ----------
if (-not $ArgList -or $ArgList.Count -lt 2) { Show-Usage; exit 2 }

$scpArgs = @('-q') + $script:SshOptions + @('-r')

# ---------- download: remote -> local dir ----------
if ($Down) {
    if ($ArgList.Count -ne 2) {
        Write-Host '[fsend] ERROR: download takes exactly 2 arguments: <user@host:remotePath> <localDir>'
        exit 2
    }
    $remote = $ArgList[0]
    $localDest = $ArgList[1]
    if ($remote -notmatch $script:RemoteTargetPattern) {
        Write-Host '[fsend] ERROR: download source must look like user@host:/remote/path'
        exit 2
    }

    $parts = Split-RemoteTarget -Target $remote
    $run = Invoke-Scp -ScpArgs ($scpArgs + @($remote, $localDest))
    if ($run.Code -ne 0) {
        Write-Host ('[fsend] FAILED down (exit ' + $run.Code + '): ' + (Get-FirstErrorLine -Output $run.Output))
        exit 1
    }

    # Local landing spot: dir + leaf name.
    $leaf = ($parts.Path.TrimEnd('/', '\') -split '/')[-1]
    $localFile = $null
    if (Test-Path -LiteralPath $localDest -PathType Container) {
        $localFile = Join-Path $localDest $leaf
    } elseif (Test-Path -LiteralPath $localDest -PathType Leaf) {
        $localFile = (Resolve-Path -LiteralPath $localDest).ProviderPath
    }
    if (-not $localFile -or -not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        Write-Host ('[fsend] down ok -> ' + $localDest + '  (size check skipped: target path is a directory tree)')
        exit 0
    }

    $localSize = (Get-Item -LiteralPath $localFile).Length
    $remoteSize = @(Invoke-RemoteSizes -RemoteHost $parts.Host -Paths @($parts.Path))[0]
    if ($remoteSize -ge 0 -and $remoteSize -ne $localSize) {
        Write-Host ('[fsend] FAILED down size mismatch: local=' + $localSize + ' remote=' + $remoteSize + ' (' + $localFile + ')')
        exit 1
    }

    $checked = 'size'
    if ($Verify) {
        $lm = Get-LocalMd5 -Path $localFile
        $rm = Get-RemoteMd5 -RemoteHost $parts.Host -Path $parts.Path
        if ($lm -and $rm -and $lm -ne $rm) {
            Write-Host ('[fsend] FAILED down md5 mismatch: local=' + $lm + ' remote=' + $rm)
            exit 1
        }
        if ($lm -and $rm) { $checked = 'md5' }
    }
    Write-Host ('[fsend] down ok ' + $localSize + 'B <- ' + $remote + '  checked=' + $checked)
    exit 0
}

# ---------- upload: local files -> remote target ----------
$target = $ArgList[$ArgList.Count - 1]
$sources = @($ArgList[0..($ArgList.Count - 2)])
if ($target -notmatch $script:RemoteTargetPattern) {
    Write-Host '[fsend] ERROR: last argument must be the remote target user@host:/remote/path'
    exit 2
}
foreach ($f in $sources) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Host ('[fsend] ERROR: local path not found: ' + $f)
        exit 2
    }
}

$parts = Split-RemoteTarget -Target $target
$names = @()
$localSizes = @()
foreach ($f in $sources) {
    $names += (Split-Path -Leaf $f)
    $localSizes += (Get-Item -LiteralPath $f).Length
}

# Remote paths we expect after the transfer. A trailing slash or more
# than one source means the target is a directory.
$isDir = $parts.Path.EndsWith('/') -or $parts.Path.EndsWith('\') -or $sources.Count -gt 1 -or $parts.Path -eq '.' -or $parts.Path -eq ''
$remotePaths = @()
if ($isDir) {
    for ($i = 0; $i -lt $names.Count; $i++) { $remotePaths += (Join-RemotePath -Dir $parts.Path -Leaf $names[$i]) }
} else {
    $remotePaths = @($parts.Path)
}

$run = Invoke-Scp -ScpArgs ($scpArgs + $sources + @($target))
if ($run.Code -ne 0) {
    Write-Host ('[fsend] FAILED up (exit ' + $run.Code + '): ' + (Get-FirstErrorLine -Output $run.Output))
    exit 1
}

$remoteSizes = @(Invoke-RemoteSizes -RemoteHost $parts.Host -Paths $remotePaths)
$total = 0
for ($i = 0; $i -lt $localSizes.Count; $i++) {
    $total += $localSizes[$i]
    $remote = if ($i -lt $remoteSizes.Count) { $remoteSizes[$i] } else { [long]-1 }
    if ($remote -ge 0 -and $remote -ne $localSizes[$i]) {
        Write-Host ('[fsend] FAILED up size mismatch: ' + $names[$i] + ' local=' + $localSizes[$i] + ' remote=' + $remote)
        exit 1
    }
}

$checked = 'size'
if ($Verify -and $sources.Count -eq 1) {
    $lm = Get-LocalMd5 -Path $sources[0]
    $rm = Get-RemoteMd5 -RemoteHost $parts.Host -Path $remotePaths[0]
    if ($lm -and $rm -and $lm -ne $rm) {
        Write-Host ('[fsend] FAILED up md5 mismatch: local=' + $lm + ' remote=' + $rm)
        exit 1
    }
    if ($lm -and $rm) { $checked = 'md5' }
}

Write-Host ('[fsend] up ok ' + $sources.Count + ' file(s) ' + $total + 'B -> ' + $target + '  checked=' + $checked)
exit 0
