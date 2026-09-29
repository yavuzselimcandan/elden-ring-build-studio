param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
. (Join-Path $PSScriptRoot 'backend.ps1')
$root=$PSScriptRoot; $catalog=Get-BuildCatalog $root; $dir=Join-Path $root 'configs'
New-Item -ItemType Directory -Force -Path $dir|Out-Null
[xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Elden Ring Build Studio" Width="1100" Height="780" Background="#101216" Foreground="#dddddd" WindowStartupLocation="CenterScreen">
<Window.Resources><Style TargetType="Button"><Setter Property="Background" Value="#242830"/><Setter Property="Foreground" Value="#eddbad"/><Setter Property="Margin" Value="6"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="10" Padding="16,10"><Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="3" Opacity="0.4"/></Border.Effect><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style><Style TargetType="TextBox"><Setter Property="Background" Value="#0c0e11"/><Setter Property="Foreground" Value="#eeeeee"/><Setter Property="BorderBrush" Value="#353a43"/><Setter Property="Padding" Value="9"/></Style></Window.Resources>
<Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="130"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="BUILD STUDIO" FontSize="28" Foreground="#d8b56a" Margin="0,0,0,16"/>
<DockPanel Grid.Row="1"><StackPanel Orientation="Horizontal" DockPanel.Dock="Right"><Button Name="New" Content="New"/><Button Name="Open" Content="Open preset"/><Button Name="Save" Content="Save"/></StackPanel><TextBox Name="Title" Text="New build"/></DockPanel>
<WrapPanel Name="Stats" Grid.Row="2" Margin="0,15"/>
<DataGrid Name="Items" Grid.Row="3" AutoGenerateColumns="False" CanUserAddRows="False" Background="#15191f" Foreground="#dddddd" RowBackground="#1b2027" AlternatingRowBackground="#242a33" GridLinesVisibility="None" HeadersVisibility="Column"><DataGrid.Resources><Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#303741"/><Setter Property="Foreground" Value="#d8b56a"/><Setter Property="Padding" Value="8"/></Style></DataGrid.Resources><DataGrid.Columns><DataGridTextColumn Header="Category" Binding="{Binding category}" Width="80"/><DataGridTextColumn Header="Item" Binding="{Binding name}" Width="*"/><DataGridTextColumn Header="Upgrade" Binding="{Binding upgrade}" Width="65"/><DataGridTextColumn Header="Quantity" Binding="{Binding quantity}" Width="65"/><DataGridTextColumn Header="Ash of War" Binding="{Binding ashOfWar}" Width="170"/></DataGrid.Columns></DataGrid>
<DockPanel Grid.Row="4" Margin="0,12"><StackPanel Orientation="Horizontal" DockPanel.Dock="Right"><Button Name="Inventory" Content="Refresh inventory"/><Button Name="Remove" Content="Remove selected"/><Button Name="Add" Content="Add item"/></StackPanel><ComboBox Name="Search" IsEditable="True" IsTextSearchEnabled="True" MaxDropDownHeight="260"/></DockPanel>
<TextBox Name="Report" Grid.Row="5" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
<TextBlock Name="Status" Grid.Row="6" TextWrapping="Wrap" Foreground="#d8b56a" Margin="0,12,0,0" Text="Open a preset. Edits save and resolve automatically."/>
</Grid></Window>
'@
$w=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
foreach($n in 'New','Open','Save','Title','Stats','Items','Add','Remove','Inventory','Search','Report','Status'){Set-Variable -Name $n -Value $w.FindName($n)}
$inputs=@{}
foreach($key in 'vig','mind','end','str','dex','int','fai','arc'){
 $s=New-Object Windows.Controls.StackPanel; $s.Margin='0,0,16,0'; $l=New-Object Windows.Controls.TextBlock; $l.Text=$key.ToUpper(); $t=New-Object Windows.Controls.TextBox; $t.Width=75
 [void]$s.Children.Add($l);[void]$s.Children.Add($t);[void]$Stats.Children.Add($s);$inputs[$key]=$t
}
$Search.ItemsSource=@($catalog|ForEach-Object {$_.name}|Sort-Object -Unique)
$rows=New-Object 'System.Collections.ObjectModel.ObservableCollection[object]';$Items.ItemsSource=$rows
$script:last='';$script:active=$false;$script:source=$null;$script:dirty=$false;$script:changedAt=[datetime]::MinValue;$script:lastApplied='';$script:lastPlan=$null;$script:planReport='';$script:inventoryReport='';$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingSent=$false;$script:pendingRequestId=$null;$script:lastBackendStartPid=$null;$script:blocked=$false
function Set-Dirty { $script:dirty=$true;$script:changedAt=[datetime]::UtcNow }
function Show-Plan($plan) {
 $script:planReport=(@($plan.items|ForEach-Object {if($_.itemId){'{0}: ID {1}, upgrade +{2}, quantity {3}' -f $_.name,$_.itemId,$_.upgrade,$_.quantity}else{'{0}: unresolved' -f $_.name}})+@($plan.issues)) -join "`r`n"; $Report.Text=($script:planReport,$script:inventoryReport|Where-Object {$_}) -join "`r`n`r`n"
}
function Show-Inventory {
 $path=Join-Path $root 'runtime\inventory-read.txt';if(-not (Test-Path $path)){return}
 $lines=Get-Content -LiteralPath $path -Encoding UTF8;$out=New-Object System.Collections.Generic.List[string]
 foreach($line in $lines){if($line -match '^entry\d+=rawID:(\d+),quantity:(\d+)$'){$raw=[uint32]$Matches[1];$q=[int]$Matches[2];$kind=$raw -shr 28;$id=$raw -band 0x0FFFFFFF;$category=@{0='weapon';1='armor';2='talisman';4='goods';8='ash'}[$kind];$upgrade=if($kind -eq 0){$id%100}else{0};$catalogMatch=@($catalog|Where-Object {[string]$_.category -eq $category -and [long]$_.itemId -eq $id});$name=if($catalogMatch.Count -eq 1){$catalogMatch[0].name}else{'(catalog name unavailable)'};[void]$out.Add(('{0}: raw {1}, ID {2}, +{3}, qty {4}' -f $name,$raw,$id,$upgrade,$q))}}
 if($out.Count){$script:inventoryReport=('--- Inventory read-only ({0} entries) ---' -f $out.Count)+"`r`n"+($out -join "`r`n");$Report.Text=($script:planReport,$script:inventoryReport|Where-Object {$_}) -join "`r`n`r`n"}
}
function Apply-Pending {
 if(-not $script:pendingPlan -or $script:pendingJson -eq $script:lastApplied){return}
 if($script:pendingSent){
  $resultPath=Join-Path $root 'runtime\result.txt'
  if(Test-Path $resultPath){$resultText=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8;$resultRequest=if($resultText -match '(?m)^requestId=([a-zA-Z0-9-]+)'){[string]$Matches[1]}else{$null};if($resultRequest -ne $script:pendingRequestId){return};if($resultText -match '(?m)^ERROR:'){ $script:pendingSent=$false;$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingRequestId=$null;$Status.Text=$resultText.Trim()}elseif($resultText -match '(?m)^PARTIAL:'){ $script:lastApplied=$script:pendingJson;$script:pendingSent=$false;$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingRequestId=$null;$Status.Text=$resultText.Trim()}elseif($resultText -match '(?m)^(?:OK:\s*APPLIED\b|APPLIED:)'){ $script:lastApplied=$script:pendingJson;$script:pendingSent=$false;$script:pendingJson='';$script:pendingPlan=$null;$script:pendingRequestId=$null;if($script:pendingItems.Count){$Status.Text='PARTIAL: applied supported items; pending: '+($script:pendingItems -join ', ')}else{$Status.Text=$resultText.Trim()};$script:pendingItems=@()}}
  return
 }
 try {
   $state=Get-BuildBackendStatus -Root $root
   if(-not $state.ready -and $state.gameRunning -and -not $state.eacRunning -and (Get-Command Start-BuildBackend -ErrorAction SilentlyContinue)){$game=Get-Process -Name eldenring -ErrorAction SilentlyContinue;if($game -and $game.Id -ne $script:lastBackendStartPid){Start-BuildBackend -Root $root;$script:lastBackendStartPid=$game.Id}}
   if(-not $state.ready){$Status.Text=$state.message;return}
  $result=Invoke-BuildPlan -Plan $script:pendingPlan -Root $root
  if($result.ok -and $result.applied){$script:lastApplied=$script:pendingJson;$script:pendingJson='';$script:pendingPlan=$null;$Status.Text=$result.message}
  elseif($result.pending){$script:pendingSent=$true;$script:pendingRequestId=[string]$result.requestId;$script:pendingItems=@($result.pendingItems);$Status.Text=$result.message}
  else {$script:pendingSent=$false;$script:pendingRequestId=$null;$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$Status.Text=if($result.message){$result.message}else{'Build was not applied.'}}
 } catch {$Status.Text=$_.Exception.Message}
}
function Save-Editor {
 if(-not $script:active){return}
 $a=@{};foreach($k in $inputs.Keys){$a[$k]=$inputs[$k].Text}
 $b=[pscustomobject]@{schemaVersion='2.0';name=$Title.Text;source=$script:source;attributes=$a;items=@($rows|ForEach-Object {$_})}
 $json=$b|ConvertTo-Json -Depth 12;if($json -eq $script:last){return}
 $plan=Resolve-BuildPlan $b $catalog
 Show-Plan $plan
 $isBlank=(@($rows).Count -eq 0 -and (@($a.Values|Where-Object {[string]$_ -ne ''}).Count -eq 0) -and $Title.Text -eq 'New build')
 if($isBlank){$script:last=$json;$script:dirty=$false;$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingSent=$false;$script:pendingRequestId=$null;$Status.Text='New build. Add an item or stat to begin.';return}
 $safe=($b.name -replace '[^\w .-]','_').Trim('. ');if(-not $safe){$safe='New build'}
 $path=Join-Path $dir ($safe+'.json');if(Test-Path $path){Copy-Item -LiteralPath $path -Destination ($path+'.previous') -Force}
 [IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding $true))
 [IO.File]::WriteAllText((Join-Path $dir ($safe+'.plan.json')),($plan|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding $true))
 $script:last=$json;$script:dirty=$false;$script:lastPlan=$plan
  $attrIssues=@($plan.issues|Where-Object {$_ -match '^Invalid attribute'});if($attrIssues.Count){$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingSent=$false;$script:pendingRequestId=$null;$script:blocked=$true;$Status.Text='Saved. Fix invalid attributes before applying.';return}
 $script:blocked=$false
 $script:pendingJson=$json;$script:pendingPlan=[pscustomobject]@{schemaVersion=$plan.schemaVersion;name=$plan.name;attributes=$a;items=@($plan.items);issues=@($plan.issues)};$script:pendingItems=@($plan.items|Where-Object {$null -eq $_.itemId}|ForEach-Object name);$script:pendingSent=$false;$script:pendingRequestId=$null
 Apply-Pending
}
$Open.Add_Click({try{$d=New-Object Microsoft.Win32.OpenFileDialog;$d.InitialDirectory=$dir;$d.Filter='Preset JSON|*.json';if($d.ShowDialog()){$b=Get-Content -LiteralPath $d.FileName -Raw -Encoding UTF8|ConvertFrom-Json;$Title.Text=$b.name;$rows.Clear();foreach($i in @(ConvertTo-BuildItems $b)){$rows.Add($i)};foreach($k in $inputs.Keys){$inputs[$k].Text=[string]$b.attributes.$k};$script:source=$b.source;$script:last='';$script:lastApplied='';$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingSent=$false;$script:pendingRequestId=$null;$script:blocked=$false;$script:planReport='';$script:inventoryReport='';$script:active=$true;$script:dirty=$true;Save-Editor}}catch{$Status.Text=$_.Exception.Message}})
$New.Add_Click({$rows.Clear();$Title.Text='New build';foreach($t in $inputs.Values){$t.Text=''};$script:source=$null;$script:last='';$script:lastApplied='';$script:lastPlan=$null;$script:planReport='';$script:inventoryReport='';$script:pendingJson='';$script:pendingPlan=$null;$script:pendingItems=@();$script:pendingSent=$false;$script:pendingRequestId=$null;$script:blocked=$false;$script:dirty=$false;$script:active=$true;$Report.Clear();$Status.Text='New build. Add an item or stat to begin.'})
$Add.Add_Click({$m=@($catalog|Where-Object {$_.name -ieq $Search.Text});if($m.Count -eq 1){$rows.Add([pscustomobject]@{category=$m[0].category;name=$m[0].name;upgrade=0;quantity=1;ashOfWar=''});$script:active=$true;Set-Dirty}else{$Status.Text='Select an exact catalog item.'}})
$Remove.Add_Click({if($null -ne $Items.SelectedItem){$rows.Remove($Items.SelectedItem);Set-Dirty;$Status.Text='Removed selected item.'}})
$Inventory.Add_Click({Show-Inventory;$Status.Text='Inventory read-only snapshot loaded; no game changes were made.'})
$Save.Add_Click({try{[void]$Items.CommitEdit();Save-Editor}catch{$Status.Text=$_.Exception.Message}})
foreach($t in $inputs.Values){$t.Add_TextChanged({Set-Dirty})};$Title.Add_TextChanged({Set-Dirty});$Items.Add_RowEditEnding({Set-Dirty})
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(150);$timer.Add_Tick({try{if($script:active -and $script:dirty -and (([datetime]::UtcNow-$script:changedAt).TotalMilliseconds -ge 700) -and -not $Items.IsKeyboardFocusWithin){Save-Editor}}catch{$Status.Text=$_.Exception.Message}})
$poll=New-Object Windows.Threading.DispatcherTimer;$poll.Interval=[TimeSpan]::FromSeconds(2);$poll.Add_Tick({try{if($script:pendingPlan -and -not $script:dirty){Apply-Pending}elseif(-not $script:blocked -and -not $script:dirty){$s=Get-BuildBackendStatus -Root $root;if(-not $s.ready){$Status.Text=$s.message}}}catch{}});$w.Add_Closed({$timer.Stop();$poll.Stop()})
if($CheckOnly){'UI XAML and catalog loaded successfully';$w.Close();return}
$timer.Start();$poll.Start();[void]$w.ShowDialog()
