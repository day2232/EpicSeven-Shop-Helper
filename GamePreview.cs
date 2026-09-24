using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
public class GamePreview : Form {
 public static void AlignDpiToGame(){
  IntPtr context=new IntPtr(-4);
  foreach(var p in Process.GetProcessesByName("EpicSeven"))using(p){if(p.MainWindowHandle!=IntPtr.Zero){context=GetWindowDpiAwarenessContext(p.MainWindowHandle);break;}}
  if(context!=IntPtr.Zero)SetThreadDpiAwarenessContext(context);
 }
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 public static bool ActivateExisting() {
  IntPtr h=FindWindow(null,"第七史诗 · 截图预览");
  if(h==IntPtr.Zero)return false;
  ShowWindowAsync(h,IsIconic(h)?9:5);
  SetForegroundWindow(h);
  return true;
 }
 [StructLayout(LayoutKind.Sequential)] struct RECT { public int L,T,R,B; }
 [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h,int command);
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetStyle(IntPtr h,int i);
 [DllImport("user32.dll",EntryPoint="SetWindowLongW",SetLastError=true)] static extern int SetStyle(IntPtr h,int i,int v);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr h,IntPtr z,int x,int y,int w,int height,uint flags);
 bool sourceParked,windowBusy;int savedExStyle;RECT savedRect;
 async void ToggleWindow(){
  if(windowBusy||ShopRunning||clickPending||!SameWindow())return;
  if(sourceParked){Restore();return;}
  windowBusy=true;hide.Enabled=false;
  IntPtr window=target;int right=SystemInformation.VirtualScreen.Right;
  try{
   await Task.Run(()=>{
    IntPtr prior=SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(window));
    try{
     if(!GetWindowRect(window,out savedRect))throw new InvalidOperationException("无法读取原窗口位置");
     savedExStyle=GetStyle(window,-20);sourceParked=true;
     SetStyle(window,-20,(savedExStyle&~0x40000)|0x80);
     RECT client;
     if(!GetClientRect(window,out client))throw new InvalidOperationException("无法读取游戏画面尺寸");
     int outerWidth=1280+(savedRect.R-savedRect.L)-(client.R-client.L);
     int outerHeight=720+(savedRect.B-savedRect.T)-(client.B-client.T);
     if(!SetWindowPos(window,IntPtr.Zero,right+64,savedRect.T,outerWidth,outerHeight,0x4034))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }finally{if(prior!=IntPtr.Zero)SetThreadDpiAwarenessContext(prior);}
   });
   paused=false;hide.Text="退出窗口预览";status.Text="截图预览已开启，原游戏窗口及任务栏图标已隐藏。";
  }catch(Exception ex){status.Text="隐藏未完成："+ex.Message;}
  finally{windowBusy=false;hide.Enabled=!windowBusy;}
 }
 async void Restore(){
  if(windowBusy||ShopRunning||clickPending)return;
  windowBusy=true;hide.Enabled=false;
  try{
   if(SameWindow()){
    IntPtr window=target;
    if(sourceParked)await Task.Run(()=>{
     IntPtr prior=SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(window));
     try{
      SetStyle(window,-20,savedExStyle);
      if(!SetWindowPos(window,IntPtr.Zero,savedRect.L,savedRect.T,savedRect.R-savedRect.L,savedRect.B-savedRect.T,0x4074))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
     }finally{if(prior!=IntPtr.Zero)SetThreadDpiAwarenessContext(prior);}
    });
    ShowWindowAsync(window,5);
   }
   sourceParked=false;paused=true;hide.Text="嵌入游戏窗口";status.Text="已恢复原游戏窗口和任务栏图标，可关闭助手。";
  }catch(Exception ex){status.Text="恢复未完成："+ex.Message;}
  finally{windowBusy=false;hide.Enabled=SameWindow();}
 }
 bool emulator;readonly Label sourceLabel=new Label{AutoSize=true,Padding=new Padding(4,8,0,0)};
 delegate bool EnumWindowCallback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowCallback callback,IntPtr p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,System.Text.StringBuilder text,int count);
 class EmulatorChoice {
  public IntPtr Handle;public uint Pid;public string Title;
  public override string ToString(){return Title+" (PID "+Pid+")";}
 }
 void ConnectMuMu(){
  if(ShopRunning||clickPending||sourceParked||windowBusy)return;
  if(capture!=null){MessageBox.Show(this,"请等待当前截图完成后再连接。","连接 MuMu");return;}
  var processes=new System.Collections.Generic.HashSet<uint>();
  foreach(var p in Process.GetProcesses())using(p){
   if(p.ProcessName.Equals("MuMuNxDevice",StringComparison.OrdinalIgnoreCase)||p.ProcessName.Equals("MuMuPlayer",StringComparison.OrdinalIgnoreCase)||p.ProcessName.Equals("NemuPlayer",StringComparison.OrdinalIgnoreCase))processes.Add((uint)p.Id);
  }
  var choices=new System.Collections.Generic.List<EmulatorChoice>();
  EnumWindows((h,p)=>{
   uint id;GetWindowThreadProcessId(h,out id);RECT r;
   if(processes.Contains(id)&&IsWindowVisible(h)&&GetClientRect(h,out r)&&r.R>160&&r.B>90){
    var text=new System.Text.StringBuilder(512);GetWindowText(h,text,text.Capacity);
    choices.Add(new EmulatorChoice{Handle=h,Pid=id,Title=text.Length==0?"MuMu 模拟器":text.ToString()});
   }return true;
  },IntPtr.Zero);
  if(choices.Count==0){MessageBox.Show(this,"未找到 MuMu 游戏窗口。请启动模拟器、打开游戏并退出最小化后重试。","连接 MuMu");return;}
  EmulatorChoice selected=choices[0];
  if(choices.Count>1)using(var dialog=new Form{Text="选择 MuMu 窗口",ClientSize=new Size(520,240),StartPosition=FormStartPosition.CenterParent,MinimizeBox=false,MaximizeBox=false}){
   var list=new ListBox{Dock=DockStyle.Fill};foreach(var choice in choices)list.Items.Add(choice);list.SelectedIndex=0;
   var ok=new Button{Text="连接所选窗口",Dock=DockStyle.Bottom,Height=36,DialogResult=DialogResult.OK};
   dialog.Controls.Add(list);dialog.Controls.Add(ok);dialog.AcceptButton=ok;
   if(dialog.ShowDialog(this)!=DialogResult.OK)return;selected=(EmulatorChoice)list.SelectedItem;
  }
  target=selected.Handle;owner=selected.Pid;emulator=true;paused=false;sourceLabel.Text="MuMu · 点击拖动";picture.Cursor=Cursors.Hand;
  picture.Visible=false;var old=picture.Image;picture.Image=null;if(old!=null)old.Dispose();
  hide.Enabled=true;hide.Text="嵌入游戏窗口";
  fpsClock.Restart();displayedFrames=0;measuredFps=0;
  status.Text="已连接 MuMu，支持截图预览、点击拖动；进入秘密商店后可开始自动购买。";
 }
 public string BaseDirectory=AppDomain.CurrentDomain.BaseDirectory;
 public int SourceWidth=1280,SourceHeight=720;
 public bool ShopRunning {get;set;}
 public long GameWindowHandle {get{return SameWindow()?target.ToInt64():0;}}
 public bool IsMuMu {get{return emulator;}}
 public bool CanStartShop {get{return !clickPending&&!windowBusy&&(!emulator||SameWindow());}}
 public bool IsDockedOrBusy {get{return emulator||sourceParked||windowBusy;}}
 public bool CanCloseHost(){if(clickPending){EndPreview();return false;}if(ShopRunning||windowBusy)return false;if(sourceParked){Restore();return false;}return true;} [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr h,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
 bool clickPending;
 public static bool MapPreviewPoint(Point point,Size viewport,Size source,out Point mapped){
  mapped=Point.Empty;if(source.Width<=0||source.Height<=0||viewport.Width<=0||viewport.Height<=0)return false;
  double scale=Math.Min((double)viewport.Width/source.Width,(double)viewport.Height/source.Height);
  int width=Math.Max(1,(int)Math.Round(source.Width*scale)),height=Math.Max(1,(int)Math.Round(source.Height*scale));
  int left=(viewport.Width-width)/2,top=(viewport.Height-height)/2;
  if(point.X<left||point.Y<top||point.X>=left+width||point.Y>=top+height)return false;
  mapped=new Point(Math.Min(source.Width-1,(int)((point.X-left)*(double)source.Width/width)),Math.Min(source.Height-1,(int)((point.Y-top)*(double)source.Height/height)));return true;
 }
 readonly object dragSync=new object(); Point dragPoint; bool dragEnded=true;
 void MovePreview(MouseEventArgs e){
  if(!clickPending||picture.Image==null)return;
  Point mapped;
  if(MapPreviewPoint(e.Location,picture.ClientSize,picture.Image.Size,out mapped))lock(dragSync){dragPoint=mapped;}
 }
 void EndPreview(){lock(dragSync){dragEnded=true;}picture.Capture=false;}
 [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr parent,Point p,uint flags);
 [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from,IntPtr to,ref Point p,uint count);
 public static IntPtr InputChild(IntPtr root,Point point){
  IntPtr current=root;
  for(int i=0;i<20;i++){
   Point local=point;MapWindowPoints(root,current,ref local,1);
   IntPtr child=ChildWindowFromPointEx(current,local,7);
   if(child==IntPtr.Zero||child==current)break;
   current=child;
  }
  return current;
 }
 bool DragNative(IntPtr window,Point start,Size source){
  IntPtr previous=SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(window));
  if(previous==IntPtr.Zero)return false;
  Point last=start;bool pressed=false;IntPtr receiver=emulator?InputChild(window,start):window;
  Func<uint,int,Point,bool> send=(msg,buttons,p)=>{IntPtr result;if(!IsWindow(receiver))return false;MapWindowPoints(window,receiver,ref p,1);return SendMessageTimeout(receiver,msg,new IntPtr(buttons),new IntPtr((p.Y<<16)|(p.X&65535)),2,500,out result)!=IntPtr.Zero;};
  try{
   RECT r;if(!GetClientRect(window,out r)||r.R!=source.Width||r.B!=source.Height)return false;
   if(!send(0x200,0,start))return false;
   pressed=true;if(!send(0x201,1,start))return false;
   var limit=Stopwatch.StartNew();
   while(limit.Elapsed.TotalSeconds<15){
    Point next;bool ended;lock(dragSync){next=dragPoint;ended=dragEnded;}
    if(next!=last){if(!GetClientRect(window,out r)||r.R!=source.Width||r.B!=source.Height)return false;if(!send(0x200,1,next))return false;last=next;}
    if(ended)return true;
    System.Threading.Thread.Sleep(16);
   }
   return false;
  }finally{if(pressed)send(0x202,0,last);SetThreadDpiAwarenessContext(previous);}
 }
 async void BeginPreview(MouseEventArgs e){
  if(windowBusy||e.Button!=MouseButtons.Left||ShopRunning||clickPending||picture.Image==null||!SameWindow())return;
  Point mapped;Size source=picture.Image.Size;
  if(!MapPreviewPoint(e.Location,picture.ClientSize,source,out mapped))return;
  var guard=new System.Threading.Mutex(false,"Local\\EpicSevenShopWorker");bool held=false;
  try{
   try{held=guard.WaitOne(0);}catch(System.Threading.AbandonedMutexException){held=true;}
   if(!held){status.Text="自动刷店运行中，手动操作已暂停。";return;}
   System.Threading.SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
   lock(dragSync){dragPoint=mapped;dragEnded=false;}
   clickPending=true;picture.Capture=true;IntPtr window=target;
   bool ok=await Task.Run(()=>DragNative(window,mapped,source));
   if(!ok)status.Text="手动操作结束或未确认送达，不会自动重试。";
  }catch(Exception ex){status.Text="手动操作失败："+ex.Message;}
  finally{EndPreview();clickPending=false;if(held)guard.ReleaseMutex();guard.Dispose();}
 } PictureBox picture=new SharpPreview(); Label status=new Label(); Button hide=new Button();
 Timer timer=new Timer(); IntPtr target; uint owner; bool closing;
 int targetFps=60; Stopwatch capturePace=Stopwatch.StartNew();
 Stopwatch fpsClock=Stopwatch.StartNew(); int displayedFrames; double measuredFps;
 void CountDisplayedFrame(){
  displayedFrames++;
  if(fpsClock.Elapsed.TotalSeconds>=1){measuredFps=displayedFrames/fpsClock.Elapsed.TotalSeconds;displayedFrames=0;fpsClock.Restart();}
 }
 Task<Bitmap> capture; DateTime captureAt;
 public GamePreview() {
  BackColor=Color.FromArgb(243,244,250);Text="第七史诗 · 截图预览"; ClientSize=new Size(900,560); MinimumSize=new Size(600,400);
  var bar=new FlowLayoutPanel { Dock=DockStyle.Top,Height=44 };
  var platform=new ComboBox {Name="platformSelector",Width=145,DropDownStyle=ComboBoxStyle.DropDownList};
  platform.Items.AddRange(new object[]{"PC STOVE","MuMu 模拟器"});platform.SelectedIndex=0;
  var connect=new Button {Name="connectPlatform",Text="连接",Width=80,Height=34};
  hide.Text="嵌入游戏窗口";hide.Width=190;hide.Height=34;hide.Enabled=false;
  var restore=new Button {Text="显示原游戏",Width=120,Height=34};
  bar.Controls.Add(platform);bar.Controls.Add(connect);bar.Controls.Add(hide);bar.Controls.Add(restore);
  sourceLabel.Visible=false;bar.Controls.Add(sourceLabel);
  status.Visible=false;status.Height=0;status.Text="截图画面显示在助手内。点击连接游戏；支持点击拖动，刷店期间暂停手动操作。";
  picture.MouseDown+=(s,e)=>BeginPreview(e);
  picture.MouseMove+=(s,e)=>MovePreview(e);
  picture.MouseUp+=(s,e)=>{if(e.Button==MouseButtons.Left){MovePreview(e);EndPreview();}};
  picture.MouseCaptureChanged+=(s,e)=>{if(!picture.Capture)lock(dragSync){dragEnded=true;}};
  picture.Cursor=Cursors.Hand;
  picture.Visible=false;picture.Dock=DockStyle.Fill;picture.SizeMode=PictureBoxSizeMode.StretchImage;picture.BackColor=Color.Black;
  Controls.Add(picture);Controls.Add(bar);Controls.Add(status);
  connect.Click+=(s,e)=>{if(platform.SelectedIndex==1)ConnectMuMu();else Connect();}; restore.Click+=(s,e)=>Restore();
  hide.Visible=true;hide.Click+=(s,e)=>ToggleWindow();
  timer.Interval=8;timer.Tick+=(s,e)=>TickCapture();timer.Start();
  FormClosing+=(s,e)=>{if(!CanCloseHost()){e.Cancel=true;return;}closing=true;};
 }
 bool paused=true;
 protected override void Dispose(bool disposing){
  if(disposing&&!closing){closing=true;}
  if(disposing){timer.Stop();timer.Dispose();EndPreview();picture.Visible=false;var old=picture.Image;picture.Image=null;if(old!=null)old.Dispose();
   var pending=capture;capture=null;if(pending!=null)pending.ContinueWith(t=>{if(t.Status==TaskStatus.RanToCompletion&&t.Result!=null)t.Result.Dispose();});}
  base.Dispose(disposing);
 } bool SameWindow(){uint id;return target!=IntPtr.Zero && IsWindow(target) && GetWindowThreadProcessId(target,out id)!=0 && id==owner;}
 void Connect(){
  if(ShopRunning||clickPending||sourceParked||windowBusy)return;
  if(capture!=null){status.Text="上一帧仍在处理中，请稍后连接。";return;}
  picture.Visible=false;var stale=picture.Image;picture.Image=null;if(stale!=null)stale.Dispose();emulator=false;sourceLabel.Text="";picture.Cursor=Cursors.Hand;paused=true;hide.Text="嵌入游戏窗口";  target=IntPtr.Zero;hide.Enabled=false;int count=0;
  foreach(var p in Process.GetProcessesByName("EpicSeven")){using(p){if(p.MainWindowHandle!=IntPtr.Zero){target=p.MainWindowHandle;count++;}}}
  if(count!=1){target=IntPtr.Zero;status.Text="未找到唯一游戏窗口，请打开游戏并退出最小化后重试。";return;}
  GetWindowThreadProcessId(target,out owner);
  if(!IsWindowVisible(target)||IsIconic(target)){target=IntPtr.Zero;status.Text="请先显示游戏窗口，再连接。";return;}
  fpsClock.Restart();displayedFrames=0;measuredFps=0;hide.Enabled=!windowBusy;status.Text="已连接，点击“嵌入游戏窗口”显示截图预览。";
 }
 [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 static Bitmap Grab(IntPtr h){
  IntPtr context=GetWindowDpiAwarenessContext(h);
  if(context==IntPtr.Zero)return null;
  IntPtr previous=SetThreadDpiAwarenessContext(context);
  if(previous==IntPtr.Zero)return null;
  try{return GrabAligned(h);}finally{SetThreadDpiAwarenessContext(previous);}
 }
 static Bitmap GrabAligned(IntPtr h){RECT r;if(!GetClientRect(h,out r)||r.R<=0||r.B<=0||r.R>7680||r.B>4320)return null;
  var b=new Bitmap(r.R,r.B);bool ok=false;try{using(var g=Graphics.FromImage(b)){var dc=g.GetHdc();try{ok=PrintWindow(h,dc,3);}finally{g.ReleaseHdc(dc);}}if(!ok){b.Dispose();return null;}return b;}catch{b.Dispose();return null;}}
 void TickCapture(){
  if(closing)return;
  if(!SameWindow()){
   picture.Visible=false;
   var stale=picture.Image;picture.Image=null;if(stale!=null)stale.Dispose();
   if(capture!=null&&capture.IsCompleted){if(capture.Status==TaskStatus.RanToCompletion&&capture.Result!=null)capture.Result.Dispose();capture=null;}
   return;
  }
  if(capture!=null){
   if(!capture.IsCompleted){if((DateTime.UtcNow-captureAt).TotalSeconds>3)status.Text="游戏捕获暂未响应；预览正在等待，不会重复启动捕获。";return;}
   Bitmap b=capture.Status==TaskStatus.RanToCompletion?capture.Result:null;capture=null;
   if(b==null){paused=true;hide.Text="嵌入游戏窗口";status.Text="捕获失败，请确认游戏正常显示且未最小化。";return;}
   var old=picture.Image;picture.Image=b;picture.Visible=true;if(old!=null)old.Dispose();CountDisplayedFrame();((SharpPreview)picture).FramesPerSecond=measuredFps;picture.Invalidate();hide.Enabled=!windowBusy;
   status.Text="截图预览 · "+b.Width+"×"+b.Height+" · 实际 "+measuredFps.ToString("0.0")+" FPS · 仅内存更新 · 可点击拖动";
  }
  if(paused||!SameWindow()||IsIconic(target))return;
    int delay=Math.Max(0,(int)Math.Ceiling(1000.0/targetFps-capturePace.Elapsed.TotalMilliseconds));
  IntPtr window=target;captureAt=DateTime.UtcNow;
  capture=Task.Run(async ()=>{
   if(delay>0)await Task.Delay(delay).ConfigureAwait(false);
   capturePace.Restart();return Grab(window);
  });
  var pending=capture;
  pending.ContinueWith(done=>{
   try{if(!closing&&!IsDisposed&&IsHandleCreated)BeginInvoke(new Action(()=>{if(!closing&&capture==pending)TickCapture();}));}
   catch(InvalidOperationException){}
  });
 }
}public class SharpPreview : PictureBox {
 public double FramesPerSecond;
 protected override void OnPaint(PaintEventArgs e) {
  e.Graphics.Clear(BackColor);
  if(Image==null)return;
  e.Graphics.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.Bilinear;
  e.Graphics.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
  using(var attributes=new System.Drawing.Imaging.ImageAttributes()) {
   attributes.SetWrapMode(System.Drawing.Drawing2D.WrapMode.TileFlipXY);
      double scale=Math.Min((double)ClientSize.Width/Image.Width,(double)ClientSize.Height/Image.Height);
   int width=Math.Max(1,(int)Math.Round(Image.Width*scale));
   int height=Math.Max(1,(int)Math.Round(Image.Height*scale));
   Rectangle destination=new Rectangle((ClientSize.Width-width)/2,(ClientSize.Height-height)/2,width,height);
   e.Graphics.DrawImage(Image,destination,0,0,Image.Width,Image.Height,GraphicsUnit.Pixel,attributes);
   string fps=FramesPerSecond.ToString("0.0")+" FPS";
   using(var font=new Font("Segoe UI",11,FontStyle.Bold))
   using(var background=new SolidBrush(Color.FromArgb(165,0,0,0))){
    SizeF size=e.Graphics.MeasureString(fps,font);
    float x=destination.Left+8,y=destination.Top+8;
    e.Graphics.FillRectangle(background,x-3,y-2,size.Width+6,size.Height+4);
    e.Graphics.DrawString(fps,font,Brushes.White,x,y);
   }
  }
 }
}