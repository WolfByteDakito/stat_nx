[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Data

# =========================================================
#  BTS SIO - Stats Licences NX (version Docker / MySQL)
#  Interface WinForms branchee sur le conteneur MySQL
#  via 'docker exec'.
# =========================================================

$SitesConfig = @{
    'France' = @(
        @{ Code = 'FRDE'; Site = 'Delle' },
        @{ Code = 'FRDA'; Site = 'Dalse' },
        @{ Code = 'FRPU'; Site = 'Puiseux' },
        @{ Code = 'FRLF'; Site = 'LaFerte' },
        @{ Code = 'FRME'; Site = 'Melisey' },
        @{ Code = 'FRLU'; Site = 'Lure' },
        @{ Code = 'FRGR'; Site = 'Grandvillars' },
        @{ Code = 'FRDC'; Site = 'Datacenter' }
    )
    'Allemagne' = @(
        @{ Code = 'DEME'; Site = 'Mellrichstadt' },
        @{ Code = 'DEKI'; Site = 'Kirspe' },
        @{ Code = 'DEHE'; Site = 'Heidelberg' }
    )
    'Espagne' = @(
        @{ Code = 'ESFU'; Site = 'Fuenlabrada' }
    )
    'Maroc' = @(
        @{ Code = 'MOTA'; Site = 'Tanger' }
    )
    'Mexique' = @(
        @{ Code = 'MXMO'; Site = 'Monterrey' },
        @{ Code = 'MXQU'; Site = 'Queretaro' }
    )
    'Chine' = @(
        @{ Code = 'CNSH'; Site = 'Shanghai' },
        @{ Code = 'CNSU'; Site = 'Suzhou' }
    )
    'Etats-Unis' = @(
        @{ Code = 'USLI'; Site = 'Livonia' },
        @{ Code = 'USLZ'; Site = 'Lake Zurich' }
    )
    'Hongrie' = @(
        @{ Code = 'HUGR'; Site = 'Gyor' }
    )
    'Republique Tcheque' = @(
        @{ Code = 'CZCE'; Site = 'Cejc' }
    )
}

$script:DbConfig = @{
    Container = 'nx_licenses_db'
    User      = 'nx_app'
    Password  = 'nx_app_pwd'
    Database  = 'nx_licenses_stats'
}

$script:LastSearchContext = $null

# ---------------------------------------------------------
#  Couche d'acces MySQL (via docker exec)
# ---------------------------------------------------------
function ConvertTo-MySqlLiteral {
    param($Value)

    if ($null -eq $Value -or $Value -eq [DBNull]::Value) {
        return 'NULL'
    }
    if ($Value -is [DateTime]) {
        return "'" + $Value.ToString('yyyy-MM-dd HH:mm:ss') + "'"
    }
    if ($Value -is [bool]) {
        if ($Value) { return '1' } else { return '0' }
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value).Replace(',', '.')
    }
    $s = [string]$Value
    $s = $s -replace '\\', '\\'
    $s = $s -replace "'", "\'"
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`n", '\n'
    return "'" + $s + "'"
}

function Invoke-MySqlBatch {
    param(
        [Parameter(Mandatory)] [string] $Query
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'docker'
    $argList = @(
        'exec', '-i',
        '-e', "MYSQL_PWD=$($script:DbConfig.Password)",
        $script:DbConfig.Container,
        'mysql', '-u', $script:DbConfig.User,
        $script:DbConfig.Database,
        '--batch',
        '--default-character-set=utf8mb4'
    )
    $psi.Arguments = ($argList | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Query)
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.BaseStream.Flush()
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        $msg = if ($stderr) { $stderr } else { $stdout }
        throw "MySQL erreur (code $($proc.ExitCode)) :`n$msg"
    }
    return $stdout
}

function ConvertFrom-MySqlBatch {
    param([string]$Output)

    $dt = New-Object System.Data.DataTable
    if ([string]::IsNullOrWhiteSpace($Output)) { return ,$dt }

    $lines = $Output -split "(`r`n|`n)" | Where-Object { $_ -ne "`r`n" -and $_ -ne "`n" }
    if ($lines.Count -eq 0) { return ,$dt }

    $headers = $lines[0] -split "`t"
    foreach ($h in $headers) { [void]$dt.Columns.Add($h, [string]) }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrEmpty($line)) { continue }
        $vals = $line -split "`t"
        $row = $dt.NewRow()
        for ($j = 0; $j -lt $headers.Count; $j++) {
            if ($j -lt $vals.Count) {
                $v = $vals[$j]
                if ($v -eq 'NULL') {
                    $row[$j] = [DBNull]::Value
                } else {
                    $v = $v -replace '\\n', "`n"
                    $v = $v -replace '\\t', "`t"
                    $v = $v -replace '\\\\', '\'
                    $row[$j] = $v
                }
            }
        }
        [void]$dt.Rows.Add($row)
    }
    return ,$dt
}

function Invoke-MySqlQuery {
    param(
        [Parameter(Mandatory)] [string] $Query,
        [switch] $ReturnScalar
    )

    $raw = Invoke-MySqlBatch -Query $Query
    $dt  = ConvertFrom-MySqlBatch -Output $raw

    if ($ReturnScalar) {
        if ($dt.Rows.Count -gt 0 -and $dt.Columns.Count -gt 0) {
            return $dt.Rows[0][0]
        }
        return $null
    }
    return ,$dt
}

# ---------------------------------------------------------
#  Construction de la clause WHERE (parametrage securise)
# ---------------------------------------------------------
function New-Filter {
    param(
        [string[]]$SiteCodes,
        [string]$UserFilter,
        [string]$LicFilter,
        [string]$HostFilter,
        [DateTime]$DateDebut,
        [DateTime]$DateFin
    )

    $clauses = @()
    $clauses += "ul.date_utilisation >= " + (ConvertTo-MySqlLiteral $DateDebut.Date)
    $clauses += "ul.date_utilisation <  " + (ConvertTo-MySqlLiteral $DateFin.Date.AddDays(1))

    if ($SiteCodes -and $SiteCodes.Count -gt 0) {
        $codes = ($SiteCodes | ForEach-Object { ConvertTo-MySqlLiteral $_ }) -join ','
        $clauses += "s.code_site IN ($codes)"
    }

    if ($UserFilter) {
        $clauses += "u.login LIKE " + (ConvertTo-MySqlLiteral "%$UserFilter%")
    }

    if ($LicFilter) {
        $clauses += "l.nom_licence LIKE " + (ConvertTo-MySqlLiteral "%$LicFilter%")
    }

    if ($HostFilter) {
        $clauses += "ul.hostname LIKE " + (ConvertTo-MySqlLiteral "%$HostFilter%")
    }

    return $clauses -join " AND "
}

# ---------------------------------------------------------
#  Aide UI
# ---------------------------------------------------------
function Show-TableInGrid {
    param(
        [System.Windows.Forms.DataGridView]$Grid,
        [System.Data.DataTable]$Table
    )

    $Grid.SuspendLayout()
    try {
        $Grid.DataSource = $null
        $Grid.Rows.Clear()
        $Grid.Columns.Clear()
        foreach ($col in $Table.Columns) {
            $null = $Grid.Columns.Add($col.ColumnName, $col.ColumnName)
        }
        foreach ($row in $Table.Rows) {
            $vals = @()
            foreach ($col in $Table.Columns) { $vals += $row[$col.ColumnName] }
            $null = $Grid.Rows.Add($vals)
        }
        $Grid.AutoResizeColumns()
    }
    finally {
        $Grid.ResumeLayout()
        $Grid.Refresh()
    }
}

function Export-DataTableToCsvFile {
    param(
        [object]$Table,
        [string]$Path
    )

    if ($Table -is [System.Object[]]) {
        $Table = $Table | Where-Object { $_ -is [System.Data.DataTable] } | Select-Object -First 1
    }
    if ($Table -isnot [System.Data.DataTable]) {
        throw "Le resultat SQL n'est pas un DataTable."
    }

    $writer = New-Object System.IO.StreamWriter($Path, $false, [System.Text.Encoding]::UTF8)
    try {
        $headers = @($Table.Columns | ForEach-Object { $_.ColumnName })
        $writer.WriteLine(($headers -join ","))
        foreach ($row in $Table.Rows) {
            $vals = @()
            foreach ($col in $Table.Columns) {
                $txt = ""
                $v = $row[$col.ColumnName]
                if ($null -ne $v -and $v -ne [DBNull]::Value) {
                    $txt = $v.ToString().Replace('"', '""')
                }
                if ($txt.Contains(",") -or $txt.Contains('"') -or $txt.Contains("`n") -or $txt.Contains("`r")) {
                    $txt = '"' + $txt + '"'
                }
                $vals += $txt
            }
            $writer.WriteLine(($vals -join ","))
        }
    }
    finally {
        $writer.Close()
    }
}

# ---------------------------------------------------------
#  Chargement des donnees
# ---------------------------------------------------------
function Load-LicenseData {
    param(
        [string[]]$SiteCodes,
        [string[]]$Countries,
        [string]$Usuario,
        [string]$Service,
        [string]$HostFilter,
        [DateTime]$DateDebut,
        [DateTime]$DateFin,
        [System.Windows.Forms.DataGridView]$Grid,
        [System.Windows.Forms.Label]$StatusLabel
    )

    try {
        if ((-not $SiteCodes -or $SiteCodes.Count -eq 0) -and $Countries -and $Countries.Count -gt 0) {
            $SiteCodes = @()
            foreach ($country in $Countries) {
                if ($SitesConfig.ContainsKey($country)) {
                    $SiteCodes += $SitesConfig[$country] | ForEach-Object { $_.Code }
                }
            }
        }

        if ($DateFin.Date -lt $DateDebut.Date) {
            [System.Windows.Forms.MessageBox]::Show("La date de fin doit etre >= date debut.", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $where = New-Filter -SiteCodes $SiteCodes -UserFilter $Usuario -LicFilter $Service -HostFilter $HostFilter -DateDebut $DateDebut -DateFin $DateFin

        $query = @"
SELECT
    ul.hostname               AS hostname,
    u.login                   AS ``login``,
    l.nom_licence             AS lic_name,
    COUNT(*)                  AS occurrence_count
FROM utilisation_licence ul
JOIN site        s ON s.id_site    = ul.id_site
JOIN utilisateur u ON u.id_user    = ul.id_user
JOIN licence     l ON l.id_licence = ul.id_licence
WHERE $where
GROUP BY ul.hostname, u.login, l.nom_licence
ORDER BY occurrence_count DESC, ul.hostname ASC
LIMIT 5000;
"@

        $table = Invoke-MySqlQuery -Query $query

        if ($table -and $table.Rows.Count -gt 0) {
            Show-TableInGrid -Grid $Grid -Table $table
            $script:LastSearchContext = [PSCustomObject]@{
                SiteCodes  = @($SiteCodes)
                Countries  = @($Countries)
                Usuario    = $Usuario
                Service    = $Service
                HostFilter = $HostFilter
                DateDebut  = $DateDebut.Date
                DateFin    = $DateFin.Date
            }
            $StatusLabel.Text = "$($table.Rows.Count) lignes chargees (report agrege)"
            $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
        }
        else {
            $Grid.DataSource = $null
            $Grid.Rows.Clear()
            $Grid.Columns.Clear()
            $StatusLabel.Text = "Aucun resultat."
            $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(231, 76, 60)
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Erreur chargement:`n$($_.Exception.Message)", "ERREUR", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Export-GridToCsv {
    if (-not $script:LastSearchContext) {
        [System.Windows.Forms.MessageBox]::Show("Fais une recherche avant export.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "CSV Files (*.csv)|*.csv"
    $saveDialog.FileName = "LicenseStats_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $saveDialog.InitialDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
    if ($saveDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $ctx = $script:LastSearchContext
        $where = New-Filter -SiteCodes $ctx.SiteCodes -UserFilter $ctx.Usuario -LicFilter $ctx.Service -HostFilter $ctx.HostFilter -DateDebut $ctx.DateDebut -DateFin $ctx.DateFin
        $query = @"
SELECT
    ul.hostname    AS hostname,
    u.login        AS ``login``,
    l.nom_licence  AS lic_name
FROM utilisation_licence ul
JOIN site        s ON s.id_site    = ul.id_site
JOIN utilisateur u ON u.id_user    = ul.id_user
JOIN licence     l ON l.id_licence = ul.id_licence
WHERE $where
GROUP BY ul.hostname, u.login, l.nom_licence
ORDER BY ul.hostname, u.login, l.nom_licence;
"@
        $table = Invoke-MySqlQuery -Query $query
        if (-not $table -or $table.Rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Aucune ligne a exporter.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        Export-DataTableToCsvFile -Table $table -Path $saveDialog.FileName
        [System.Windows.Forms.MessageBox]::Show("Export termine.`n$($table.Rows.Count) lignes.", "Export CSV", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Erreur export:`n$($_.Exception.Message)", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Test-DbConnection {
    try {
        $v = Invoke-MySqlQuery -Query "SELECT VERSION() AS version, DATABASE() AS db, USER() AS who;"
        $msg = "Connexion OK.`n`n"
        if ($v -and $v.Rows.Count -gt 0) {
            foreach ($col in $v.Columns) {
                $msg += "$($col.ColumnName) = $($v.Rows[0][$col.ColumnName])`n"
            }
        }
        [System.Windows.Forms.MessageBox]::Show($msg, "Test BDD", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Connexion KO:`n$($_.Exception.Message)", "Test BDD", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

# ---------------------------------------------------------
#  Formulaire
# ---------------------------------------------------------
function New-StatsForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "BTS SIO - Stats Licences"
    $form.Size = New-Object System.Drawing.Size(1200, 800)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 248, 252)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "BTS SIO - Stats Licences"
    $header.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $header.ForeColor = [System.Drawing.Color]::White
    $header.BackColor = [System.Drawing.Color]::FromArgb(16, 69, 127)
    $header.TextAlign = "MiddleCenter"
    $header.Size = New-Object System.Drawing.Size(1200, 50)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $form.Controls.Add($header)

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = "Criteres de recherche"
    $group.Location = New-Object System.Drawing.Point(20, 70)
    $group.Size = New-Object System.Drawing.Size(1160, 210)
    $form.Controls.Add($group)

    $lblPays = New-Object System.Windows.Forms.Label
    $lblPays.Text = "Pays :"
    $lblPays.Location = New-Object System.Drawing.Point(20, 30)
    $lblPays.Size = New-Object System.Drawing.Size(80, 25)
    $lblPays.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblPays)

    $cmbPays = New-Object System.Windows.Forms.ComboBox
    $cmbPays.Location = New-Object System.Drawing.Point(110, 28)
    $cmbPays.Size = New-Object System.Drawing.Size(200, 25)
    $cmbPays.DropDownStyle = "DropDownList"
    $cmbPays.Items.AddRange(@("-- Selectionnez un Pays --") + @($SitesConfig.Keys | Sort-Object))
    $cmbPays.SelectedIndex = 0
    $group.Controls.Add($cmbPays)

    $lblSites = New-Object System.Windows.Forms.Label
    $lblSites.Text = "Sites :"
    $lblSites.Location = New-Object System.Drawing.Point(330, 30)
    $lblSites.Size = New-Object System.Drawing.Size(80, 25)
    $lblSites.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblSites)

    $checkedSites = New-Object System.Windows.Forms.CheckedListBox
    $checkedSites.Location = New-Object System.Drawing.Point(420, 22)
    $checkedSites.Size = New-Object System.Drawing.Size(280, 85)
    $checkedSites.CheckOnClick = $true
    $group.Controls.Add($checkedSites)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Utilisateur :"
    $lblUser.Location = New-Object System.Drawing.Point(720, 30)
    $lblUser.Size = New-Object System.Drawing.Size(80, 25)
    $lblUser.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(810, 28)
    $txtUser.Size = New-Object System.Drawing.Size(150, 25)
    $group.Controls.Add($txtUser)

    $lbhost = New-Object System.Windows.Forms.Label
    $lbhost.Text = "Hostname (ex: FRDE) :"
    $lbhost.Location = New-Object System.Drawing.Point(720, 60)
    $lbhost.Size = New-Object System.Drawing.Size(150, 25)
    $lbhost.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lbhost)

    $txthost = New-Object System.Windows.Forms.TextBox
    $txthost.Location = New-Object System.Drawing.Point(880, 60)
    $txthost.Size = New-Object System.Drawing.Size(80, 25)
    $group.Controls.Add($txthost)

    $lblLic = New-Object System.Windows.Forms.Label
    $lblLic.Text = "Licence :"
    $lblLic.Location = New-Object System.Drawing.Point(20, 115)
    $lblLic.Size = New-Object System.Drawing.Size(80, 25)
    $lblLic.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblLic)

    $txtLic = New-Object System.Windows.Forms.TextBox
    $txtLic.Location = New-Object System.Drawing.Point(110, 113)
    $txtLic.Size = New-Object System.Drawing.Size(200, 25)
    $group.Controls.Add($txtLic)

    $lblDateDebut = New-Object System.Windows.Forms.Label
    $lblDateDebut.Text = "Date debut :"
    $lblDateDebut.Location = New-Object System.Drawing.Point(330, 115)
    $lblDateDebut.Size = New-Object System.Drawing.Size(80, 25)
    $lblDateDebut.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblDateDebut)

    $dpDebut = New-Object System.Windows.Forms.DateTimePicker
    $dpDebut.Location = New-Object System.Drawing.Point(420, 113)
    $dpDebut.Size = New-Object System.Drawing.Size(150, 25)
    $dpDebut.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $dpDebut.Value = (Get-Date).AddDays(-30)
    $group.Controls.Add($dpDebut)

    $lblDateFin = New-Object System.Windows.Forms.Label
    $lblDateFin.Text = "Date fin :"
    $lblDateFin.Location = New-Object System.Drawing.Point(590, 115)
    $lblDateFin.Size = New-Object System.Drawing.Size(80, 25)
    $lblDateFin.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($lblDateFin)

    $dpFin = New-Object System.Windows.Forms.DateTimePicker
    $dpFin.Location = New-Object System.Drawing.Point(680, 113)
    $dpFin.Size = New-Object System.Drawing.Size(150, 25)
    $dpFin.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $dpFin.Value = (Get-Date)
    $group.Controls.Add($dpFin)

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = "Start"
    $btnStart.Location = New-Object System.Drawing.Point(20, 160)
    $btnStart.Size = New-Object System.Drawing.Size(100, 35)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(52, 152, 219)
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($btnStart)

    $btnReset = New-Object System.Windows.Forms.Button
    $btnReset.Text = "Reinitialiser"
    $btnReset.Location = New-Object System.Drawing.Point(130, 160)
    $btnReset.Size = New-Object System.Drawing.Size(100, 35)
    $btnReset.BackColor = [System.Drawing.Color]::FromArgb(149, 165, 166)
    $btnReset.ForeColor = [System.Drawing.Color]::White
    $btnReset.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($btnReset)

    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = "Test BDD"
    $btnTest.Location = New-Object System.Drawing.Point(240, 160)
    $btnTest.Size = New-Object System.Drawing.Size(100, 35)
    $btnTest.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
    $btnTest.ForeColor = [System.Drawing.Color]::White
    $btnTest.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($btnTest)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = "Exporter CSV"
    $btnExport.Location = New-Object System.Drawing.Point(350, 160)
    $btnExport.Size = New-Object System.Drawing.Size(100, 35)
    $btnExport.BackColor = [System.Drawing.Color]::FromArgb(155, 89, 182)
    $btnExport.ForeColor = [System.Drawing.Color]::White
    $btnExport.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $group.Controls.Add($btnExport)

    $lblPerf = New-Object System.Windows.Forms.Label
    $lblPerf.Text = "(Affichage limite a 5000 lignes. Export report: hostname, login, licence)"
    $lblPerf.Location = New-Object System.Drawing.Point(470, 160)
    $lblPerf.Size = New-Object System.Drawing.Size(500, 35)
    $lblPerf.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblPerf.ForeColor = [System.Drawing.Color]::FromArgb(127, 140, 141)
    $group.Controls.Add($lblPerf)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(20, 295)
    $grid.Size = New-Object System.Drawing.Size(1160, 450)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.ReadOnly = $true
    $grid.AutoSizeColumnsMode = "AllCells"
    $grid.ColumnHeadersVisible = $true
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.GridColor = [System.Drawing.Color]::LightGray
    $grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $form.Controls.Add($grid)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "1. Selectionnez un Pays | 2. Optionnel: cochez 1+ sites | 3. Optionnel: filtres | 4. Cliquez Start"
    $lblStatus.Location = New-Object System.Drawing.Point(20, 755)
    $lblStatus.Size = New-Object System.Drawing.Size(1160, 25)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(127, 140, 141)
    $form.Controls.Add($lblStatus)

    $cmbPays.Add_SelectedIndexChanged({
        $checkedSites.Items.Clear()
        $country = [string]$cmbPays.SelectedItem
        if ($country -and $country -ne "-- Selectionnez un Pays --") {
            foreach ($site in $SitesConfig[$country]) {
                $null = $checkedSites.Items.Add("$($site.Code) | $($site.Site)")
            }
        }
    })

    $btnStart.Add_Click({
        $codes = @()
        foreach ($item in $checkedSites.CheckedItems) {
            $code = $item.ToString().Split("|")[0].Trim()
            if ($code) { $codes += $code }
        }
        $countries = @()
        if ($cmbPays.SelectedIndex -gt 0) {
            $countries = @([string]$cmbPays.SelectedItem)
        }
        Load-LicenseData `
            -SiteCodes $codes `
            -Countries $countries `
            -Usuario $txtUser.Text `
            -Service $txtLic.Text `
            -HostFilter $txthost.Text `
            -DateDebut $dpDebut.Value `
            -DateFin $dpFin.Value `
            -Grid $grid `
            -StatusLabel $lblStatus
    })

    $btnReset.Add_Click({
        $cmbPays.SelectedIndex = 0
        $checkedSites.Items.Clear()
        $txtUser.Text = ""
        $txtLic.Text = ""
        $txthost.Text = ""
        $dpDebut.Value = (Get-Date).AddDays(-30)
        $dpFin.Value = (Get-Date)
        $grid.DataSource = $null
        $grid.Rows.Clear()
        $grid.Columns.Clear()
        $script:LastSearchContext = $null
        $lblStatus.Text = "Filtres reinitialises."
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(127, 140, 141)
    })

    $btnTest.Add_Click({ Test-DbConnection })
    $btnExport.Add_Click({ Export-GridToCsv })

    [void]$form.ShowDialog()
}

Write-Host "Container : $($script:DbConfig.Container)" -ForegroundColor Gray
Write-Host "Database  : $($script:DbConfig.Database)"  -ForegroundColor Gray
New-StatsForm
