param([switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot "GamePreview.cs") -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Core
[GamePreview]::AlignDpiToGame()
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object GamePreview
$form.BaseDirectory=$PSScriptRoot
if($SelfTest){$form.Dispose();Write-Output 'Preview construction passed; no game input sent.';return}
$mutex=New-Object Threading.Mutex($false,'Local\EpicSevenGamePreview')
$locked=$false
try {
 try {$locked=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$locked=$true}
 if(!$locked){
  $activated=$false
  for($i=0;$i -lt 10;$i++) {
   if([GamePreview]::ActivateExisting()){$activated=$true;break}
   Start-Sleep -Milliseconds 200
  }
  if(!$activated){[Windows.Forms.MessageBox]::Show('预览进程正在启动或退出。请稍后重试；也可在任务栏查找“游戏预览”。','游戏预览') | Out-Null}
  return
 }
 [void]$form.ShowDialog()
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose();$form.Dispose()}