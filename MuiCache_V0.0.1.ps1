# Configuration de l'encodage
$OutputEncoding = [System.Text.Encoding]::Default
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# CONFIGURATION CHEMINS
# =========================
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir = Join-Path $ScriptRoot "out_muicache"
if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$logFile = Join-Path $OutDir "muicache_log.txt"

# =========================
# INTERFACE GRAPHIQUE (Simplifiée pour l'exemple)
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "MUI Cache Analyzer v1.0"
$form.Size = "820,600"
$form.StartPosition = "CenterScreen"

$txtReCmd = New-Object System.Windows.Forms.TextBox
$txtReCmd.Location = "150,20"; $txtReCmd.Size = "520,20"; $txtReCmd.ReadOnly = $true
$btnReCmd = New-Object System.Windows.Forms.Button
$btnReCmd.Text = "ReCmd.exe"; $btnReCmd.Location = "20,18"

$txtUsers = New-Object System.Windows.Forms.TextBox
$txtUsers.Location = "150,60"; $txtUsers.Size = "520,20"; $txtUsers.Text = "C:\Users"
$btnUsers = New-Object System.Windows.Forms.Button
$btnUsers.Text = "Dossier Users"; $btnUsers.Location = "20,58"

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Lancer l'Analyse MUI"; $btnRun.Location = "150,100"; $btnRun.Size = "200,35"; $btnRun.BackColor = "LightBlue"

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = "20,150"; $logBox.Size = "760,380"; $logBox.Multiline = $true; $logBox.ScrollBars = "Vertical"; $logBox.ReadOnly = $true

$form.Controls.AddRange(@($txtReCmd,$txtUsers,$btnReCmd,$btnUsers,$btnRun,$logBox))

# --- Fonctions Log ---
function Write-Log($message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$timestamp] $message`r`n")
    "[$timestamp] $message" | Out-File $logFile -Append
}

# --- Événements ---
$btnReCmd.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    if ($dialog.ShowDialog() -eq "OK") { $script:ReCmdPath = $dialog.FileName; $txtReCmd.Text = $dialog.FileName }
})

$btnUsers.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq "OK") { $txtUsers.Text = $dialog.SelectedPath }
})

# =========================
# ACTION PRINCIPALE
# =========================
$btnRun.Add_Click({
    if (-not $script:ReCmdPath -or -not (Test-Path $txtUsers.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Configuration incomplete.")
        return
    }

    $logBox.Clear()
    Write-Log "Demarrage de l'analyse MUI Cache..."

    # 1. Création du fichier de template ReCmd (.reb) pour le MUI Cache
    $rebPath = Join-Path $OutDir "muicache.reb"
    $rebContent = @"
Description: MUI Cache Extraction
Author: ForensicTool
Version: 1
Id: mui1
Keys:
    -
        Description: MuiCache Registry Key
        HiveType: NTUSER
        Category: UserActivity
        KeyPath: Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache
        Recursive: true
"@
    $rebContent | Out-File $rebPath -Encoding Default -Force

    $profiles = Get-ChildItem $txtUsers.Text -Directory | Where-Object { $_.Name -notin @("Default","Public","All Users") }
    $results = @()

    foreach ($profile in $profiles) {
        $ntuser = Join-Path $profile.FullName "NTUSER.DAT"
        if (Test-Path $ntuser) {
            Write-Log "Traitement de l'utilisateur : $($profile.Name)"
            $tempCsvName = "mui_$($profile.Name).csv"
            
            # 2. Exécution de ReCmd
            & $script:ReCmdPath -f $ntuser --bn $rebPath --csv $OutDir --csvf $tempCsvName --recover | Out-Null
            
            $tempCsvPath = Join-Path $OutDir $tempCsvName
            if (Test-Path $tempCsvPath) {
                $data = Import-Csv $tempCsvPath
                foreach ($row in $data) {
                    if ($row.ValueName -and $row.ValueData) {
                        $results += [PSCustomObject]@{
                            Utilisateur = $profile.Name
                            Application = $row.ValueName  # Souvent le chemin complet de l'EXE
                            NomFriendly = $row.ValueData  # Le nom affiché dans l'interface
                            DerniereModifCle = $row.LastWriteTime
                        }
                    }
                }
                Remove-Item $tempCsvPath -ErrorAction SilentlyContinue
            }
        }
    }

    # 3. Export Final
    if ($results.Count -gt 0) {
        $csvPath = Join-Path $OutDir "MuiCache_Final_Report.csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding Default
        Write-Log "Analyse terminee. Rapport genere : $csvPath"
        $results | Out-GridView -Title "Resultats MUI Cache"
    } else {
        Write-Log "Aucune donnee MUI Cache trouvee."
    }
})

$form.ShowDialog()