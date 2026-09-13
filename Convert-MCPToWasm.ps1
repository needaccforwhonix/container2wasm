<#
.SYNOPSIS
    Convert MCP Docker Images to WASM
.DESCRIPTION
    Loops through local Docker images matching "ghcr.io/github/github-mcp-server" and "mcp/*"
    and converts them to highly optimized WASM images using container2wasm.
    Saves outputs to ^^wasm/mcp/.
#>

$ErrorActionPreference = "Stop"

if (-not $env:NEXUS_HOME) { $env:NEXUS_HOME = "C:\Users\hello\.gemini" }
$WasmDir = "$env:NEXUS_HOME\^^wasm\mcp"
$C2WExe = "$env:NEXUS_HOME\^tools\container2wasm\c2w.exe"

if (-not (Test-Path $C2WExe)) {
    Write-Error "c2w.exe not found at $C2WExe. Please ensure container2wasm is built."
    exit 1
}

if (-not (Test-Path $WasmDir)) {
    New-Item -ItemType Directory -Path $WasmDir -Force | Out-Null
}

Write-Host "[*] Searching for MCP Docker images..." -ForegroundColor Cyan

# Fetch all docker images
$images = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object {
    $_ -match "^mcp/" -or $_ -match "github-mcp-server"
}

if (-not $images) {
    Write-Host "[!] No MCP images found." -ForegroundColor Yellow
    exit 0
}

Write-Host "[*] Found $($images.Count) MCP images. Beginning conversion..." -ForegroundColor Cyan

foreach ($img in $images) {
    # Extract clean name for the wasm file
    # e.g., mcp/playwright:latest -> playwright
    # ghcr.io/github/github-mcp-server:latest -> github-mcp-server
    $cleanName = $img -replace ":.*", ""
    $cleanName = $cleanName -replace ".*/", ""
    
    $outWasm = Join-Path $WasmDir "$cleanName.wasm"

    if (Test-Path $outWasm) {
        Write-Host "[-] Skipping $img, WASM module already exists: $outWasm" -ForegroundColor DarkGray
        continue
    }

    Write-Host "[+] Converting $img to $outWasm..." -ForegroundColor Green
    
    # Run c2w conversion
    # Note: c2w takes the image name and the output wasm file.
    # It communicates with local docker daemon to pull/export.
    try {
        $proc = Start-Process -FilePath $C2WExe -ArgumentList "$img", "$outWasm" -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Host "    -> Conversion successful!" -ForegroundColor Cyan
            
            # Register in manifest.json
            $manifestPath = "$env:NEXUS_HOME\^^wasm\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            $existing = $manifest.modules | Where-Object { $_.id -eq $cleanName }
            if (-not $existing) {
                $newMod = [PSCustomObject]@{
                    id = $cleanName
                    file = "mcp/$cleanName.wasm"
                    role = "MCP Protocol Server ($cleanName)"
                    source_image = $img
                    container_emulated = $true
                }
                $manifest.modules += $newMod
                $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
                Write-Host "    -> Registered $cleanName in manifest.json" -ForegroundColor Magenta
            }
        } else {
            Write-Host "    -> Conversion failed with ExitCode $($proc.ExitCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host "    -> Exception during conversion: $_" -ForegroundColor Red
    }
}

Write-Host "[*] Batch conversion finished." -ForegroundColor Green
