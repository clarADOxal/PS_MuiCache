# Configuration de l'encodage pour la session
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# CONFIGURATION CHEMINS
# =========================
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir = Join-Path $ScriptRoot "out_muicache"
if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$logFile = Join-Path $OutDir "muicache_session_log.txt"

# =========================
# FENETRE PRINCIPALE
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "MUI Cache Analyzer v2.0 (Multi-Hive)"
$form.Size = "850,700"
$form.StartPosition = "CenterScreen"

# --- UI CONTROLES ---
$lblReCmd = New-Object System.Windows.Forms.Label
$lblReCmd.Text = "Chemin RECmd.exe :"; $lblReCmd.Location = "20,22"; $lblReCmd.AutoSize = $true

$txtReCmd = New-Object System.Windows.Forms.TextBox
$txtReCmd.Location = "150,20"; $txtReCmd.Size = "520,20"; $txtReCmd.ReadOnly = $true

$btnReCmd = New-Object System.Windows.Forms.Button
$btnReCmd.Text = "..."; $btnReCmd.Location = "680,18"; $btnReCmd.Size = "40,25"

$lblUsers = New-Object System.Windows.Forms.Label
$lblUsers.Text = "Dossier C:\Users :"; $lblUsers.Location = "20,62"; $lblUsers.AutoSize = $true

$txtUsers = New-Object System.Windows.Forms.TextBox
$txtUsers.Location = "150,60"; $txtUsers.Size = "520,20"; $txtUsers.Text = "C:\Users"

$btnUsers = New-Object System.Windows.Forms.Button
$btnUsers.Text = "..."; $btnUsers.Location = "680,58"; $btnUsers.Size = "40,25"

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "LANCER L'ANALYSE (NTUSER + USRCLASS)"; $btnRun.Location = "150,100"; $btnRun.Size = "300,40"; $btnRun.BackColor = "LightGreen"; $btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = "150,155"; $progressBar.Size = "520,15"

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = "20,190"; $logBox.Size = "790,450"; $logBox.Multiline = $true; $logBox.ScrollBars = "Vertical"; $logBox.ReadOnly = $true; $logBox.Font = New-Object System.Drawing.Font("Consolas", 9); $logBox.BackColor = "Black"; $logBox.ForeColor = "White"

$form.Controls.AddRange(@($lblReCmd, $txtReCmd, $btnReCmd, $lblUsers, $txtUsers, $btnUsers, $btnRun, $progressBar, $logBox))

# =========================
# FONCTIONS
# =========================
function Write-Log($message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $fullLine = "[$timestamp] $message"
    $logBox.AppendText("$fullLine`r`n")
    $fullLine | Out-File -FilePath $logFile -Append -Encoding UTF8
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# =========================
# EVENEMENTS
# =========================
$btnReCmd.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "RECmd.exe|RECmd.exe"
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
        [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner RECmd.exe et le dossier source des profils.", "Erreur")
        return
    }

    $btnRun.Enabled = $false
    $logBox.Clear()
    Write-Log "--- Début de l'Analyse MUI Cache ---"

    # 1. Création du fichier de configuration REB Universel
    $rebPath = Join-Path $OutDir "muicache_universal.reb"
    $rebContent = @"
Description: Extraction MUI Cache (NTUSER et USRCLASS)
Author: ForensicTool
Version: 1
Id: mui_univ
Keys:
    -
        Description: MuiCache Standard
        HiveType: Any
        Category: UserActivity
        KeyPath: Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache
        Recursive: true
    -
        Description: MuiCache Legacy
        HiveType: NTUSER
        Category: UserActivity
        KeyPath: Software\Microsoft\Windows\ShellNoRoam\MUICache
        Recursive: true
"@
    $rebContent | Out-File $rebPath -Encoding Default -Force

    # 2. Identification des profils
    $profiles = Get-ChildItem $txtUsers.Text -Directory | Where-Object { $_.Name -notin @("Default","Public","All Users") }
    $results = @()
    $pIdx = 0

    foreach ($profile in $profiles) {
        $pIdx++
        $progressBar.Value = [int](($pIdx / $profiles.Count) * 100)
        Write-Log "Traitement de l'utilisateur : $($profile.Name)"

        # Définition des chemins vers les deux fichiers cruciaux
        $hives = @(
            @{ Path = Join-Path $profile.FullName "NTUSER.DAT"; Name = "NTUSER.DAT" },
            @{ Path = Join-Path $profile.FullName "AppData\Local\Microsoft\Windows\UsrClass.dat"; Name = "UsrClass.dat" }
        )

        foreach ($hive in $hives) {
            if (Test-Path $hive.Path) {
                Write-Log "  [+] Lecture de $($hive.Name)..."
                
                $tempCsvName = "raw_mui_$($profile.Name)_$($hive.Name).csv"
                $tempCsvPath = Join-Path $OutDir $tempCsvName
                
                # Exécution RECmd
                & $script:ReCmdPath -f $hive.Path --bn $rebPath --csv $OutDir --csvf $tempCsvName --recover | Out-Null
                
                if (Test-Path $tempCsvPath) {
                    $csvData = Import-Csv $tempCsvPath
                    foreach ($row in $csvData) {
                        # Filtrage : On ignore LangID et les entrées vides
                        if ($row.ValueName -and $row.ValueData -and $row.ValueName -notmatch "LangID") {
                            
                            # Nettoyage du chemin de l'application
                            $cleanApp = $row.ValueName -replace "\.FriendlyAppName$", "" -replace "\.ApplicationCompany$", ""
                            
                            $results += [PSCustomObject]@{
                                Utilisateur = $profile.Name
                                Source      = $hive.Name
                                Application = $cleanApp
                                Description = $row.ValueData
                                LastWrite   = $row.LastWriteTime
                            }
                        }
                    }
                    Remove-Item $tempCsvPath -ErrorAction SilentlyContinue
                }
            } else {
                Write-Log "  [-] $($hive.Name) non trouvé ou inaccessible."
            }
        }
    }

    # 3. Finalisation et Affichage
    if ($results.Count -gt 0) {
        $finalCsv = Join-Path $OutDir "Rapport_MuiCache_Global.csv"
        $results | Sort-Object LastWrite -Descending | Export-Csv -Path $finalCsv -NoTypeInformation -Encoding UTF8
        Write-Log "SUCCÈS : $($results.Count) entrées extraites."
        Write-Log "Rapport sauvegardé : $finalCsv"
        $results | Out-GridView -Title "Analyse MUI Cache Terminée"
    } else {
        Write-Log "ALERTE : Aucun résultat trouvé. Vérifiez les droits d'accès aux fichiers DAT."
    }

    Write-Log "--- Analyse Terminée ---"
    $btnRun.Enabled = $true
})

$form.ShowDialog()