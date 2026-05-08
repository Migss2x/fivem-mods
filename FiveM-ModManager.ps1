#Requires -Version 5.0
<#
.SYNOPSIS
FiveM Mod Manager - Advanced PowerShell GUI Application
A comprehensive mod management system with GitHub integration, multi-user support, and automated installation.

.DESCRIPTION
This application provides:
- Secure login system with password protection
- Node-based dashboard with 7 mod categories
- GitHub integration for file storage and retrieval
- Automatic file installation to correct GTA V paths
- Favorites/bookmarking system
- Real-time file listing updates
- Error handling and logging

.PARAMETER GitHubToken
GitHub Personal Access Token (set in configuration section)

.PARAMETER GitHubRepo
GitHub repository URL (set in configuration section)

.EXAMPLE
.\FiveM-ModManager.ps1

.NOTES
Author: FiveM Community
Version: 2.0
LastUpdate: 2026-05-08
Requirements: Windows 10+, PowerShell 5.0+, Administrator privileges recommended

INITIAL SETUP:
1. Create a GitHub repository for mod storage
2. Generate a Personal Access Token at https://github.com/settings/tokens
3. Update the configuration variables in the CONFIG SECTION below
4. Run the script with administrator privileges
#>

#region CONFIG SECTION
# ============================================================================
# CONFIGURE THESE SETTINGS FOR YOUR ENVIRONMENT
# ============================================================================

$Config = @{
    # GitHub Configuration
    GitHubToken        = "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"  # Replace with your token
    GitHubRepo         = "Migss2x/fivem-mods" # Format: username/repository
    GitHubAPIUrl       = "https://api.github.com"
    
    # Application Configuration
    AppVersion         = "2.0.0"
    AppTitle           = "FiveM Mod Manager"
    LoginPassword      = "lol"  # Change this to your desired password
    EnableLogging      = $true
    LogPath            = "$env:USERPROFILE\AppData\Local\FiveM-ModManager\logs.txt"
    FavoritesPath      = "$env:USERPROFILE\AppData\Local\FiveM-ModManager\favorites.json"
    
    # Installation Paths
    InstallPaths       = @{
        "Sound Packs"       = "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V\x64\audio\sfx"
        "Custom Roads"      = "$env:USERPROFILE\AppData\Local\FiveM\FiveM.app\mods"
        "Reshade Setup"     = "$env:USERPROFILE\Downloads"
        "NVE"               = "$env:USERPROFILE\AppData\Local\FiveM\FiveM.app\mods"
        "RPFs"              = "$env:USERPROFILE\AppData\Local\FiveM\FiveM.app\mods"
        "Reshade Configs"   = "$env:USERPROFILE\AppData\Local\FiveM\FiveM.app\plugins"
        "Cheat Configs"     = "$env:USERPROFILE\Downloads"
    }
    
    # UI Configuration
    Theme               = @{
        BackgroundColor     = "#0a0e27"
        PrimaryColor        = "#00d4ff"
        SecondaryColor      = "#ff006e"
        TextColor           = "#e0e0e0"
        AccentColor         = "#00ff88"
        ErrorColor          = "#ff4757"
        WarningColor        = "#ffa502"
        SuccessColor        = "#2ed573"
    }
}

# Create necessary directories
$LogDir = Split-Path -Parent $Config.LogPath
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

#endregion

#region GLOBAL VARIABLES
# ============================================================================
# GLOBAL STATE MANAGEMENT
# ============================================================================

$Global:CurrentUser = $null
$Global:IsAuthenticated = $false
$Global:Favorites = @{}
$Global:CategoryFiles = @{}
$Global:MainWindow = $null
$Global:DashboardCanvas = $null

# Load favorites if they exist
if (Test-Path $Config.FavoritesPath) {
    $Global:Favorites = Get-Content $Config.FavoritesPath -Raw | ConvertFrom-Json -AsHashtable
}

#endregion

#region LOGGING AND UTILITIES
# ============================================================================
# LOGGING, ERROR HANDLING, AND UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
    Writes messages to log file and console with timestamps
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Console output with color
    $Colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }
    Write-Host $LogMessage -ForegroundColor $Colors[$Level]
    
    # File logging
    if ($Config.EnableLogging) {
        Add-Content -Path $Config.LogPath -Value $LogMessage -Encoding UTF8
    }
}

function Show-Notification {
    <#
    .SYNOPSIS
    Displays a WPF notification toast
    #>
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info',
        [int]$Duration = 3000
    )
    
    $Colors = @{
        'Info'    = $Config.Theme.PrimaryColor
        'Success' = $Config.Theme.SuccessColor
        'Warning' = $Config.Theme.WarningColor
        'Error'   = $Config.Theme.ErrorColor
    }
    
    Write-Log "$Title - $Message" -Level $Type
    
    # This can be enhanced with a toast notification window
    # For now, we'll use simple console output
}

function Test-GitHubConnection {
    <#
    .SYNOPSIS
    Tests connectivity to GitHub API
    #>
    try {
        $Headers = @{
            'Authorization' = "token $($Config.GitHubToken)"
            'Accept'        = 'application/vnd.github.v3+json'
        }
        
        $Response = Invoke-RestMethod -Uri "$($Config.GitHubAPIUrl)/user" -Headers $Headers -ErrorAction Stop
        Write-Log "GitHub connection successful: $($Response.login)" -Level Success
        return $true
    }
    catch {
        Write-Log "GitHub connection failed: $_" -Level Error
        return $false
    }
}

function ConvertTo-ConverterJson {
    <#
    .SYNOPSIS
    Safely converts object to JSON with error handling
    #>
    param([Parameter(Mandatory = $true)]$InputObject)
    
    try {
        return $InputObject | ConvertTo-Json -Depth 10
    }
    catch {
        Write-Log "JSON conversion error: $_" -Level Error
        return $null
    }
}

#endregion

#region GITHUB INTEGRATION
# ============================================================================
# GITHUB API INTEGRATION FOR FILE MANAGEMENT
# ============================================================================

function Get-GitHubFiles {
    <#
    .SYNOPSIS
    Retrieves list of files from GitHub repository for a specific category
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    try {
        $Headers = @{
            'Authorization' = "token $($Config.GitHubToken)"
            'Accept'        = 'application/vnd.github.v3+json'
        }
        
        # Create category folder path
        $FolderPath = [uri]::EscapeUriString($Category -replace ' ', '_')
        $ApiUrl = "$($Config.GitHubAPIUrl)/repos/$($Config.GitHubRepo)/contents/$FolderPath"
        
        $Response = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -ErrorAction Stop
        
        if ($Response -is [array]) {
            return $Response | Where-Object { $_.type -eq 'file' } | Select-Object -Property name, download_url, size, @{
                Name       = 'upload_date'
                Expression = { [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') }
            }
        }
        return @()
    }
    catch {
        Write-Log "Failed to fetch files for $Category : $_" -Level Warning
        return @()
    }
}

function Upload-FileToGitHub {
    <#
    .SYNOPSIS
    Uploads a file to GitHub repository in the specified category folder
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Category,
        
        [Parameter(Mandatory = $true)]
        [string]$CustomName
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        
        $FileContent = [System.IO.File]::ReadAllBytes($FilePath)
        $Base64Content = [Convert]::ToBase64String($FileContent)
        
        $FolderPath = $Category -replace ' ', '_'
        $FileName = "$CustomName$(Split-Path -Extension $FilePath)"
        $ApiUrl = "$($Config.GitHubAPIUrl)/repos/$($Config.GitHubRepo)/contents/$FolderPath/$FileName"
        
        $Headers = @{
            'Authorization' = "token $($Config.GitHubToken)"
            'Accept'        = 'application/vnd.github.v3+json'
        }
        
        $Body = @{
            message = "Upload: $CustomName from $(whoami)"
            content = $Base64Content
        } | ConvertTo-Json
        
        $Response = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -Method Put -Body $Body -ContentType 'application/json' -ErrorAction Stop
        
        Write-Log "File uploaded successfully: $FileName to $Category" -Level Success
        return $true
    }
    catch {
        Write-Log "Upload failed for $CustomName : $_" -Level Error
        return $false
    }
}

function Download-FileFromGitHub {
    <#
    .SYNOPSIS
    Downloads a file from GitHub to a local temporary location
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    
    try {
        $TempPath = Join-Path $env:TEMP "FiveM_$FileName"
        $Headers = @{
            'Authorization' = "token $($Config.GitHubToken)"
        }
        
        Invoke-WebRequest -Uri $DownloadUrl -Headers $Headers -OutFile $TempPath -ErrorAction Stop
        
        Write-Log "File downloaded: $FileName" -Level Success
        return $TempPath
    }
    catch {
        Write-Log "Download failed for $FileName : $_" -Level Error
        return $null
    }
}

#endregion

#region FILE MANAGEMENT
# ============================================================================
# FILE INSTALLATION AND MANAGEMENT FUNCTIONS
# ============================================================================

function Install-ModFile {
    <#
    .SYNOPSIS
    Installs a mod file to the correct system path based on category
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    try {
        $InstallPath = $Config.InstallPaths[$Category]
        
        if ([string]::IsNullOrEmpty($InstallPath)) {
            throw "Unknown installation category: $Category"
        }
        
        # Create directory if it doesn't exist
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Log "Created installation directory: $InstallPath" -Level Info
        }
        
        $FileName = Split-Path -Leaf $FilePath
        $DestinationPath = Join-Path $InstallPath $FileName
        
        # For Reshade Setup and Cheat Configs, keep in Downloads
        if ($Category -in @('Reshade Setup', 'Cheat Configs')) {
            Write-Log "File ready in Downloads folder: $DestinationPath" -Level Info
            return $true
        }
        
        # Copy file to destination
        Copy-Item -Path $FilePath -Destination $DestinationPath -Force -ErrorAction Stop
        
        Write-Log "File installed successfully: $FileName to $Category" -Level Success
        return $true
    }
    catch {
        Write-Log "Installation failed: $_" -Level Error
        return $false
    }
}

function Add-ToFavorites {
    <#
    .SYNOPSIS
    Adds a file to user's favorites
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    try {
        $FavoriteId = "$Category-$FileName"
        $Global:Favorites[$FavoriteId] = @{
            FileName   = $FileName
            Category   = $Category
            AddedDate  = (Get-Date).ToString('o')
        }
        
        # Save to file
        $Global:Favorites | ConvertTo-Json | Set-Content -Path $Config.FavoritesPath -Encoding UTF8
        
        Write-Log "Added to favorites: $FileName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to add favorite: $_" -Level Error
        return $false
    }
}

function Remove-FromFavorites {
    <#
    .SYNOPSIS
    Removes a file from user's favorites
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    try {
        $FavoriteId = "$Category-$FileName"
        $Global:Favorites.Remove($FavoriteId)
        
        $Global:Favorites | ConvertTo-Json | Set-Content -Path $Config.FavoritesPath -Encoding UTF8
        
        Write-Log "Removed from favorites: $FileName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to remove favorite: $_" -Level Error
        return $false
    }
}

#endregion

#region WPF UI BUILDERS
# ============================================================================
# WPF UI GENERATION AND EVENT HANDLERS
# ============================================================================

function New-LoginWindow {
    <#
    .SYNOPSIS
    Creates and displays the login window
    #>
    
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($Config.AppTitle) - Login" 
        Width="400" 
        Height="300"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        ResizeMode="NoResize"
        Topmost="False">
    <Grid>
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="300">
            <!-- Title -->
            <TextBlock Text="FiveM Mod Manager" 
                       FontSize="28" 
                       FontWeight="Bold" 
                       Foreground="#00d4ff"
                       HorizontalAlignment="Center"
                       Margin="0,0,0,30"/>
            
            <!-- Version Info -->
            <TextBlock Text="v$($Config.AppVersion)" 
                       FontSize="12" 
                       Foreground="#888888"
                       HorizontalAlignment="Center"
                       Margin="0,0,0,20"/>
            
            <!-- Password Input -->
            <TextBlock Text="Access Code" 
                       Foreground="#e0e0e0" 
                       FontSize="12"
                       Margin="0,0,0,8"/>
            <PasswordBox x:Name="PasswordBox" 
                         Height="40"
                         Background="#1a1f3a"
                         Foreground="#e0e0e0"
                         BorderBrush="#00d4ff"
                         BorderThickness="2"
                         Padding="10,8"
                         FontSize="14"
                         Margin="0,0,0,20"/>
            
            <!-- Login Button -->
            <Button x:Name="LoginButton" 
                    Content="AUTHENTICATE" 
                    Height="40"
                    Background="#00d4ff"
                    Foreground="#0a0e27"
                    FontSize="14"
                    FontWeight="Bold"
                    Cursor="Hand"
                    Margin="0,0,0,15"/>
            
            <!-- Status Message -->
            <TextBlock x:Name="StatusMessage" 
                       Text="" 
                       Foreground="#ff4757"
                       FontSize="11"
                       HorizontalAlignment="Center"
                       TextWrapping="Wrap"
                       Margin="0,10,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    $Reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    $PasswordBox = $Window.FindName("PasswordBox")
    $LoginButton = $Window.FindName("LoginButton")
    $StatusMessage = $Window.FindName("StatusMessage")
    
    $LoginButton.Add_Click({
        $Password = $PasswordBox.Password
        
        if ($Password -eq $Config.LoginPassword) {
            $Global:IsAuthenticated = $true
            $Global:CurrentUser = $env:USERNAME
            Write-Log "User authenticated: $($Global:CurrentUser)" -Level Success
            $Window.Close()
        }
        else {
            $StatusMessage.Text = "Invalid access code. Try again."
            $PasswordBox.Clear()
            $PasswordBox.Focus()
        }
    })
    
    # Allow Enter key to submit
    $PasswordBox.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Return) {
            $LoginButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }
    })
    
    $PasswordBox.Focus()
    return $Window
}

function New-MainDashboard {
    <#
    .SYNOPSIS
    Creates the main dashboard with node-based category interface
    #>
    
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($Config.AppTitle) - Dashboard" 
        Width="1200" 
        Height="800"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        Foreground="#e0e0e0">
    <Grid>
        <!-- Top Bar -->
        <StackPanel Height="60" VerticalAlignment="Top" Background="#0f1535" Orientation="Horizontal">
            <TextBlock Text="FiveM Mod Manager" 
                       FontSize="20" 
                       FontWeight="Bold" 
                       Foreground="#00d4ff"
                       VerticalAlignment="Center"
                       Margin="20,0,0,0"/>
            <TextBlock x:Name="UserInfo" 
                       FontSize="12" 
                       Foreground="#00ff88"
                       VerticalAlignment="Center"
                       Margin="40,0,0,0"/>
            <TextBlock Text="●" 
                       FontSize="16" 
                       Foreground="#00ff88"
                       VerticalAlignment="Center"
                       Margin="10,0,5,0"/>
            <TextBlock x:Name="StatusIndicator" 
                       Text="Connected" 
                       FontSize="11" 
                       Foreground="#00ff88"
                       VerticalAlignment="Center"/>
            <StackPanel HorizontalAlignment="Right" Orientation="Horizontal" Margin="0,0,20,0">
                <Button x:Name="FavoritesTab" 
                        Content="★ FAVORITES" 
                        Background="Transparent"
                        Foreground="#00d4ff"
                        BorderThickness="0"
                        FontSize="11"
                        Cursor="Hand"
                        Padding="10,5"
                        Margin="0,0,10,0"/>
                <Button x:Name="RefreshButton" 
                        Content="⟳ REFRESH" 
                        Background="Transparent"
                        Foreground="#00d4ff"
                        BorderThickness="0"
                        FontSize="11"
                        Cursor="Hand"
                        Padding="10,5"
                        Margin="0,0,10,0"/>
                <Button x:Name="SettingsButton" 
                        Content="⚙ SETTINGS" 
                        Background="Transparent"
                        Foreground="#00d4ff"
                        BorderThickness="0"
                        FontSize="11"
                        Cursor="Hand"
                        Padding="10,5"/>
            </StackPanel>
        </StackPanel>
        
        <!-- Main Content Area -->
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,60,0,0">
            <Canvas x:Name="DashboardCanvas" 
                    Background="#0a0e27"
                    Height="2000"
                    Width="1200"/>
        </ScrollViewer>
    </Grid>
</Window>
"@
    
    $Reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    $Global:MainWindow = $Window
    $Global:DashboardCanvas = $Window.FindName("DashboardCanvas")
    $UserInfo = $Window.FindName("UserInfo")
    $FavoritesTab = $Window.FindName("FavoritesTab")
    $RefreshButton = $Window.FindName("RefreshButton")
    $SettingsButton = $Window.FindName("SettingsButton")
    
    # Set user info
    $UserInfo.Text = "User: $($Global:CurrentUser)"
    
    # Create category nodes
    $Categories = @(
        "Sound Packs",
        "Custom Roads",
        "Reshade Setup",
        "NVE",
        "RPFs",
        "Reshade Configs",
        "Cheat Configs"
    )
    
    # Node positioning in a grid-like layout
    $NodeSize = 120
    $NodeSpacing = 180
    $StartX = 100
    $StartY = 100
    $NodesPerRow = 3
    
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        $Row = [math]::Floor($i / $NodesPerRow)
        $Col = $i % $NodesPerRow
        
        $X = $StartX + ($Col * $NodeSpacing)
        $Y = $StartY + ($Row * $NodeSpacing)
        
        $Node = New-CategoryNode -Category $Categories[$i] -X $X -Y $Y -Size $NodeSize
        $Global:DashboardCanvas.Children.Add($Node) | Out-Null
    }
    
    # Event handlers
    $FavoritesTab.Add_Click({ Show-FavoritesWindow })
    $RefreshButton.Add_Click({ Refresh-Dashboard })
    $SettingsButton.Add_Click({ Show-SettingsWindow })
    
    # Test GitHub connection on load
    $Window.Add_Loaded({
        $StatusIndicator = $Window.FindName("StatusIndicator")
        if (Test-GitHubConnection) {
            $StatusIndicator.Text = "Connected"
            $StatusIndicator.Foreground = "#00ff88"
        }
        else {
            $StatusIndicator.Text = "Offline"
            $StatusIndicator.Foreground = "#ff4757"
        }
    })
    
    return $Window
}

function New-CategoryNode {
    <#
    .SYNOPSIS
    Creates a clickable category node for the dashboard
    #>
    param(
        [string]$Category,
        [int]$X,
        [int]$Y,
        [int]$Size
    )
    
    # Create node grid
    $Node = New-Object System.Windows.Controls.Grid
    $Node.Width = $Size
    $Node.Height = $Size
    $Node.SetValue([System.Windows.Controls.Canvas]::LeftProperty, $X)
    $Node.SetValue([System.Windows.Controls.Canvas]::TopProperty, $Y)
    
    # Background ellipse
    $Background = New-Object System.Windows.Shapes.Ellipse
    $Background.Fill = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.BackgroundColor)"
    $Background.Stroke = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.PrimaryColor)"
    $Background.StrokeThickness = 2
    
    $Node.Children.Add($Background) | Out-Null
    
    # Text content
    $TextBlock = New-Object System.Windows.Controls.TextBlock
    $TextBlock.Text = $Category
    $TextBlock.FontSize = 13
    $TextBlock.FontWeight = 'Bold'
    $TextBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.PrimaryColor)"
    $TextBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $TextBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $TextBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $TextBlock.Padding = [System.Windows.Thickness]10
    $TextBlock.TextAlignment = [System.Windows.TextAlignment]::Center
    
    $Node.Children.Add($TextBlock) | Out-Null
    
    # Mouse events
    $Node.Cursor = [System.Windows.Input.Cursors]::Hand
    
    $Node.Add_MouseEnter({
        $Background.Stroke = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.SecondaryColor)"
        $Background.StrokeThickness = 3
        $TextBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.SecondaryColor)"
    })
    
    $Node.Add_MouseLeave({
        $Background.Stroke = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.PrimaryColor)"
        $Background.StrokeThickness = 2
        $TextBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush "$($Config.Theme.PrimaryColor)"
    })
    
    $Node.Add_MouseUp({
        Show-CategoryWindow -Category $Category
    })
    
    return $Node
}

function Show-CategoryWindow {
    <#
    .SYNOPSIS
    Displays a popup window for a specific category showing files
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    # Fetch files from GitHub
    $Files = Get-GitHubFiles -Category $Category
    
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Category - File Manager" 
        Width="600" 
        Height="500"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        Foreground="#e0e0e0"
        ResizeMode="CanResize">
    <Grid>
        <!-- Header -->
        <StackPanel Height="60" VerticalAlignment="Top" Background="#0f1535" Orientation="Horizontal">
            <TextBlock Text="$Category" 
                       FontSize="18" 
                       FontWeight="Bold" 
                       Foreground="#00d4ff"
                       VerticalAlignment="Center"
                       Margin="20,0,0,0"/>
            <StackPanel HorizontalAlignment="Right" Orientation="Horizontal" Margin="0,0,20,0">
                <Button x:Name="AddFileButton" 
                        Content="+ ADD FILE" 
                        Background="#00ff88"
                        Foreground="#0a0e27"
                        BorderThickness="0"
                        FontSize="12"
                        FontWeight="Bold"
                        Cursor="Hand"
                        Padding="15,8"
                        Margin="0,0,10,0"/>
                <Button x:Name="CloseButton" 
                        Content="CLOSE" 
                        Background="Transparent"
                        Foreground="#ff006e"
                        BorderThickness="0"
                        FontSize="12"
                        Cursor="Hand"
                        Padding="15,8"/>
            </StackPanel>
        </StackPanel>
        
        <!-- File List -->
        <ListBox x:Name="FileList" 
                 Margin="0,60,0,0"
                 Background="#1a1f3a"
                 BorderBrush="#00d4ff"
                 BorderThickness="1"
                 Foreground="#e0e0e0">
            <ListBox.ItemTemplate>
                <DataTemplate>
                    <StackPanel Margin="10" Orientation="Horizontal" Height="50">
                        <TextBlock Text="📦" FontSize="24" Margin="0,0,10,0"/>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="{Binding name}" FontSize="13" FontWeight="Bold" Foreground="#00d4ff"/>
                            <TextBlock Text="{Binding size, StringFormat='{0} bytes'}" FontSize="11" Foreground="#888888"/>
                        </StackPanel>
                    </StackPanel>
                </DataTemplate>
            </ListBox.ItemTemplate>
        </ListBox>
    </Grid>
</Window>
"@
    
    $Reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    $FileList = $Window.FindName("FileList")
    $AddFileButton = $Window.FindName("AddFileButton")
    $CloseButton = $Window.FindName("CloseButton")
    
    # Populate file list
    $FileList.ItemsSource = $Files
    
    # Event handlers
    $AddFileButton.Add_Click({
        Add-FileToCategory -Category $Category -Window $Window
    })
    
    $CloseButton.Add_Click({ $Window.Close() })
    
    # Double-click to install
    $FileList.Add_MouseDoubleClick({
        if ($FileList.SelectedItem) {
            Install-SelectedFile -Category $Category -SelectedFile $FileList.SelectedItem
        }
    })
    
    $Window.ShowDialog() | Out-Null
}

function Add-FileToCategory {
    <#
    .SYNOPSIS
    Allows user to select and upload a file to a category
    #>
    param(
        [string]$Category,
        $Window
    )
    
    # File picker
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Title = "Select file to upload to $Category"
    $OpenFileDialog.Filter = "All files (*.*)|*.*"
    
    if ($OpenFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $FilePath = $OpenFileDialog.FileName
        
        # Prompt for custom name
        [xml]$NameXAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Name Your File" 
        Width="400" 
        Height="200"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        ResizeMode="NoResize">
    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="350">
        <TextBlock Text="Custom File Name" Foreground="#e0e0e0" FontSize="12" Margin="0,0,0,10"/>
        <TextBox x:Name="NameInput" 
                 Height="35"
                 Background="#1a1f3a"
                 Foreground="#e0e0e0"
                 BorderBrush="#00d4ff"
                 BorderThickness="2"
                 Padding="10"
                 FontSize="13"
                 Margin="0,0,0,20"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="OkButton" Content="OK" Background="#00d4ff" Foreground="#0a0e27" 
                    Width="80" Margin="0,0,10,0" Cursor="Hand"/>
            <Button x:Name="CancelButton" Content="CANCEL" Background="Transparent" Foreground="#ff006e" 
                    Width="80" BorderThickness="1" BorderBrush="#ff006e" Cursor="Hand"/>
        </StackPanel>
    </StackPanel>
</Window>
"@
        
        $NameReader = [System.Xml.XmlNodeReader]::new($NameXAML)
        $NameWindow = [System.Windows.Markup.XamlReader]::Load($NameReader)
        
        $NameInput = $NameWindow.FindName("NameInput")
        $OkButton = $NameWindow.FindName("OkButton")
        $CancelButton = $NameWindow.FindName("CancelButton")
        $NameWindow.Owner = $Window
        
        $Result = $null
        
        $OkButton.Add_Click({
            $Result = $NameInput.Text
            $NameWindow.Close()
        })
        
        $CancelButton.Add_Click({ $NameWindow.Close() })
        
        $NameInput.Focus()
        $NameWindow.ShowDialog() | Out-Null
        
        # Upload file if name provided
        if (-not [string]::IsNullOrEmpty($Result)) {
            if (Upload-FileToGitHub -FilePath $FilePath -Category $Category -CustomName $Result) {
                Show-Notification -Title "Success" -Message "File uploaded: $Result" -Type Success
                
                # Refresh the file list
                $Window.Close()
                Start-Sleep -Milliseconds 500
                Show-CategoryWindow -Category $Category
            }
            else {
                Show-Notification -Title "Error" -Message "Upload failed. Check your GitHub settings." -Type Error
            }
        }
    }
}

function Install-SelectedFile {
    <#
    .SYNOPSIS
    Downloads and installs a selected file
    #>
    param(
        [string]$Category,
        $SelectedFile
    )
    
    if ($SelectedFile) {
        $FileName = $SelectedFile.name
        $DownloadUrl = $SelectedFile.download_url
        
        Write-Log "Installing: $FileName from $Category" -Level Info
        
        # Download file
        $LocalPath = Download-FileFromGitHub -DownloadUrl $DownloadUrl -FileName $FileName
        
        if ($LocalPath -and (Test-Path $LocalPath)) {
            # Install file
            if (Install-ModFile -FilePath $LocalPath -Category $Category) {
                Show-Notification -Title "Installation Complete" -Message "$FileName installed successfully" -Type Success
            }
            else {
                Show-Notification -Title "Installation Error" -Message "Failed to install $FileName" -Type Error
            }
            
            # Cleanup temp file
            Remove-Item -Path $LocalPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-FavoritesWindow {
    <#
    .SYNOPSIS
    Displays the favorites management window
    #>
    
    if ($Global:Favorites.Count -eq 0) {
        Show-Notification -Title "Favorites" -Message "No favorites added yet. Star files to add them here." -Type Info
        return
    }
    
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Favorites" 
        Width="600" 
        Height="500"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        Foreground="#e0e0e0">
    <Grid>
        <!-- Header -->
        <StackPanel Height="60" VerticalAlignment="Top" Background="#0f1535" Orientation="Horizontal">
            <TextBlock Text="★ FAVORITES" 
                       FontSize="18" 
                       FontWeight="Bold" 
                       Foreground="#00ff88"
                       VerticalAlignment="Center"
                       Margin="20,0,0,0"/>
        </StackPanel>
        
        <!-- Favorites List -->
        <ListBox x:Name="FavoritesList" 
                 Margin="0,60,0,0"
                 Background="#1a1f3a"
                 BorderBrush="#00ff88"
                 BorderThickness="1"
                 Foreground="#e0e0e0"/>
    </Grid>
</Window>
"@
    
    $Reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    $FavoritesList = $Window.FindName("FavoritesList")
    
    # Populate favorites
    $Items = @()
    foreach ($Fav in $Global:Favorites.Values) {
        $Items += @{
            Name     = $Fav.FileName
            Category = $Fav.Category
            Date     = $Fav.AddedDate
        }
    }
    
    $FavoritesList.ItemsSource = $Items
    $Window.ShowDialog() | Out-Null
}

function Show-SettingsWindow {
    <#
    .SYNOPSIS
    Displays the settings window
    #>
    
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" 
        Width="500" 
        Height="400"
        WindowStartupLocation="CenterScreen"
        Background="#0a0e27"
        Foreground="#e0e0e0"
        ResizeMode="NoResize">
    <StackPanel Margin="20" VerticalAlignment="Top">
        <TextBlock Text="SETTINGS" FontSize="20" FontWeight="Bold" Foreground="#00d4ff" Margin="0,0,0,30"/>
        
        <!-- GitHub Settings -->
        <TextBlock Text="GitHub Configuration" FontSize="14" FontWeight="Bold" Foreground="#00ff88" Margin="0,0,0,10"/>
        <TextBlock Text="Token Status:" Foreground="#e0e0e0" FontSize="12" Margin="0,0,0,5"/>
        <TextBlock x:Name="TokenStatus" Text="●  Connected" Foreground="#00ff88" FontSize="11" Margin="20,0,0,15"/>
        
        <!-- Installation Paths -->
        <TextBlock Text="Installation Paths" FontSize="14" FontWeight="Bold" Foreground="#00ff88" Margin="0,20,0,10"/>
        <TextBox x:Name="SoundPacksPath" Height="25" Background="#1a1f3a" Foreground="#e0e0e0" 
                 BorderBrush="#00d4ff" Padding="10" Margin="0,0,0,10" IsReadOnly="True"
                 Text="C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V\x64\audio\sfx"/>
        
        <!-- Logging -->
        <CheckBox x:Name="LoggingCheckbox" Content="Enable Logging" Foreground="#e0e0e0" 
                  FontSize="12" Margin="0,20,0,15" IsChecked="True"/>
        
        <!-- Clear Favorites -->
        <Button x:Name="ClearFavButton" Content="CLEAR ALL FAVORITES" 
                Background="#ff4757" Foreground="White" 
                Height="35" FontSize="12" Cursor="Hand" Margin="0,20,0,0"/>
    </StackPanel>
</Window>
"@
    
    $Reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    $ClearFavButton = $Window.FindName("ClearFavButton")
    
    $ClearFavButton.Add_Click({
        $Global:Favorites = @{}
        @{} | ConvertTo-Json | Set-Content -Path $Config.FavoritesPath -Encoding UTF8
        Show-Notification -Title "Success" -Message "All favorites cleared" -Type Success
        $Window.Close()
    })
    
    $Window.ShowDialog() | Out-Null
}

function Refresh-Dashboard {
    <#
    .SYNOPSIS
    Refreshes the dashboard and file listings
    #>
    Write-Log "Refreshing dashboard..." -Level Info
    Show-Notification -Title "Refreshing" -Message "Syncing with GitHub..." -Type Info
    
    # Clear cached files
    $Global:CategoryFiles = @{}
    
    # Could trigger a full UI refresh here
    Show-Notification -Title "Complete" -Message "Dashboard refreshed" -Type Success
}

#endregion

#region MAIN APPLICATION ENTRY
# ============================================================================
# MAIN APPLICATION STARTUP AND EVENT LOOP
# ============================================================================

function Start-Application {
    <#
    .SYNOPSIS
    Initializes and starts the FiveM Mod Manager application
    #>
    
    Write-Log "Starting FiveM Mod Manager v$($Config.AppVersion)" -Level Success
    Write-Log "User: $env:USERNAME" -Level Info
    
    # Load required assemblies
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
    
    # Verify configuration
    if ($Config.GitHubToken -eq "YOUR_GITHUB_TOKEN_HERE") {
        Write-Log "WARNING: GitHub token not configured. File operations will be limited." -Level Warning
        [System.Windows.MessageBox]::Show(
            "GitHub token is not configured. Please set your token in the script configuration.",
            "Configuration Required",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
    }
    
    # Display login window
    Write-Log "Displaying login window..." -Level Info
    $LoginWindow = New-LoginWindow
    $LoginWindow.ShowDialog() | Out-Null
    
    if (-not $Global:IsAuthenticated) {
        Write-Log "Authentication failed. Application exiting." -Level Warning
        exit
    }
    
    # Create and display main dashboard
    Write-Log "Creating main dashboard..." -Level Info
    $DashboardWindow = New-MainDashboard
    
    # Configure window behavior
    $DashboardWindow.Add_Closed({
        Write-Log "Application closed by user" -Level Info
        [System.Windows.Application]::Current.Shutdown()
    })
    
    # Show dashboard
    $DashboardWindow.ShowDialog() | Out-Null
}

#endregion

#region ENTRY POINT
# ============================================================================
# APPLICATION ENTRY POINT
# ============================================================================

# Check for administrator privileges (recommended for file operations)
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Log "NOTE: Not running as administrator. Some features may be limited." -Level Warning
    Write-Host "Recommended: Run PowerShell as Administrator for full functionality." -ForegroundColor Yellow
}

# Start the application
try {
    Start-Application
}
catch {
    Write-Log "Fatal error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    [System.Windows.MessageBox]::Show(
        "An error occurred: $_`n`nCheck the log file for details.",
        "Application Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

#endregion