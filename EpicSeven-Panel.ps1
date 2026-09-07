param([string]$PreviewPath,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$script:startupLog=Join-Path $PSScriptRoot 'panel-data\startup.log'
function Startup-Log([string]$Message) {
 try {
  [IO.Directory]::CreateDirectory((Split-Path $script:startupLog -Parent)) | Out-Null
  [IO.File]::AppendAllText($script:startupLog,((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' PID='+$PID+' '+$Message+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
 } catch {}
}
trap {
 $details=$_ | Out-String
 Startup-Log $details
 try {[Windows.Forms.MessageBox]::Show(('启动失败：'+$_.Exception.Message+[Environment]::NewLine+'错误已保存到 panel-data\startup.log'),'商店助手启动错误') | Out-Null} catch {Write-Host $details}
 break
}
Startup-Log 'Starting panel'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class E7PanelWindow {
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint processId);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h,int command);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetLastActivePopup(IntPtr h);
}
"@
function Show-ExistingPanel {
 for($attempt=0;$attempt -lt 8;$attempt++) {
  $existing=[IntPtr]::Zero
  $instancePath=Join-Path $PSScriptRoot 'panel-data\ui-instance.json'
  if(Test-Path -LiteralPath $instancePath) {
   try {
    $instance=Get-Content -LiteralPath $instancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $candidate=[IntPtr]([long]$instance.Handle)
    $ownerId=[uint32]0
    if([E7PanelWindow]::IsWindow($candidate)) {
     [void][E7PanelWindow]::GetWindowThreadProcessId($candidate,[ref]$ownerId)
     if($ownerId -eq [uint32]$instance.ProcessId) {$existing=$candidate}
    }
   } catch {Startup-Log ('Cannot read previous window identity: '+$_.Exception.Message)}
  }
  if($existing -eq [IntPtr]::Zero) {$existing=[E7PanelWindow]::FindWindow($null,'第七史诗 · 商店助手')}
  if($existing -ne [IntPtr]::Zero) {
   if([E7PanelWindow]::IsIconic($existing)) {[void][E7PanelWindow]::ShowWindowAsync($existing,9)} else {[void][E7PanelWindow]::ShowWindowAsync($existing,5)}
   [void][E7PanelWindow]::SetForegroundWindow($existing)
   $popup=[E7PanelWindow]::GetLastActivePopup($existing)
   if($popup -ne [IntPtr]::Zero -and $popup -ne $existing) {[void][E7PanelWindow]::SetForegroundWindow($popup)}
   return $true
  }
  Start-Sleep -Milliseconds 150
 }
 return $false
}
[Windows.Forms.Application]::EnableVisualStyles()
$script:base=$PSScriptRoot
$script:dataDir=Join-Path $script:base 'panel-data'
$script:sessionRoot=Join-Path $script:dataDir 'sessions'
$script:worker=$null;$script:resizeProcess=$null;$script:currentDir=$null
$script:closing=$false;$script:sessions=@{};$script:lastLog='';$script:preview=[bool]$PreviewPath -or $SelfTest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Quote-Arg([string]$value) {return '"'+$value+'"'}
if(!$script:preview -and !$isAdmin) {
 Startup-Log 'Requesting administrator launch'
 try {Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File '+(Quote-Arg $PSCommandPath)) | Out-Null} catch {[Windows.Forms.MessageBox]::Show('未取得管理员权限，窗口调整和后台操作需要此权限。','第七史诗商店助手') | Out-Null}
 return
}
$script:ownsPanelMutex=$false
if(!$script:preview) {
 if(Show-ExistingPanel) {Startup-Log 'Activated an existing verified panel window';return}
 $script:panelMutex=New-Object Threading.Mutex($false,'Local\EpicSevenShopPanelV2')
 try {$script:ownsPanelMutex=$script:panelMutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$script:ownsPanelMutex=$true}
 Startup-Log ('Panel mutex acquired: '+$script:ownsPanelMutex)
 if(!$script:ownsPanelMutex) {
  if(!(Show-ExistingPanel)) {
   Startup-Log 'Existing instance lock held but window was not found'
   [Windows.Forms.MessageBox]::Show('助手正在启动或退出，请稍等片刻再打开。若旧助手仍在任务栏，请先关闭旧窗口再加载新版。','第七史诗商店助手') | Out-Null
  }
  $script:panelMutex.Dispose()
  return
 }
}
if(!$script:preview) {New-Item -ItemType Directory -Force -Path $script:sessionRoot | Out-Null}
$script:form=New-Object Windows.Forms.Form
$form.Text='第七史诗 · 商店助手'
$form.Add_Shown({
 if(!$script:preview) {
  $identity=[pscustomobject]@{ProcessId=$PID;Handle=$form.Handle.ToInt64();Version=2;Started=(Get-Date -Format o)}
  $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:dataDir 'ui-instance.json') -Encoding UTF8
  Startup-Log ('Window shown: handle='+$form.Handle.ToInt64())
 }
})
$form.ClientSize=New-Object Drawing.Size(900,700)
$form.MinimumSize=New-Object Drawing.Size(916,739)
$form.MaximumSize=New-Object Drawing.Size(916,739)
$form.StartPosition='CenterScreen'
$form.BackColor=[Drawing.ColorTranslator]::FromHtml('#F3F5FA')
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',9)
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::None
function LabelAt($parent,[string]$text,[int]$x,[int]$y,[int]$width,[int]$height,[int]$fontSize=10,[string]$color='#24314A') {
 $c=New-Object Windows.Forms.Label
 $c.Text=$text;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,$height)
 $c.Font=New-Object Drawing.Font('Microsoft YaHei UI',$fontSize)
 $c.ForeColor=[Drawing.ColorTranslator]::FromHtml($color)
 $parent.Controls.Add($c);return $c
}
function ButtonAt($parent,[string]$text,[int]$x,[int]$y,[int]$width,[string]$color='#E5EAF4') {
 $c=New-Object Windows.Forms.Button;$c.Text=$text
 $c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,34)
 $c.FlatStyle='Flat';$c.FlatAppearance.BorderSize=0;$c.BackColor=[Drawing.ColorTranslator]::FromHtml($color)
 $c.Cursor=[Windows.Forms.Cursors]::Hand
 $parent.Controls.Add($c);return $c
}
function PanelAt([int]$x,[int]$y,[int]$width,[int]$height) {
 $c=New-Object Windows.Forms.Panel;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,$height);$c.BackColor=[Drawing.Color]::White
 $form.Controls.Add($c);return $c
}
[void](LabelAt $form '第七史诗 / 商店助手千叶出品必属精品' 24 18 580 36 20)
[void](LabelAt $form '后台刷新 · 只购买圣约书签与神秘奖牌' 26 58 660 25 10 '#6B7890')
$script:statusLabel=LabelAt $form '就绪' 722 27 152 28 11 '#3369D8'
$config=PanelAt 24 94 852 126
[void](LabelAt $config '本轮天空石预算' 18 14 155 24 10)
$script:budgetInput=New-Object Windows.Forms.NumericUpDown
$budgetInput.Location=New-Object Drawing.Point(18,43);$budgetInput.Size=New-Object Drawing.Size(160,28)
$budgetInput.Minimum=3;$budgetInput.Maximum=300000;$budgetInput.Increment=3;$budgetInput.Value=300;$budgetInput.ThousandsSeparator=$true
$config.Controls.Add($budgetInput)
$script:budgetHint=LabelAt $config '最多刷新 100 次' 18 80 240 22 9 '#6B7890'
[void](LabelAt $config '游戏窗口尺寸' 285 14 220 24 10)
$script:resolution=New-Object Windows.Forms.ComboBox
$resolution.DropDownStyle='DropDownList';$resolution.Location=New-Object Drawing.Point(285,43);$resolution.Size=New-Object Drawing.Size(157,28)
[void]$resolution.Items.AddRange(@('640 × 360','800 × 450','960 × 540','1280 × 720','1600 × 900'))
$resolution.SelectedIndex=1;$config.Controls.Add($resolution)
$script:applySize=ButtonAt $config '应用尺寸' 455 40 106
$script:sizeHint=LabelAt $config '保持 16:9；运行中不可更改尺寸' 285 80 300 23 9 '#6B7890'
$script:newButton=ButtonAt $config '新建一轮并开始' 610 18 222 '#3068D8'
$newButton.ForeColor=[Drawing.Color]::White
$script:stopButton=ButtonAt $config '停止（或按住 F8）' 610 64 222 '#FCE6E6'
$stopButton.Enabled=$false
$script:metricValues=@();$script:metricSubs=@()
$titles=@('天空石花费','刷新次数','圣约书签','神秘奖牌')
for($i=0;$i -lt 4;$i++) {
 $card=PanelAt (24+$i*216) 234 204 105
 [void](LabelAt $card $titles[$i] 14 11 178 23 10 '#6B7890')
 $script:metricValues+=LabelAt $card '0' 14 34 180 35 22
 $script:metricSubs+=LabelAt $card '尚未开始' 14 77 180 23 9 '#6B7890'
}
$metricValues[0].Font=New-Object Drawing.Font('Microsoft YaHei UI',16)
$rates=PanelAt 24 350 852 77
$script:bookRate=LabelAt $rates '书签出货率  —' 15 12 238 25 11
$script:mysticRate=LabelAt $rates '神秘出货率  —' 285 12 238 25 11
$script:goldLabel=LabelAt $rates '金币花费  0' 565 12 268 25 11
$script:rateHint=LabelAt $rates '出货率 = 含该商品的完整扫描页数 ÷ 完整扫描页数（含初始页）；不是官方概率。' 15 45 824 22 9 '#6B7890'
$roundPanel=PanelAt 24 438 852 47
$script:roundList=New-Object Windows.Forms.ComboBox
$roundList.Location=New-Object Drawing.Point(12,11);$roundList.Size=New-Object Drawing.Size(432,27);$roundList.DropDownStyle='DropDownList'
$roundPanel.Controls.Add($roundList)
$script:resumeButton=ButtonAt $roundPanel '继续本轮' 460 6 110
$script:openButton=ButtonAt $roundPanel '打开记录' 582 6 110
$script:resumeButton.Enabled=$false;$openButton.Enabled=$false
$script:clearButton=ButtonAt $roundPanel '清空记录' 704 6 132 '#FCE6E6'
$script:logBox=New-Object Windows.Forms.TextBox
$logBox.Multiline=$true;$logBox.ScrollBars=[Windows.Forms.ScrollBars]::Vertical
$logBox.Location=New-Object Drawing.Point(24,497);$logBox.Size=New-Object Drawing.Size(852,145)
$logBox.ReadOnly=$true;$logBox.BorderStyle='None';$logBox.BackColor=[Drawing.ColorTranslator]::FromHtml('#18243A');$logBox.ForeColor=[Drawing.ColorTranslator]::FromHtml('#DAE5F7')
$logBox.Font=New-Object Drawing.Font('Microsoft YaHei UI',9)
$logBox.Text='先打开游戏的秘密商店，再设置预算并开始。启动界面不会自动消费天空石。'
$form.Controls.Add($logBox)
$script:footer=LabelAt $form '游戏保持未最小化。停止会等待当前交易核对完成，重启可继续同一轮。' 26 655 848 32 9 '#6B7890'
$budgetInput.Add_ValueChanged({$budgetHint.Text=('最多刷新 {0:N0} 次；余数 {1} 石不消费' -f [Math]::Floor([double]$budgetInput.Value/3),([int]$budgetInput.Value%3))})
function Read-State {
 if(!$script:currentDir) {return $null}
 $p=Join-Path $script:currentDir 'state.json'
 if(Test-Path -LiteralPath $p) {try {return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)} catch {return $null}}
 return $null
}
function Is-Running {return ($null -ne $script:worker -and !$script:worker.HasExited)}
function Refresh-View {
 $running=Is-Running
 $state=Read-State
 $newButton.Enabled=!$running -and $null -eq $script:resizeProcess
 $budgetInput.Enabled=!$running;$roundList.Enabled=!$running
 $resolution.Enabled=!$running -and $null -eq $script:resizeProcess
 $applySize.Enabled=$resolution.Enabled;$stopButton.Enabled=$running
 $openButton.Enabled=[bool]$script:currentDir
 $clearButton.Enabled=!$running -and $null -eq $script:resizeProcess -and $roundList.Items.Count -gt 0
 $canResume=$false
 if($state) {
  $metricValues[0].Text=('{0:N0} / {1:N0}' -f $state.ReservedSkystones,$state.Budget)

  $metricSubs[0].Text=('剩余 {0:N0} 石' -f ([Math]::Max(0,$state.Budget-$state.ReservedSkystones)))
  $metricValues[1].Text=[string]$state.ConfirmedRefreshes
  $metricSubs[1].Text=('已完整扫描 {0} 页' -f $state.PagesScanned)
  $metricValues[2].Text=('{0} 个' -f ([int]$state.BookPurchases*5))
  $metricSubs[2].Text=('购买 {0} 批，每批 5 个' -f [int]$state.BookPurchases)
  $metricValues[3].Text=('{0} 个' -f ([int]$state.MysticPurchases*50))
  $metricSubs[3].Text=('购买 {0} 批，每批 50 个' -f [int]$state.MysticPurchases)
  $goldLabel.Text=('金币花费  {0:N0}' -f [long]$state.GoldSpent)
  if($state.PagesScanned -gt 0) {
   $bookRate.Text=('书签出货率  {0:P1}（{1}/{2}）' -f ($state.BookHitPages/[double]$state.PagesScanned),$state.BookHitPages,$state.PagesScanned)
   $mysticRate.Text=('神秘出货率  {0:P1}（{1}/{2}）' -f ($state.MysticHitPages/[double]$state.PagesScanned),$state.MysticHitPages,$state.PagesScanned)
  } else {$bookRate.Text='书签出货率  —';$mysticRate.Text='神秘出货率  —'}
  $pending=$state.Phase -in @('PurchasePending','RefreshPending')
  $canResume=!$running -and $null -eq $script:resizeProcess -and !$pending -and ($state.Budget-$state.ReservedSkystones -ge 3)
  if($running) {$statusLabel.Text='运行中';if($pending){$statusLabel.Text='正在核对交易'}}
  elseif($pending) {$statusLabel.Text='交易待核实';$footer.Text='上一笔交易结果不确定，已禁止继续。请保留现场和记录，核实后再处理。'}
  elseif($state.Phase -in @('InsufficientGold','InsufficientSkystones','BalanceUnreadable')) {$statusLabel.Text='资源检查已停止';$footer.Text=$state.StopReason}
  elseif($state.Budget-$state.ReservedSkystones -lt 3) {$statusLabel.Text='本轮预算已完成'}
  else {$statusLabel.Text='已停止 / 可继续'}
  $parts=@()
  foreach($name in @('worker.log','worker-error.log')) {
   $p=Join-Path $script:currentDir $name
   if(Test-Path -LiteralPath $p) {$parts+=@(Get-Content -LiteralPath $p -Tail 45 -Encoding UTF8 -ErrorAction SilentlyContinue)}
  }
  $text=$parts -join [Environment]::NewLine
  if($text -and $text -ne $script:lastLog) {$logBox.Text=$text;$logBox.SelectionStart=$logBox.TextLength;$logBox.ScrollToCaret();$script:lastLog=$text}
 }
 $resumeButton.Enabled=$canResume
}
function Load-Rounds {
 $roundList.Items.Clear();$script:sessions=@{}
 if(Test-Path -LiteralPath $script:sessionRoot) {
  foreach($d in (Get-ChildItem -LiteralPath $script:sessionRoot -Directory | Sort-Object Name -Descending)) {
   if(Test-Path -LiteralPath (Join-Path $d.FullName 'state.json')) {$script:sessions[$d.Name]=$d.FullName;[void]$roundList.Items.Add($d.Name)}
  }
 }
 if($roundList.Items.Count -gt 0) {$roundList.SelectedIndex=0}
}
$roundList.Add_SelectedIndexChanged({if($roundList.SelectedItem){$script:currentDir=$script:sessions[[string]$roundList.SelectedItem];$script:lastLog='';Refresh-View}})
function Start-Worker {
 $state=Read-State
 if(!$state) {throw '找不到本轮预算记录。'}
 if($state.Phase -in @('PurchasePending','RefreshPending')) {throw '上一笔交易尚未核实，不能重试。'}
 $stopPath=Join-Path $script:currentDir 'STOP'
 # Remove only this round's stop marker, never its budget or history.
 if(Test-Path -LiteralPath $stopPath) {Remove-Item -LiteralPath $stopPath}
 $out=Join-Path $script:currentDir 'worker.log';$err=Join-Path $script:currentDir 'worker-error.log'
 if(Test-Path -LiteralPath $out) {Move-Item -LiteralPath $out -Destination (Join-Path $script:currentDir ('worker-'+(Get-Date -Format 'HHmmssfff')+'.log'))}
 if(Test-Path -LiteralPath $err) {Move-Item -LiteralPath $err -Destination (Join-Path $script:currentDir ('error-'+(Get-Date -Format 'HHmmssfff')+'.log'))}
 $run=Join-Path $script:currentDir ('run-'+(Get-Date -Format 'HHmmssfff'))
 $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File '+(Quote-Arg (Join-Path $script:base 'Scan-EpicSeven-Shop.ps1'))+' -AutoBuy -BudgetLimit '+[int]$state.Budget+' -StatePath '+(Quote-Arg (Join-Path $script:currentDir 'state.json'))+' -StopFile '+(Quote-Arg $stopPath)+' -RunOutputPath '+(Quote-Arg $run)
 $script:worker=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 $footer.Text='运行中。按“停止”后会完成当前交易核对再退出；请勿同时运行旧版刷店脚本。'
 $script:lastLog='';Refresh-View
}
$newButton.Add_Click({
 try {
  if(Is-Running) {return}
  $state=Read-State
  if($state -and $state.Phase -in @('PurchasePending','RefreshPending')) {throw '当前轮次交易未核实，请先处理，不能新建轮次绕过。'}
  $id=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
  $script:currentDir=Join-Path $script:sessionRoot $id
  New-Item -ItemType Directory -Path $script:currentDir | Out-Null
  $state=[pscustomobject]@{Budget=[int]$budgetInput.Value;ReservedSkystones=0;ConfirmedRefreshes=0;Phase='Ready';Purchases=0;BoughtThisRefresh=@();LastPurchase=$null;BookPurchases=0;MysticPurchases=0;GoldSpent=0;PagesScanned=0;BookHitPages=0;MysticHitPages=0;LastCountedRefresh=-1;SeenThisRefresh=@()}
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:currentDir 'state.json') -Encoding UTF8
  Load-Rounds
  Start-Worker
 } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法开始') | Out-Null}
})
$resumeButton.Add_Click({try {Start-Worker} catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法继续') | Out-Null}})
function Get-ClearTargets([string]$Root) {
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')
 if(!(Test-Path -LiteralPath $rootPath)) {return}
 $rootItem=Get-Item -LiteralPath $rootPath
 if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {throw '记录目录不能是链接。'}
 foreach($dir in (Get-ChildItem -LiteralPath $rootPath -Directory)) {
  $resolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $dir.FullName).Path)
  if(!(Split-Path $resolved -Parent).Equals($rootPath,[StringComparison]::OrdinalIgnoreCase)) {throw '记录路径超出允许目录。'}
  if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {throw '记录中发现链接，停止清空。'}
  if(@(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count) {throw '记录中发现嵌套链接，停止清空。'}
  $statePath=Join-Path $resolved 'state.json'
  if(!(Test-Path -LiteralPath $statePath)) {throw '发现非轮次目录，停止清空。'}
  $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($state.Phase -in @('PurchasePending','RefreshPending')) {throw '有尚未核实的交易，请先处理后再清空记录。'}
  $resolved
 }
}
function Reset-Display {
 $script:currentDir=$null;$script:lastLog='';$script:sessions=@{};$roundList.Items.Clear()
 foreach($label in $metricValues) {$label.Text='0'}
 foreach($label in $metricSubs) {$label.Text='尚未开始'}
 $bookRate.Text='书签出货率  —';$mysticRate.Text='神秘出货率  —';$goldLabel.Text='金币花费  0'
 $statusLabel.Text='记录已清空';$logBox.Text='轮次记录、日志及截图已清空。设置预算后可新建一轮。'
 $footer.Text='当前没有运行任务；清空记录不会自动开始刷店。'
 Refresh-View
}
function Completion-Message($state,[int]$ExitCode) {
 $reason='任务已停止，请查看运行日志。'
 if($state) {
  if($state.Phase -eq 'BudgetOrRunLimit') {$reason='本轮已完成：达到设定的刷新预算或次数上限。'}
  elseif($state.Phase -in @('InsufficientGold','InsufficientSkystones','BalanceUnreadable')) {$reason=[string]$state.StopReason}
  elseif($state.Phase -in @('PurchasePending','RefreshPending')) {$reason='交易结果尚未确认，已停止。请保留游戏画面和日志，核实前不要重复购买或刷新。'}
  elseif($state.Phase -eq 'Stopped') {$reason='任务已停止。若非手动停止，请查看日志中的具体原因。'}
  $reason+=[Environment]::NewLine+[Environment]::NewLine+('天空石：{0} / {1}；刷新：{2} 次' -f $state.ReservedSkystones,$state.Budget,$state.ConfirmedRefreshes)
  $reason+=[Environment]::NewLine+('圣约书签：{0} 个；神秘奖牌：{1} 个' -f ([int]$state.BookPurchases*5),([int]$state.MysticPurchases*50))
 }
 return $reason
}
$clearButton.Add_Click({
 try {
  if(Is-Running) {throw '请先停止任务，再清空记录。'}
  $guard=New-Object Threading.Mutex($false,'Local\EpicSevenShopWorker')
  $locked=$false
  try {
   $locked=$guard.WaitOne(0)
   if(!$locked) {throw '仍有后台刷店任务运行，不能清空记录。'}
   $targets=@(Get-ClearTargets $script:sessionRoot)
   if(!$targets.Count) {Reset-Display;return}
   $answer=[Windows.Forms.MessageBox]::Show($form,('清空全部 '+$targets.Count+' 轮记录、日志及截图？此操作不可恢复，不会修改游戏资源。'),'清空记录',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning,[Windows.Forms.MessageBoxDefaultButton]::Button2)
   if($answer -ne [Windows.Forms.DialogResult]::Yes) {return}
   foreach($target in $targets) {[IO.Directory]::Delete($target,$true)}
   Reset-Display
  } finally {if($locked){$guard.ReleaseMutex()};$guard.Dispose()}
 } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法清空') | Out-Null}
})
function Request-Stop {
 if(Is-Running) {[IO.File]::WriteAllText((Join-Path $script:currentDir 'STOP'),'stop');$statusLabel.Text='正在停止';$footer.Text='已请求停止，等待当前交易核对完成。'}
}
$stopButton.Add_Click({Request-Stop})
$openButton.Add_Click({if($script:currentDir){Start-Process -FilePath 'explorer.exe' -ArgumentList (Quote-Arg $script:currentDir) | Out-Null}})
$applySize.Add_Click({
 try {
  $parts=([string]$resolution.SelectedItem) -split ' × '
  New-Item -ItemType Directory -Force -Path $script:dataDir | Out-Null
  $script:resizeOut=Join-Path $script:dataDir 'resize.json';$script:resizeErr=Join-Path $script:dataDir 'resize-error.log'
  $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File '+(Quote-Arg (Join-Path $script:base 'Resize-EpicSeven.ps1'))+' -Width '+[int]$parts[0]+' -Height '+[int]$parts[1]
  $script:resizeProcess=Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList $args -RedirectStandardOutput $script:resizeOut -RedirectStandardError $script:resizeErr
  $sizeHint.Text='正在调整游戏窗口…';Refresh-View
 } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'窗口调整失败') | Out-Null}
})
$script:timer=New-Object Windows.Forms.Timer;$timer.Interval=1000
$timer.Add_Tick({
 try {
  if($script:resizeProcess -and $script:resizeProcess.HasExited) {
   if($script:resizeProcess.ExitCode -eq 0) {
    $result=Get-Content -LiteralPath $script:resizeOut -Raw | ConvertFrom-Json
    $sizeHint.Text=('已应用：{0} × {1}' -f $result.AfterClientWidth,$result.AfterClientHeight)
   } else {$sizeHint.Text='调整失败，请查看日志';$logBox.Text=Get-Content -LiteralPath $script:resizeErr -Raw}
   $script:resizeProcess.Dispose();$script:resizeProcess=$null
  }
  if($script:worker -and $script:worker.HasExited) {
   $exitCode=$script:worker.ExitCode
   $script:worker.Dispose();$script:worker=$null
   Refresh-View
   if(!$script:closing) {
    $notice=Completion-Message (Read-State) $exitCode
    [Windows.Forms.MessageBox]::Show($form,$notice,'刷店任务提示',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   }
  }
  Refresh-View
  if($script:closing -and !(Is-Running)) {$form.Close()}
 } catch {$footer.Text=$_.Exception.Message}
})
$form.Add_FormClosing({param($sender,$eventArgs) if(Is-Running){$eventArgs.Cancel=$true;$script:closing=$true;Request-Stop}})
if($script:preview) {
 if($SelfTest) {Load-Rounds}
 foreach($layoutPanel in @($config,$roundPanel)) {
 for($i=0;$i -lt $layoutPanel.Controls.Count;$i++) {
  for($j=$i+1;$j -lt $layoutPanel.Controls.Count;$j++) {
   if($layoutPanel.Controls[$i].Bounds.IntersectsWith($layoutPanel.Controls[$j].Bounds)) {
    throw ('Configuration controls overlap: '+$layoutPanel.Controls[$i].Text+' / '+$layoutPanel.Controls[$j].Text)
   }
  }
 }
 }
 $metricValues[0].Text='174 / 300';$metricValues[0].Font=New-Object Drawing.Font('Microsoft YaHei UI',16)
 $metricSubs[0].Text='剩余 126 石';$metricValues[1].Text='58';$metricSubs[1].Text='演示数据 · 59 页'
 $metricValues[2].Text='15 个';$metricSubs[2].Text='购买 3 批，每批 5 个'
 $metricValues[3].Text='100 个';$metricSubs[3].Text='购买 2 批，每批 50 个'
 $bookRate.Text='书签出货率  5.1%（3/59）';$mysticRate.Text='神秘出货率  3.4%（2/59）';$goldLabel.Text='金币花费  1,112,000'
 $statusLabel.Text='界面预览';$footer.Text='界面预览使用演示数据；未连接游戏，不会执行刷新或购买。'
 [void]$roundList.Items.Add('示例轮次 · 300 天空石');$roundList.SelectedIndex=0
 $logBox.Text='界面示例：'+[Environment]::NewLine+'已购买 神秘奖牌 ×50；商品状态核对通过。'+[Environment]::NewLine+'已购买 圣约书签 ×5；商品状态核对通过。'+[Environment]::NewLine+'停止与继续沿用本轮预算；新一轮单独保存记录。'
 if($PreviewPath) {
  $form.CreateControl();$form.Show();[Windows.Forms.Application]::DoEvents()
  $image=New-Object Drawing.Bitmap($form.Width,$form.Height)
  $form.DrawToBitmap($image,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
  $image.Save($PreviewPath,[Drawing.Imaging.ImageFormat]::Png);$image.Dispose();$form.Close()
 }
 Write-Host 'Panel construction passed. Preview only; no worker launched.'
 $form.Dispose();return
}
Startup-Log 'Loading saved rounds'
Load-Rounds
Startup-Log 'Showing main window'
$timer.Start()
try {[void]$form.ShowDialog()} finally {$timer.Stop();$timer.Dispose();$form.Dispose();if($script:ownsPanelMutex){$script:panelMutex.ReleaseMutex()};$script:panelMutex.Dispose()}
