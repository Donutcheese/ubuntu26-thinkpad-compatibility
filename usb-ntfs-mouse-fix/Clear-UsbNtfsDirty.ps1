# 仅处理可移动磁盘上的 NTFS；不改注册表、不改系统盘文件。
# 用法（管理员 PowerShell）：
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\Clear-UsbNtfsDirty.ps1
# 可选：注册当前用户登录任务（只加当前用户计划任务）
#   .\Clear-UsbNtfsDirty.ps1 -RegisterTask

param(
  [switch]$RegisterTask
)

function Clear-RemovableNtfsDirty {
  Get-Volume | Where-Object {
    $_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS' -and $_.DriveLetter
  } | ForEach-Object {
    $letter = "$($_.DriveLetter):"
    Write-Host "Clearing dirty on $letter ($($_.FileSystemLabel)) ..."
    & chkdsk $letter /f
  }
}

if ($RegisterTask) {
  $scriptPath = $MyInvocation.MyCommand.Path
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName 'ClearUsbNtfsDirty' -Action $action -Trigger $trigger `
    -Description 'Clear NTFS dirty bit on removable USB drives (current user only)' `
    -User $env:USERNAME | Out-Null
  Write-Host "Registered current-user logon task: ClearUsbNtfsDirty"
}

Clear-RemovableNtfsDirty
