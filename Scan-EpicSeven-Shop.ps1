param(
 [ValidateRange(0,100000)][int]$MaxRefreshes=100000,
 [switch]$InspectPurchase,[switch]$AutoBuy,[switch]$MuMu,
 [ValidateRange(3,300000)][int]$BudgetLimit=300,
 [string]$StatePath,[string]$StopFile,[string]$RunOutputPath,[long]$GameWindowHandle=0
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$script:workerMutex=New-Object Threading.Mutex($false,'Local\EpicSevenShopWorker')
if(!$script:workerMutex.WaitOne(0)) {throw 'Another shop worker is already running. Close it before starting a new one.'}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class E7Scout {
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int X,Y;}
 delegate bool EnumCallback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumCallback callback,IntPtr p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr h,POINT p,uint flags);
 [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from,IntPtr to,ref POINT p,uint count);
 public static IntPtr GameSurface(IntPtr root){
  RECT outer;if(!GetClientRect(root,out outer))return IntPtr.Zero;
  long best=0;IntPtr result=IntPtr.Zero;
  EnumChildWindows(root,(h,p)=>{RECT r;
   if(IsWindowVisible(h)&&GetClientRect(h,out r)&&r.Right>=640&&r.Bottom>=360&&Math.Abs((double)r.Right/r.Bottom-16.0/9)<0.04){
    long area=(long)r.Right*r.Bottom;
    if(area>best&&area>(long)outer.Right*outer.Bottom*0.4){best=area;result=h;}
   }return true;
  },IntPtr.Zero);
  if(result==IntPtr.Zero&&outer.Bottom>0&&Math.Abs((double)outer.Right/outer.Bottom-16.0/9)<0.04)result=root;
  return result;
 }
 static IntPtr receiver;static bool pressed;
 public static IntPtr RouteMouse(IntPtr root,uint message,int buttons,int x,int y,out IntPtr result){
  POINT point=new POINT{X=x,Y=y};
  if(!pressed){
   receiver=root;
   for(int i=0;i<20;i++){
    POINT local=point;MapWindowPoints(root,receiver,ref local,1);
    IntPtr child=ChildWindowFromPointEx(receiver,local,7);
    if(child==IntPtr.Zero||child==receiver)break;receiver=child;
   }
  }
  result=IntPtr.Zero;if(!IsWindow(receiver))return IntPtr.Zero;
  MapWindowPoints(root,receiver,ref point,1);
  if(message==0x201)pressed=true;
  try{return SendMessageTimeout(receiver,message,new IntPtr(buttons),new IntPtr((point.Y<<16)|(point.X&65535)),2,1500,out result);}
  finally{if(message==0x202)pressed=false;}
 }
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static void CleanStock(System.Drawing.Bitmap b) {
  for(int y=0;y<b.Height;y++)for(int x=0;x<b.Width;x++){
   var c=b.GetPixel(x,y);
   bool yellow=c.R>135&&c.G>105&&c.R>c.B*1.3&&c.G>c.B*1.2;
   bool white=c.R>175&&c.G>175&&c.B>175;
   b.SetPixel(x,y,yellow||white?System.Drawing.Color.Black:System.Drawing.Color.White);
  }
 }
 public static void CleanNumbers(System.Drawing.Bitmap b) {
  for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) {
   var c=b.GetPixel(x,y);
   b.SetPixel(x,y,c.R>155 && c.G>155 && c.B>155 ? System.Drawing.Color.Black : System.Drawing.Color.White);
  }
 }
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint msg,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
}
"@
[void][E7Scout]::SetProcessDPIAware()
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
$script:asTask=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1
function Await($op,[Type]$type) {
 $task=$script:asTask.MakeGenericMethod($type).Invoke($null,@($op))
 if (!$task.Wait(15000)) {throw 'OCR timed out.'}
 return $task.Result
}
$script:engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (!$engine) {throw 'Windows OCR unavailable.'}
if($GameWindowHandle -ne 0){
 $script:handle=[IntPtr]$GameWindowHandle
 [uint32]$windowProcess=0
 if(![E7Scout]::IsWindow($handle) -or [E7Scout]::GetWindowThreadProcessId($handle,[ref]$windowProcess) -eq 0){throw 'Game window no longer exists.'}
 $gameProcess=Get-Process -Id $windowProcess -ErrorAction Stop
 if($MuMu){
  if($gameProcess.ProcessName -notin @('MuMuNxDevice','MuMuPlayer','NemuPlayer')){throw '所选窗口不属于 MuMu 模拟器。'}
 }elseif($gameProcess.ProcessName -ne 'EpicSeven'){throw 'Window does not belong to EpicSeven.'}
}else{
 if($MuMu){throw '请先在助手连接 MuMu，再开始刷店。'}
 $games=@(Get-Process -Name EpicSeven | Where-Object {$_.MainWindowHandle -ne 0})
 if ($games.Count -ne 1) {throw 'Expected one EpicSeven window.'}
 $script:handle=$games[0].MainWindowHandle
}
# Match the target window's coordinate space for capture, OCR and mouse messages.
$script:gameDpiContext=[E7Scout]::GetWindowDpiAwarenessContext($handle)
if($script:gameDpiContext -eq [IntPtr]::Zero -or [E7Scout]::SetThreadDpiAwarenessContext($script:gameDpiContext) -eq [IntPtr]::Zero) {throw 'Cannot align game DPI coordinate space.'}
$script:sourceHandle=$handle
if($MuMu){
 $script:handle=[E7Scout]::GameSurface($sourceHandle)
 if($handle -eq [IntPtr]::Zero){throw '无法定位 MuMu 的横屏游戏画面，请将模拟器设为 1280×720 并打开秘密商店。'}
 [uint32]$surfaceProcess=0
 [void][E7Scout]::GetWindowThreadProcessId($handle,[ref]$surfaceProcess)
 $surfaceOwner=Get-Process -Id $surfaceProcess -ErrorAction Stop
 if($surfaceOwner.ProcessName -notin @('MuMuNxDevice','MuMuPlayer','NemuPlayer')){throw 'MuMu 游戏画面归属发生变化。'}
}
$script:rect=New-Object E7Scout+RECT
if (![E7Scout]::GetClientRect($handle,[ref]$script:rect)) {throw 'Cannot get window size.'}
$script:w=$rect.Right; $script:h=$rect.Bottom
if ([Math]::Abs($w/$h-16/9) -gt 0.04) {throw 'Expected a 16:9 game window.'}
$script:runDir=Join-Path $PSScriptRoot ('shop-scan-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if($RunOutputPath) {$script:runDir=$RunOutputPath}
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$script:budgetPath=Join-Path $PSScriptRoot 'shop-budget-300.json'
if($StatePath) {$script:budgetPath=$StatePath}
$script:stopPath=Join-Path $PSScriptRoot 'STOP-EpicSeven'
if($StopFile) {$script:stopPath=$StopFile}
$script:budget=[pscustomobject]@{Budget=$BudgetLimit;ReservedSkystones=0;ConfirmedRefreshes=0;Phase='Ready';Purchases=0}
if (Test-Path -LiteralPath $budgetPath) {$script:budget=Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json}
if ($budget.Budget -ne $BudgetLimit -or $budget.ReservedSkystones -lt 0 -or $budget.ReservedSkystones -gt $budget.Budget) {throw 'Invalid budget checkpoint.'}
if ($budget.Phase -in @('RefreshPending','PurchasePending')) {throw 'Previous refresh outcome uncertain. Inspect checkpoint and game before continuing.'}
if (!$budget.PSObject.Properties['BoughtThisRefresh']) {$budget | Add-Member -NotePropertyName BoughtThisRefresh -NotePropertyValue @()}
if (!$budget.PSObject.Properties['LastPurchase']) {$budget | Add-Member -NotePropertyName LastPurchase -NotePropertyValue $null}
foreach($entry in @{'BookPurchases'=0;'MysticPurchases'=0;'GoldSpent'=0;'PagesScanned'=0;'BookHitPages'=0;'MysticHitPages'=0;'LastCountedRefresh'=-1;'SeenThisRefresh'=@();'StopReason'='';'LastGoldBalance'=$null;'LastSkystoneBalance'=$null}.GetEnumerator()) {
 if(!$budget.PSObject.Properties[$entry.Key]) {$budget | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value}
}
function Save-Budget {
 $temp=$budgetPath+'.tmp'
 $budget | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
 Move-Item -LiteralPath $temp -Destination $budgetPath -Force
}
function Check-Stop {
 [void][E7Scout]::SetThreadDpiAwarenessContext($script:gameDpiContext)
 if ($budget.Phase -notin @('PurchasePending','RefreshPending') -and ((Test-Path -LiteralPath $stopPath) -or ([E7Scout]::GetAsyncKeyState(0x77) -band 0x8000))) {throw 'Stopped by user (F8 or STOP-EpicSeven file).'}
 if (![E7Scout]::IsWindow($handle)){throw 'Game window closed.'}; if ([E7Scout]::IsIconic($sourceHandle)) {throw 'Game is minimized. Keep the window restored.'}
 $current=New-Object E7Scout+RECT
 if (![E7Scout]::GetClientRect($handle,[ref]$current) -or $current.Right -ne $w -or $current.Bottom -ne $h) {throw 'Window size changed. Stopping.'}
}
function Mouse([uint32]$msg,[int]$buttons,[int]$x,[int]$y) {
 $reply=[IntPtr]::Zero
 $packed=($x -band 0xffff) -bor (($y -band 0xffff) -shl 16)
  if($MuMu){$sent=[E7Scout]::RouteMouse($handle,$msg,$buttons,$x,$y,[ref]$reply)}
 else{$sent=[E7Scout]::SendMessageTimeout($handle,$msg,[IntPtr]$buttons,[IntPtr]$packed,2,1500,[ref]$reply)}
 if ($sent -eq [IntPtr]::Zero) {throw ('Background input failed: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
}
function Click([double]$nx,[double]$ny) {
 Check-Stop
 $x=[int]($nx*$w);$y=[int]($ny*$h)
 Mouse 0x200 0 $x $y
 try {Mouse 0x201 1 $x $y; Start-Sleep -Milliseconds 100} finally {Mouse 0x202 0 $x $y}
 Start-Sleep -Milliseconds 800
}
function Drag-List([bool]$Down) {
 Check-Stop
 $x=[int]($w*0.73)
 if ($Down) {$a=0.77;$b=0.30} else {$a=0.30;$b=0.82}
 $y=[int]($h*$a)
 Mouse 0x200 0 $x $y
 try {
  Mouse 0x201 1 $x $y
  Start-Sleep -Milliseconds 100
  for($i=1;$i -le 20;$i++) {$y=[int]($h*($a+($b-$a)*$i/20));Mouse 0x200 1 $x $y;Start-Sleep -Milliseconds 25}
 } finally {Mouse 0x202 0 $x $y}
 Start-Sleep -Milliseconds 800
}
$script:frame=0
function Read-RegionOcr([string]$ImagePath,[double]$NX,[double]$NY,[double]$NW,[double]$NH,[switch]$Numbers,[switch]$Stock,[ValidateRange(1,4)][int]$OcrScale=2) {
 foreach($value in @($NX,$NY,$NW,$NH)){
  if([double]::IsNaN($value) -or [double]::IsInfinity($value)){throw 'OCR 裁剪坐标无效。'}
 }
 if($NW -le 0 -or $NH -le 0){return}
 $source=$null;$crop=$null;$g=$null
 $cropPath=$ImagePath+'.region.png'
 try{
  $source=[System.Drawing.Bitmap]::FromFile($ImagePath)
  # Intersect the requested rectangle with the image; an empty region is not evidence.
  $left=[Math]::Max(0.0,[Math]::Min([double]$source.Width,[Math]::Floor($source.Width*$NX)))
  $top=[Math]::Max(0.0,[Math]::Min([double]$source.Height,[Math]::Floor($source.Height*$NY)))
  $right=[Math]::Max(0.0,[Math]::Min([double]$source.Width,[Math]::Ceiling($source.Width*($NX+$NW))))
  $bottom=[Math]::Max(0.0,[Math]::Min([double]$source.Height,[Math]::Ceiling($source.Height*($NY+$NH))))
  $rx=[int]$left;$ry=[int]$top;$rw=[int]($right-$left);$rh=[int]($bottom-$top)
  if($rw -le 0 -or $rh -le 0){return}
  $scale=$OcrScale;if($Numbers){$scale=4}
  [int]$cropWidth=$rw*$scale;[int]$cropHeight=$rh*$scale
  $crop=New-Object System.Drawing.Bitmap -ArgumentList $cropWidth,$cropHeight
  $g=[System.Drawing.Graphics]::FromImage($crop)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $dest=New-Object System.Drawing.Rectangle -ArgumentList 0,0,$cropWidth,$cropHeight
  $src=New-Object System.Drawing.Rectangle -ArgumentList $rx,$ry,$rw,$rh
  $g.DrawImage($source,$dest,$src,[System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose();$g=$null
  if($Numbers){[E7Scout]::CleanNumbers($crop)}
  if($Stock){[E7Scout]::CleanStock($crop)}
  $crop.Save($cropPath,[System.Drawing.Imaging.ImageFormat]::Png)
 }finally{
  if($g){$g.Dispose()};if($crop){$crop.Dispose()};if($source){$source.Dispose()}
 }
 $file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($cropPath)) ([Windows.Storage.StorageFile])
 $stream=Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
 try {
  $decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap=Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  try {$result=Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])} finally {$bitmap.Dispose()}
 } finally {$stream.Dispose()}
 foreach($line in $result.Lines) {
  $words=@($line.Words)
  if($words.Count -gt 0) {
   $left=($words | ForEach-Object {$_.BoundingRect.X} | Measure-Object -Minimum).Minimum
   $top=($words | ForEach-Object {$_.BoundingRect.Y} | Measure-Object -Minimum).Minimum
   [pscustomobject]@{Text=($line.Text -replace '\s','');X=($rx+$left/$scale);Y=($ry+$top/$scale)}
  }
 }
}

function Snapshot {
 Check-Stop
 $script:frame++
 $path=Join-Path $runDir ('frame-{0:D4}.png' -f $script:frame)
 $bmp=New-Object System.Drawing.Bitmap($w,$h)
 $graphics=[System.Drawing.Graphics]::FromImage($bmp);$dc=$graphics.GetHdc()
 try {$ok=[E7Scout]::PrintWindow($handle,$dc,3)} finally {$graphics.ReleaseHdc($dc);$graphics.Dispose()}
 try {if (!$ok) {throw 'Screenshot failed.'};$bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)} finally {$bmp.Dispose()}
 $file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
 $stream=Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
 try {
  $decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap=Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  try {$ocr=Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])} finally {$bitmap.Dispose()}
 } finally {$stream.Dispose()}
 $lines=@(foreach($line in $ocr.Lines) {
  $words=@($line.Words)
  if ($words.Count -gt 0) {
   $left=($words | ForEach-Object {$_.BoundingRect.X} | Measure-Object -Minimum).Minimum
   $top=($words | ForEach-Object {$_.BoundingRect.Y} | Measure-Object -Minimum).Minimum
   [pscustomobject]@{Text=($line.Text -replace '\s','');X=$left;Y=$top}
  }
 })
 # Read critical UI regions separately so animated artwork cannot disrupt OCR layout.
 $lines += @(Read-RegionOcr $path 0.0 0.0 0.24 0.09)
 $lines += @(Read-RegionOcr $path 0.04 0.86 0.25 0.12)
 $lines += @(Read-RegionOcr $path 0.53 0.09 0.28 0.90)
 $text=($lines.Text -join "`n")
 $text | Set-Content -LiteralPath ($path+'.txt') -Encoding UTF8
 $snapshot=[pscustomobject]@{Path=$path;Lines=$lines;Text=$text}
 Check-ResourcePopup $snapshot
 return $snapshot
}
function Refresh-Dialog($s) {return $s.Text -match '天空石立即更新'}
function Validate-ShopOnce($s) {
 if ((Refresh-Dialog $s) -or (Purchase-Dialog $s) -or $s.Text -notmatch '秘密商店' -or $s.Text -notmatch '立即更新') {throw ('Shop screen could not be verified: '+$s.Path)}
 $rows=@($s.Lines | Where-Object {$_.X -gt $w*0.5 -and $_.Y -gt $h*0.08 -and $_.Y -lt $h*0.90 -and $_.Text -match '可购[买買]1次'})
 if ($rows.Count -lt 2) {throw ('Not enough readable item rows. No refresh performed: '+$s.Path)}
}
function Validate-Shop($s) {
 $current=$s
 for($check=0;$check -lt 5;$check++) {
  # Dialogs must remain under their existing purchase/refresh handlers.
  if((Refresh-Dialog $current) -or (Purchase-Dialog $current)) {
   throw ('Shop screen is a confirmation dialog: '+$current.Path)
  }
  try {
   Validate-ShopOnce $current
   # Callers must inspect the recovered frame, not the stale loading frame.
   $s.Path=$current.Path;$s.Lines=$current.Lines;$s.Text=$current.Text
   return
  } catch {
   if($check -eq 4){throw}
  }
  Write-Host ('Waiting for readable shop screen: '+($check+1)+'/4. No input sent.')
  Start-Sleep -Milliseconds 800
  $current=Snapshot
 }
}
function Find-Target($s) {
 $seen=New-Object System.Collections.Generic.List[object]
 $candidates=@($s.Lines | Where-Object {$_.X -gt $w*0.48 -and $_.Y -gt $h*0.08 -and $_.Y -lt $h*0.95 -and $_.Text -match '书签|書籤|圣约|聖約|神秘'})
 foreach($candidate in $candidates) {
  $available=@($s.Lines | Where-Object {
   $_.X -gt $w*0.5 -and $_.X -lt $w*0.81 -and
   $_.Y -gt ($candidate.Y+$h*0.02) -and $_.Y -lt ($candidate.Y+$h*0.085) -and
   $_.Text -match '可购[买買]1次'
  })
  $alreadyBought=$false
  if($candidate.Text -match '书签|書籤|圣约|聖約') {$alreadyBought=@($budget.BoughtThisRefresh | Where-Object {$_ -match '书签|書籤'}).Count -gt 0}
  if($candidate.Text -match '神秘') {$alreadyBought=@($budget.BoughtThisRefresh | Where-Object {$_ -match '神秘'}).Count -gt 0}
  # A verified purchase may leave a partial-name toast or a disabled sold row.
  # Only suppress it when there is no available item row beneath the name.
  if($alreadyBought -and $available.Count -eq 0) {continue}
  $duplicate=@($seen | Where-Object {$_.Text -eq $candidate.Text -and [Math]::Abs($_.Y-$candidate.Y) -le $h*0.018 -and [Math]::Abs($_.X-$candidate.X) -le $w*0.025})
  if($duplicate.Count -eq 0){$seen.Add($candidate);$candidate}
 }
}
function Purchase-Dialog($s) {return $s.Text -match '购买商品|确定要购买该商品'}
function Parse-Currency($Lines) {
 $values=@(foreach($line in $Lines) {
  foreach($m in [regex]::Matches($line.Text,'[0-9][0-9,，]*')) {
   $token=$m.Value
   if($token -notmatch '^([0-9]{1,3}([,，][0-9]{3})+|[0-9]+)$') {continue}
   [long]($token -replace '[,，]','')
  }
 })
 $values=@($values | Select-Object -Unique)
 if($values.Count -ne 1) {throw 'Currency balance could not be read reliably.'}
 return $values[0]
}
function Stop-Resource([string]$Kind,[string]$Message) {
 if($Kind -eq 'InsufficientSkystones' -and $budget.Phase -eq 'RefreshPending') {
  $budget.ReservedSkystones=[Math]::Max(0,$budget.ReservedSkystones-3)
 }
 if($Kind -eq 'InsufficientGold' -and $budget.Phase -eq 'PurchasePending' -and $budget.LastPurchase) {$budget.LastPurchase.Status='RejectedInsufficientGold'}
 $budget.Phase=$Kind;$budget.StopReason=$Message;Save-Budget
 throw $Message
}
function Check-ResourcePopup($s) {
 $text=$s.Text -replace '\s',''
 if($text -match '(天空石.{0,12}(不足|不够|不夠)|(不足|不够|不夠).{0,12}天空石)') {Stop-Resource 'InsufficientSkystones' '天空石不足，已停止；不会进入补充或充值操作。'}
 if($text -match '((金币|金幣|金钱|金錢).{0,12}(不足|不够|不夠)|(不足|不够|不夠).{0,12}(金币|金幣|金钱|金錢))') {Stop-Resource 'InsufficientGold' '金币不足，已停止购买和刷新。'}
}




function Read-StockToken([string]$Text) {
 # OCR may combine the quantity and purchase label into one line.
 $text=($Text -replace '\s','') -replace '／','/'
 $match=[regex]::Match($text,'^(?<n>[01])/1(?:(?:购买|購買))?$')
 if($match.Success){return ($match.Groups['n'].Value+'/1')}
 return $null
}
function Item-Stock($s,[string]$Name,[int]$Quantity) {
 $items=@($s.Lines | Where-Object {$_.Text -eq $Name -and $_.X -gt $w*0.5 -and $_.Y -gt $h*0.08})
 foreach($item in $items) {
  $readings=@(foreach($line in $s.Lines){
   if($line.X -gt $w*0.82 -and $line.X -lt $w*0.91 -and $line.Y -gt ($item.Y+$h*0.012) -and $line.Y -lt ($item.Y+$h*0.08)){
    $value=Read-StockToken $line.Text;if($value){$value}
   }
  })
  foreach($scale in @(1,2,3,4)) {
   # Exclude most of the purchase label while retaining the entire quantity.
   $crop=@(Read-RegionOcr $s.Path 0.82 (($item.Y/$h)+0.006) 0.09 0.08 -OcrScale $scale)
   $scaleValues=@(@(foreach($line in $crop){$value=Read-StockToken $line.Text;if($value){$value}}) | Select-Object -Unique)
   $readings+=@($scaleValues)
  }
  foreach($scale in @(2,3,4)) {
   $cleanCrop=@(Read-RegionOcr $s.Path 0.82 (($item.Y/$h)+0.006) 0.09 0.08 -Stock -OcrScale $scale)
   $cleanValues=@(@(foreach($line in $cleanCrop){$value=Read-StockToken $line.Text;if($value){$value}}) | Select-Object -Unique)
   $readings+=@($cleanValues)
  }
  $unique=@($readings | Select-Object -Unique)
  [pscustomobject]@{Item=$Name;Requested=$Quantity;X=$item.X;Y=$item.Y;Width=$w;Height=$h;StockReadings=$readings} | ConvertTo-Json -Compress | Add-Content -LiteralPath ($s.Path+'.stock.jsonl') -Encoding UTF8
  # Independent evidence from the same item's availability label can corroborate
  # one exact quantity reading when the tiny yellow digits fail crop OCR.
  $availableLabel=@($s.Lines | Where-Object {
   $_.Text -match '^可购[买買]1次$' -and $_.X -gt $w*0.50 -and $_.X -lt $w*0.80 -and
   $_.Y -gt ($item.Y+$h*0.015) -and $_.Y -lt ($item.Y+$h*0.08)
  })
  if($Quantity -eq 1 -and $unique.Count -eq 1 -and $unique[0] -eq '1/1' -and $availableLabel.Count -gt 0){return $true}
  # The full-frame and regional OCR already identify this item's row.
  # Buy-Visible corroborates this result on a new frame before opening the dialog.
  if($Quantity -eq 1 -and $unique -notcontains '0/1' -and $availableLabel.Count -gt 0){return $true}
  if($Quantity -eq 0 -and $unique.Count -eq 1 -and $unique[0] -eq '0/1' -and $availableLabel.Count -eq 0){return $true}
  if($readings.Count -ge 2 -and $unique.Count -eq 1 -and $unique[0] -eq ($Quantity.ToString()+'/1')) {return $true}
 }
 return $false
}
function Buy-Visible($s) {
 while($true) {
  Validate-Shop $s
  $targets=@(Find-Target $s | Where-Object {$budget.BoughtThisRefresh -notcontains $_.Text} | Sort-Object Y)
  if($targets.Count -eq 0) {return $s}
  $target=$targets[0]
  if($target.Text -notmatch '^(神秘奖牌|神秘獎牌|圣约书签|聖約書籤)$') {throw ('Uncertain target name; stopped for review: '+$target.Text)}
  if($target.Y -gt $h*0.93) {throw 'Target purchase button is not fully visible. Stopping without refreshing.'}
  if(Item-Stock $s $target.Text 0) {
   Start-Sleep -Milliseconds 400
   $soldCheck=Snapshot
   Validate-Shop $soldCheck
   if(Item-Stock $soldCheck $target.Text 0){
    $budget.BoughtThisRefresh=@($budget.BoughtThisRefresh)+@($target.Text)
    Save-Budget
    Write-Host ('跳过已售出商品：'+$target.Text+'；不计入本轮购买统计。')
    $s=$soldCheck
    continue
   }
   $s=$soldCheck
  }
  $stockReady=Item-Stock $s $target.Text 1
  for($stockRetry=0;!$stockReady -and $stockRetry -lt 2;$stockRetry++){
   Start-Sleep -Milliseconds 400
   $s=Snapshot
   Validate-Shop $s
   $matches=@(Find-Target $s | Where-Object {$_.Text -eq $target.Text -and [Math]::Abs($_.Y-$target.Y) -le $h*0.035 -and [Math]::Abs($_.X-$target.X) -le $w*0.04})
   if($matches.Count -ne 1){
    if($stockRetry -lt 1){continue}
    throw ('重新截图后原商品位置仍不明确，未购买。截图：'+$s.Path)
   }
   $target=$matches[0]
   if($target.Y -gt $h*0.90){throw '目标购买按钮显示不完整，已停止。'}
   $stockReady=Item-Stock $s $target.Text 1
  }
  if(!$stockReady){throw ('目标商品可购买状态（1/1或同一行可购买1次）仍无法确认，未购买。截图：'+$s.Path)}
  Start-Sleep -Milliseconds 400
  $confirmedFrame=Snapshot
  Validate-Shop $confirmedFrame
  $sameRow=@(Find-Target $confirmedFrame | Where-Object {
   $_.Text -eq $target.Text -and [Math]::Abs($_.Y-$target.Y) -le $h*0.035 -and [Math]::Abs($_.X-$target.X) -le $w*0.04
  })
  if($sameRow.Count -ne 1 -or !(Item-Stock $confirmedFrame $target.Text 1)){
   throw ('第二张截图未确认同一商品仍可购买，未点击购买。截图：'+$confirmedFrame.Path)
  }
  $s=$confirmedFrame;$target=$sameRow[0]
  if($budget.SeenThisRefresh -notcontains $target.Text) {$budget.SeenThisRefresh=@($budget.SeenThisRefresh)+@($target.Text);Save-Budget}
  $requiredPrice=184000
  if($target.Text -match '神秘') {$requiredPrice=280000}
  Check-ResourcePopup $s
  Click 0.93 (($target.Y/$h)+0.05)
  $dialog=Snapshot
  if(!(Purchase-Dialog $dialog)) {throw 'Purchase confirmation not recognized.'}
  $names=@(Read-RegionOcr $dialog.Path 0.39 0.41 0.25 0.16)
  if($names.Text -notcontains $target.Text) {throw 'Purchase dialog item does not match the target.'}
  $priceEvidence=@()
  $prices=@(foreach($enhanced in @($false,$true)){
   foreach($scale in @(1,2,3)) {
    $priceLines=@(Read-RegionOcr $dialog.Path 0.505 0.68 0.08 0.06 -Stock:$enhanced -OcrScale $scale)
    $priceEvidence+=[pscustomobject]@{Scale=$scale;Enhanced=$enhanced;Lines=@($priceLines.Text)}
    # Accept an intact number with or without a thousands separator.
    # Do not concatenate multiple OCR lines or infer missing digits from the expected price.
    if($priceLines.Count -eq 1){
     $priceText=$priceLines[0].Text -replace '\s',''
     if($priceText -match '^(?:[0-9]{1,3}[,，][0-9]{3}|[0-9]{6})$'){
      [long]($priceText -replace '[,，]','')
     }
    }
   }
  })
  $priceEvidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($dialog.Path+'.price.json') -Encoding UTF8
  if($prices.Count -lt 2 -or @($prices|Select-Object -Unique).Count -ne 1){throw ('购买确认框价格仍无法一致识别，未确认购买。截图：'+$dialog.Path)}
  $price=$prices[0]
  if($price -ne $requiredPrice){throw ('Unexpected target price: '+$price)}
  $budget.Phase='PurchasePending'
  $budget.LastPurchase=[pscustomobject]@{Item=$target.Text;Price=$price;Screenshot=$dialog.Path;Status='Pending'}
  Save-Budget
  Click 0.635 0.707
  $verified=$false;$soldFrames=0
  for($attempt=0;$attempt -lt 3;$attempt++) {
   Start-Sleep -Milliseconds 1000
   $after=Snapshot
   if(Purchase-Dialog $after) {$soldFrames=0;continue}
   try {
    Validate-Shop $after
    if(Item-Stock $after $target.Text 0) {$soldFrames++} else {$soldFrames=0}
    if($soldFrames -ge 2){$verified=$true;break}
   } catch {
    if($attempt -eq 2) {throw}
   }
  }
  if(!$verified) {throw 'Purchase outcome uncertain. No repeat confirmation will be sent.'}
  $budget.Purchases++
  if($target.Text -match '神秘') {$budget.MysticPurchases++} else {$budget.BookPurchases++}
  $budget.GoldSpent+=$price
  $budget.BoughtThisRefresh=@($budget.BoughtThisRefresh)+@($target.Text)
  $budget.LastPurchase.Status='Verified'
  $budget.Phase='Ready'
  Save-Budget
  Write-Host ('BOUGHT: '+$target.Text+'; gold: '+$price+'; verified purchases: '+$budget.Purchases) -ForegroundColor Green
  $budget.LastPurchase | ConvertTo-Json -Depth 4 | Add-Content -LiteralPath (Join-Path $runDir 'purchases.jsonl') -Encoding UTF8
  Start-Sleep -Milliseconds 2500
  $s=Snapshot
  Validate-Shop $s
 }
}

function Complete-Page {
  if($budget.LastCountedRefresh -ne $budget.ConfirmedRefreshes) {
   $budget.PagesScanned++
   if(@($budget.SeenThisRefresh | Where-Object {$_ -match '书签|書籤'}).Count -gt 0) {$budget.BookHitPages++}
   if(@($budget.SeenThisRefresh | Where-Object {$_ -match '神秘'}).Count -gt 0) {$budget.MysticHitPages++}
   $budget.LastCountedRefresh=$budget.ConfirmedRefreshes
   Save-Budget
  }
}
function Open-RefreshDialog {
 $screen=Snapshot
 Validate-Shop $screen
 Check-ResourcePopup $screen
 for($attempt=1;$attempt -le 3;$attempt++) {
  Check-Stop
  Click 0.21 0.92
  for($observation=0;$observation -lt 2;$observation++) {
   $screen=Snapshot
   if(Refresh-Dialog $screen) {return $screen}
   # Unknown screens or other dialogs fail closed; never click through them.
   Validate-Shop $screen
   if($observation -eq 0) {Start-Sleep -Milliseconds 700}
  }
  Write-Host ('Refresh button did not open confirmation; verified shop remains visible. Attempt '+$attempt+'/3.')
 }
 throw 'Refresh button did not respond after three attempts. No confirmation or budget charge was sent.'
}
function Can-Refresh([int]$Iteration,[int]$RunLimit) {
 return ($Iteration -lt $RunLimit -and $budget.ReservedSkystones+3 -le $budget.Budget)
}
function Record-Target($s,$targets) {
 $budget.Phase='TargetFound';Save-Budget
 [pscustomobject]@{Status='TargetFound';Candidates=$targets;Screenshot=$s.Path;ReservedSkystones=$budget.ReservedSkystones;ConfirmedRefreshes=$budget.ConfirmedRefreshes;Purchases=0;Note='Stopped before purchasing. Candidate recognition requires review.'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding UTF8
 Write-Host 'TARGET FOUND. Stopped before purchasing.' -ForegroundColor Green
 Write-Host $s.Path
}
try {
 if ($InspectPurchase) {
  $s=Snapshot
  Validate-Shop $s
  $targets=@(Find-Target $s | Where-Object {$_.Text -match '^(神秘奖牌|神秘獎牌|圣约书签|聖約書籤)$' -and $_.Y -gt $h*0.1 -and $_.Y -lt $h*0.85} | Sort-Object Y)
  if ($targets.Count -eq 0) {throw 'No fully recognized target in view. No input sent.'}
  $target=$targets[0]
  Click 0.93 (($target.Y/$h)+0.05)
  $dialog=Snapshot
  [pscustomobject]@{Status='PurchaseDialogOpened';Target=$target.Text;Screenshot=$dialog.Path;Budget=$budget;PurchasesPerformed=0} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding UTF8
  Write-Host 'Purchase dialog captured. No confirmation sent.'
  Write-Host ('Results: '+$runDir)
  return
 }
 Save-Budget
 if ($AutoBuy) {Write-Host 'AUTO BUY: covenant bookmarks and mystic medals only. Shared configured skystone cap. Hold F8 to stop.'} else {Write-Host 'Calibration scanner: stops on first possible target. Hold F8 to stop.'}
 $s=Snapshot
 if (Purchase-Dialog $s) {Click 0.376 0.707;$s=Snapshot}
 if (Refresh-Dialog $s) {Click 0.416 0.64;$s=Snapshot}
 Validate-Shop $s
 for($iteration=0;;$iteration++) {
  Drag-List $false
  $top=Snapshot;Validate-Shop $top
  $targets=Find-Target $top
  if ($AutoBuy) {$top=Buy-Visible $top} elseif ($targets.Count -gt 0) {Record-Target $top $targets;break}
  Drag-List $true
  $bottom=Snapshot;Validate-Shop $bottom
  $targets=Find-Target $bottom
  if ($AutoBuy) {$bottom=Buy-Visible $bottom} elseif ($targets.Count -gt 0) {Record-Target $bottom $targets;break}
  if ($top.Text -eq $bottom.Text) {throw 'Scrolling could not be verified.'}
  Complete-Page
  if (!(Can-Refresh $iteration $MaxRefreshes)) {
   $budget.Phase='BudgetOrRunLimit';Save-Budget
   [pscustomobject]@{Status='BudgetOrRunLimit';Budget=$budget} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding UTF8
   Write-Host 'Refresh limit reached.';break
  }
  $dialog=Open-RefreshDialog
  $budget.ReservedSkystones+=3;$budget.Phase='RefreshPending';Save-Budget
  Click 0.585 0.64
  Start-Sleep -Milliseconds 1200
  $shopReady=$false
  for($check=0;$check -lt 5;$check++) {
   $s=Snapshot
   try {Validate-Shop $s;$shopReady=$true;break} catch {
    if($check -lt 4) {Start-Sleep -Milliseconds 1000}
   }
  }
  if(!$shopReady) {
   $budget.StopReason='刷新确认后仍未返回可验证的商店画面，已停止。没有重复确认；本次预留的3天空石保留在预算内。'
   Save-Budget
   throw $budget.StopReason
  }
  $budget.ConfirmedRefreshes++;$budget.BoughtThisRefresh=@();$budget.SeenThisRefresh=@();$budget.Phase='Ready';Save-Budget
  Write-Host ('Refreshes: '+$budget.ConfirmedRefreshes+'; budget reserved: '+$budget.ReservedSkystones+'/'+$budget.Budget)
 }
} catch {
 $_ | Out-String | Set-Content -LiteralPath (Join-Path $runDir 'error.txt') -Encoding UTF8
 if($budget.Phase -notin @('PurchasePending','RefreshPending','InsufficientGold','InsufficientSkystones','BalanceUnreadable')) {$budget.Phase='Stopped';Save-Budget}
 Write-Host ('STOPPED: '+$_.Exception.Message) -ForegroundColor Red
 Write-Host ('Results: '+$runDir)
 throw
}
Write-Host ('Results: '+$runDir)

$script:workerMutex.ReleaseMutex();$script:workerMutex.Dispose()
