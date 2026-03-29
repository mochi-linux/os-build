# MochiOS Build System - Windows WSL Launcher
# Runs the MochiOS build pipeline inside Windows Subsystem for Linux.
#
# Usage:
#   .\buildworld-wsl.ps1                        # Full build (all steps)
#   .\buildworld-wsl.ps1 -Command fetch         # Download sources only
#   .\buildworld-wsl.ps1 -Command host          # Host toolchain only
#   .\buildworld-wsl.ps1 -Command host -Step gcc1
#   .\buildworld-wsl.ps1 -Command chroot -Step system
#   .\buildworld-wsl.ps1 -Command image
#   .\buildworld-wsl.ps1 -Command shell         # Interactive chroot shell
#   .\buildworld-wsl.ps1 -Distro Ubuntu-22.04 -Jobs 8 -Command all

param(
    [string]$Command   = "all",
    [string]$Step      = "",
    [string]$Distro    = "",
    [string]$BuildRoot = "",
    [int]$Jobs         = 0,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Log  { param([string]$M) Write-Host "[WSL] $(Get-Date -f HH:mm:ss)  $M" -ForegroundColor Cyan }
function Write-Warn { param([string]$M) Write-Host "[WSL] WARN: $M" -ForegroundColor Yellow }
function Write-Err  { param([string]$M) Write-Host "[WSL] ERROR: $M" -ForegroundColor Red }
function Abort      { param([string]$M) Write-Err $M; exit 1 }

if ($Help) {
    Write-Host @"
MochiOS Build System - WSL Launcher

Usage: .\buildworld-wsl.ps1 [OPTIONS]

Options:
  -Command <cmd>    Build command (default: all)
                    fetch | rootfs | host | chroot | image | shell | clean | all
  -Step <step>      Sub-step for host/chroot commands
                    host   : headers | binutils | gcc1 | glibc | gcc2
                    chroot : bash | coreutils | system | kernel | grub
  -Distro <name>    WSL distro name (default: system default)
  -BuildRoot <path> Build directory inside WSL (default: /mnt/mochi-build)
  -Jobs <n>         Parallel build jobs (default: logical CPU count)
  -Help             Show this help

Examples:
  .\buildworld-wsl.ps1                              # Full build
  .\buildworld-wsl.ps1 -Command fetch               # Download sources
  .\buildworld-wsl.ps1 -Command host                # Build cross toolchain
  .\buildworld-wsl.ps1 -Command host -Step gcc1     # GCC stage 1 only
  .\buildworld-wsl.ps1 -Command chroot -Step system # System utils only
  .\buildworld-wsl.ps1 -Jobs 8 -Command all         # Full build, 8 jobs
"@
    exit 0
}

# ---------------------------------------------------------------------------
# Check WSL availability
# ---------------------------------------------------------------------------
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Abort "WSL is not installed or not in PATH. Run: wsl --install"
}

$wslVersion = (wsl --status 2>&1 | Select-String "Default Version") -replace ".*:\s*", ""
Write-Log "WSL available  (version hint: $wslVersion)"

# ---------------------------------------------------------------------------
# Resolve distro flag
# ---------------------------------------------------------------------------
$DistroArgs = @()
if ($Distro) { $DistroArgs = @("-d", $Distro) }

# ---------------------------------------------------------------------------
# Convert the Windows script directory to a WSL path
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptDirWsl = (wsl @DistroArgs wslpath -a ($ScriptDir -replace "\\", "/") 2>$null)
if (-not $ScriptDirWsl) {
    # Fallback manual conversion: C:\foo\bar → /mnt/c/foo/bar
    $ScriptDirWsl = "/" + ($ScriptDir -replace "^([A-Za-z]):\\", { "mnt/$($_.Groups[1].Value.ToLower())/" } `
                                      -replace "\\", "/")
}
$ScriptDirWsl = $ScriptDirWsl.Trim()

# Default BuildRoot = <project>/buildfs (same convention as buildworld.sh)
if (-not $BuildRoot) { $BuildRoot = "$ScriptDirWsl/buildfs" }

Write-Log "Project path   : $ScriptDir"
Write-Log "WSL path       : $ScriptDirWsl"

# ---------------------------------------------------------------------------
# Determine job count
# ---------------------------------------------------------------------------
if ($Jobs -le 0) {
    $Jobs = (Get-CimInstance Win32_Processor |
             Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $Jobs = [Math]::Max(1, $Jobs)
}

# ---------------------------------------------------------------------------
# Commands that require root inside WSL
# ---------------------------------------------------------------------------
$RootRequired = @("all", "chroot", "image", "shell", "distclean")
$NeedsRoot    = ($RootRequired -contains $Command) -or ($Command -eq "chroot")

# ---------------------------------------------------------------------------
# Build the shell invocation
# ---------------------------------------------------------------------------
$CmdLine = "bash buildworld.sh $Command"
if ($Step) { $CmdLine += " $Step" }

$ShellScript = @"
set -euo pipefail
export MOCHI_BUILD='$BuildRoot'
export MOCHI_SOURCES='$BuildRoot/sources'
export MOCHI_SYSROOT='$BuildRoot/sysroot'
export MOCHI_ROOTFS='$BuildRoot/rootfs'
export MOCHI_CROSS='$BuildRoot/cross'
export MOCHI_TARGET='x86_64-mochios-linux-gnu'
export MOCHI_IMAGE='$BuildRoot/mochios.img'
export JOBS=$Jobs
cd '$ScriptDirWsl'
chmod +x buildworld.sh \
         scripts/host/buildsource.sh \
         scripts/host/createimage.sh \
         scripts/chroot/buildsource.sh
$CmdLine
"@

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
Write-Log "Build command  : $Command$(if ($Step) { " $Step" })"
Write-Log "Build root     : $BuildRoot"
Write-Log "Jobs           : $Jobs"
Write-Log "Needs root     : $NeedsRoot"
Write-Host ""

if ($NeedsRoot) {
    Write-Log "Launching with sudo (chroot/image operations require root) ..."
    wsl @DistroArgs sudo bash -c $ShellScript
} else {
    Write-Log "Launching ..."
    wsl @DistroArgs bash -c $ShellScript
}

$exit = $LASTEXITCODE
if ($exit -ne 0) {
    Write-Err "Build failed with exit code $exit"
    exit $exit
}

Write-Log "==> Build complete"
