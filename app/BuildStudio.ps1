param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
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
<DockPanel Grid.Row="4" Margin="0,12"><Button Name="Add" Content="Add item" DockPanel.Dock="Right"/><ComboBox Name="Search" IsEditable="True" IsTextSearchEnabled="True" MaxDropDownHeight="260"/></DockPanel>
<TextBox Name="Report" Grid.Row="5" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
<TextBlock Name="Status" Grid.Row="6" TextWrapping="Wrap" Foreground="#d8b56a" Margin="0,12,0,0" Text="Open a preset. Edits save and resolve automatically."/>
</Grid></Window>
'@
$w=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
foreach($n in 'New','Open','Save','Title','Stats','Items','Add','Search','Report','Status'){Set-Variable -Name $n -Value $w.FindName($n)}
$inputs=@{}
foreach($key in 'vig','mind','end','str','dex','int','fai','arc'){
 $s=New-Object Windows.Controls.StackPanel; $s.Margin='0,0,16,0'; $l=New-Object Windows.Controls.TextBlock; $l.Text=$key.ToUpper(); $t=New-Object Windows.Controls.TextBox; $t.Width=75
 [void]$s.Children.Add($l);[void]$s.Children.Add($t);[void]$Stats.Children.Add($s);$inputs[$key]=$t
}
$Search.ItemsSource=@($catalog|ForEach-Object {$_.name}|Sort-Object -Unique)
$rows=New-Object 'System.Collections.ObjectModel.ObservableCollection[object]';$Items.ItemsSource=$rows
$script:last='';$script:active=$false;$script:source=$null
function Save-Editor {
 if(-not $script:active){return}
 $a=@{};foreach($k in $inputs.Keys){$a[$k]=$inputs[$k].Text}
 $b=[pscustomobject]@{schemaVersion='2.0';name=$Title.Text;source=$script:source;attributes=$a;items=@($rows|ForEach-Object {$_})}
 $json=$b|ConvertTo-Json -Depth 12;if($json -eq $script:last){return}
 $plan=Resolve-BuildPlan $b $catalog
 $safe=($b.name -replace '[^\w .-]','_').Trim('. ');if(-not $safe){$safe='New build'}
 $path=Join-Path $dir ($safe+'.json');if(Test-Path $path){Copy-Item -LiteralPath $path -Destination ($path+'.previous') -Force}
 [IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding $true))
 [IO.File]::WriteAllText((Join-Path $dir ($safe+'.plan.json')),($plan|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding $true))
 $Report.Text=(@($plan.items|ForEach-Object {'{0}: ID {1}, upgrade +{2}, quantity {3}' -f $_.name,$_.itemId,$_.upgrade,$_.quantity})+@($plan.issues)) -join "`r`n"
 $script:last=$json
 $Status.Text='Saved and resolved. Game writes unavailable: game 2.2.0.0 / table 2.7.0.0. Nothing applied to game.'
}
$Open.Add_Click({try{$d=New-Object Microsoft.Win32.OpenFileDialog;$d.InitialDirectory=$dir;$d.Filter='Preset JSON|*.json';if($d.ShowDialog()){$b=Get-Content -LiteralPath $d.FileName -Raw -Encoding UTF8|ConvertFrom-Json;$Title.Text=$b.name;$rows.Clear();foreach($i in @(ConvertTo-BuildItems $b)){$rows.Add($i)};foreach($k in $inputs.Keys){$inputs[$k].Text=[string]$b.attributes.$k};$script:source=$b.source;$script:last='';$script:active=$true;Save-Editor}}catch{$Status.Text=$_.Exception.Message}})
$New.Add_Click({$rows.Clear();$Title.Text='New build';foreach($t in $inputs.Values){$t.Text=''};$script:source=$null;$script:last='';$script:active=$true})
$Add.Add_Click({$m=@($catalog|Where-Object {$_.name -ieq $Search.Text});if($m.Count -eq 1){$rows.Add([pscustomobject]@{category=$m[0].category;name=$m[0].name;upgrade=0;quantity=1;ashOfWar=''});$script:active=$true}else{$Status.Text='Select an exact catalog item.'}})
$Save.Add_Click({try{[void]$Items.CommitEdit();[void]$Items.CommitEdit();Save-Editor}catch{$Status.Text=$_.Exception.Message}})
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds(2);$timer.Add_Tick({try{if(-not $Items.IsKeyboardFocusWithin){Save-Editor}}catch{$Status.Text=$_.Exception.Message}});$w.Add_Closed({$timer.Stop()})
if($CheckOnly){'UI XAML and catalog loaded successfully';$w.Close();return}
$timer.Start();[void]$w.ShowDialog()
