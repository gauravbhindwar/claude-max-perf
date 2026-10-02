# claude-max-perf installer for Windows PowerShell 5.1 and PowerShell 7+.
#   irm https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.ps1 | iex
# Idempotent: re-run to update. Env overrides:
#   CMP_BASE   raw base URL to download from
#   CMP_SRC    local checkout to copy from instead of downloading
#   CLAUDE_CONFIG_DIR, XDG_CONFIG_HOME   honoured as Claude Code and caveman do
# Nothing runs until Install-ClaudeMaxPerf on the last line, so a partial download does nothing.
# Errors are thrown (not exit) so an interactive `irm | iex` session stays open; -File/-Command exit 1.

function Install-ClaudeMaxPerf {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Windows PowerShell 5.1 may default to TLS 1.0/1.1; GitHub needs TLS 1.2.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    $base = 'https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main'
    if ($env:CMP_BASE) { $base = $env:CMP_BASE.TrimEnd('/') }
    $agents = @('coder', 'strict-reviewer', 'doc-writer')
    $importLine = '@claude-max-perf/RULES.md'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $isWin = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $cwd = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    # PowerShell 7+: parse with System.Text.Json (strict JSON: no comments or trailing commas,
    # no ISO-date conversion). 5.1/6.x fall back to ConvertFrom-Json.
    $stj = $null
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        try { Add-Type -AssemblyName System.Text.Json -ErrorAction Stop } catch { }
        $stj = 'System.Text.Json.JsonDocument' -as [type]
    }

    # ---- helpers -------------------------------------------------------------

    function Resolve-CmpPath([string]$Path) {
        [IO.Path]::GetFullPath([IO.Path]::Combine($cwd, $Path))
    }

    function Show-CmpPath([string]$Path) {
        if ($Path.StartsWith($homeDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            return '~' + $Path.Substring($homeDir.Length)
        }
        return $Path
    }

    function Say([string]$What, [string]$Path, [string]$Note = '') {
        $line = '  {0,-10} {1}' -f $What, (Show-CmpPath $Path)
        if ($Note) { $line += " ($Note)" }
        Write-Host $line
    }

    function New-CmpDir([string]$Path) {
        if (-not [IO.Directory]::Exists($Path)) { [void][IO.Directory]::CreateDirectory($Path) }
    }

    function Get-CmpFile([string]$Rel, [string]$Dst) {
        New-CmpDir (Split-Path -Parent $Dst)
        if ($env:CMP_SRC) {
            $src = Join-Path $env:CMP_SRC $Rel
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "claude-max-perf: missing $src" }
            Copy-Item -LiteralPath $src -Destination $Dst -Force
        } else {
            try {
                Invoke-WebRequest -Uri "$base/$Rel" -OutFile $Dst -UseBasicParsing
            } catch {
                throw "claude-max-perf: download failed: $base/$Rel ($($_.Exception.Message))"
            }
        }
    }

    # JSON text -> OrderedDictionary / List[object] / scalar tree.
    function ConvertTo-CmpNode($Obj) {
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [System.Management.Automation.PSCustomObject]) {
            $d = New-Object System.Collections.Specialized.OrderedDictionary
            foreach ($p in $Obj.PSObject.Properties) { $d[$p.Name] = (ConvertTo-CmpNode $p.Value) }
            return $d
        }
        if ($Obj -is [System.Collections.IList]) {
            $l = New-Object 'System.Collections.Generic.List[object]'
            foreach ($e in $Obj) { $l.Add((ConvertTo-CmpNode $e)) }
            return , $l
        }
        return $Obj
    }

    # System.Text.Json JsonElement -> same tree shape as ConvertTo-CmpNode.
    function ConvertFrom-CmpElement($El) {
        switch ([string]$El.ValueKind) {
            'Object' {
                $d = New-Object System.Collections.Specialized.OrderedDictionary
                foreach ($p in $El.EnumerateObject()) { $d[$p.Name] = (ConvertFrom-CmpElement $p.Value) }
                return $d
            }
            'Array' {
                $l = New-Object 'System.Collections.Generic.List[object]'
                foreach ($e in $El.EnumerateArray()) { $l.Add((ConvertFrom-CmpElement $e)) }
                return , $l
            }
            'String' { return $El.GetString() }
            'Number' {
                [long]$i = 0
                if ($El.TryGetInt64([ref]$i)) { return $i }
                [decimal]$m = 0
                if ($El.TryGetDecimal([ref]$m)) { return $m }
                return $El.GetDouble()
            }
            'True' { return $true }
            'False' { return $false }
            default { return $null }
        }
    }

    # Missing or blank file = {}. Throws when not a single JSON object.
    function Read-CmpJson([string]$Path) {
        if (-not [IO.File]::Exists($Path)) { return (New-Object System.Collections.Specialized.OrderedDictionary) }
        $text = [IO.File]::ReadAllText($Path)
        if ([string]::IsNullOrWhiteSpace($text)) { return (New-Object System.Collections.Specialized.OrderedDictionary) }
        if (-not $text.TrimStart().StartsWith('{')) { throw 'root is not a JSON object' }
        if ($stj) {
            $doc = $stj::Parse([string]$text, (New-Object System.Text.Json.JsonDocumentOptions))
            try {
                if ([string]$doc.RootElement.ValueKind -ne 'Object') { throw 'root is not a JSON object' }
                return (ConvertFrom-CmpElement $doc.RootElement)
            } finally {
                $doc.Dispose()
            }
        }
        $params = @{ InputObject = $text }
        $cfj = (Get-Command ConvertFrom-Json).Parameters
        if ($cfj.ContainsKey('NoEnumerate')) { $params.NoEnumerate = $true }
        if ($cfj.ContainsKey('DateKind')) { $params.DateKind = 'String' }
        $obj = ConvertFrom-Json @params
        if (-not ($obj -is [System.Management.Automation.PSCustomObject])) { throw 'root is not a JSON object' }
        return (ConvertTo-CmpNode $obj)
    }

    function Format-CmpString([string]$s) {
        if ($s -notmatch '[\x00-\x1f"\\]') { return '"' + $s + '"' }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $s.ToCharArray()) {
            $c = [int]$ch
            if ($c -eq 34) { [void]$sb.Append('\"') }
            elseif ($c -eq 92) { [void]$sb.Append('\\') }
            elseif ($c -eq 10) { [void]$sb.Append('\n') }
            elseif ($c -eq 13) { [void]$sb.Append('\r') }
            elseif ($c -eq 9) { [void]$sb.Append('\t') }
            elseif ($c -eq 8) { [void]$sb.Append('\b') }
            elseif ($c -eq 12) { [void]$sb.Append('\f') }
            elseif ($c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $c)) }
            else { [void]$sb.Append($ch) }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }

    # Pretty (2-space, same layout as jq/python/node) or canonical (compact, sorted keys).
    function Format-CmpJson($Value, [int]$Level = 0, [switch]$Canonical) {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $pad = '  ' * ($Level + 1)
        $padEnd = '  ' * $Level
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [System.Collections.Specialized.OrderedDictionary]) {
            [string[]]$keys = @($Value.PSBase.Keys)
            if ($keys.Count -eq 0) { return '{}' }
            if ($Canonical) { [Array]::Sort($keys, [StringComparer]::Ordinal) }
            $items = New-Object 'System.Collections.Generic.List[string]'
            foreach ($k in $keys) {
                $v = Format-CmpJson ($Value[$k]) ($Level + 1) -Canonical:$Canonical
                if ($Canonical) { $items.Add((Format-CmpString $k) + ':' + $v) }
                else { $items.Add($pad + (Format-CmpString $k) + ': ' + $v) }
            }
            if ($Canonical) { return '{' + ($items -join ',') + '}' }
            return "{`n" + ($items -join ",`n") + "`n$padEnd}"
        }
        if ($Value -is [System.Collections.IList]) {
            if ($Value.Count -eq 0) { return '[]' }
            $items = New-Object 'System.Collections.Generic.List[string]'
            foreach ($e in $Value) {
                $v = Format-CmpJson $e ($Level + 1) -Canonical:$Canonical
                if ($Canonical) { $items.Add($v) } else { $items.Add($pad + $v) }
            }
            if ($Canonical) { return '[' + ($items -join ',') + ']' }
            return "[`n" + ($items -join ",`n") + "`n$padEnd]"
        }
        if ($Value -is [string]) { return (Format-CmpString $Value) }
        if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
        if ($Value -is [datetime]) { return (Format-CmpString ($Value.ToString('o', $inv))) }
        if ($Value -is [double] -or $Value -is [single]) { return $Value.ToString('R', $inv) }
        if ($Value -is [IFormattable]) { return $Value.ToString($null, $inv) }
        return (Format-CmpString ([string]$Value))
    }

    # Objects recurse, arrays union (order kept, no new dupes), scalars overwrite.
    function Merge-CmpNode($A, $B) {
        if ($A -is [System.Collections.Specialized.OrderedDictionary] -and $B -is [System.Collections.Specialized.OrderedDictionary]) {
            $out = New-Object System.Collections.Specialized.OrderedDictionary
            foreach ($k in @($A.PSBase.Keys)) { $out[$k] = $A[$k] }
            foreach ($k in @($B.PSBase.Keys)) {
                if ($out.Contains($k)) { $out[$k] = (Merge-CmpNode ($out[$k]) ($B[$k])) }
                else { $out[$k] = $B[$k] }
            }
            return $out
        }
        if ($A -is [System.Collections.IList] -and $B -is [System.Collections.IList]) {
            $out = New-Object 'System.Collections.Generic.List[object]'
            $seen = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($e in $A) { $out.Add($e); [void]$seen.Add((Format-CmpJson $e -Canonical)) }
            foreach ($e in $B) { if ($seen.Add((Format-CmpJson $e -Canonical))) { $out.Add($e) } }
            return , $out
        }
        if ($B -is [System.Collections.IList]) { return , $B }
        return $B
    }

    function Install-CmpFile([string]$Src, [string]$Dst, [bool]$Backup) {
        if ([IO.File]::Exists($Dst)) {
            if ((Get-FileHash -LiteralPath $Src).Hash -eq (Get-FileHash -LiteralPath $Dst).Hash) { Say 'unchanged' $Dst; return }
            if ($Backup) {
                [IO.File]::Copy($Dst, "$Dst.bak-$ts", $true)
                Say 'backup' "$Dst.bak-$ts"
            }
            [IO.File]::WriteAllBytes($Dst, [IO.File]::ReadAllBytes($Src))
            Say 'updated' $Dst
        } else {
            New-CmpDir (Split-Path -Parent $Dst)
            [IO.File]::WriteAllBytes($Dst, [IO.File]::ReadAllBytes($Src))
            Say 'created' $Dst
        }
    }

    # 0 = import present outside code fences (Claude Code ignores imports inside them),
    # 1 = absent, 2 = absent and text ends inside an unclosed fence.
    # CommonMark fences: <=3 spaces, run of >=3 ` or ~ (no ` in a backtick info string);
    # closed only by the same char, run >= opening length, nothing but blanks after.
    function Get-CmpImportState([string]$Text) {
        $fenceChar = ''
        $fenceLen = 0
        foreach ($raw in ($Text -split "`n")) {
            $line = $raw.TrimEnd([char]13)
            $m = [regex]::Match($line, '^ {0,3}(`{3,}|~{3,})(.*)$')
            if ($m.Success) {
                $run = $m.Groups[1].Value
                $rest = $m.Groups[2].Value
                $char = $run.Substring(0, 1)
                if ($fenceChar -eq '') {
                    if ($char -eq '~' -or -not $rest.Contains('`')) {
                        $fenceChar = $char
                        $fenceLen = $run.Length
                        continue
                    }
                } elseif ($char -eq $fenceChar -and $run.Length -ge $fenceLen -and $rest -match '^[ \t]*$') {
                    $fenceChar = ''
                    continue
                }
            }
            if ($fenceChar -eq '' -and $line -cmatch '^ {0,3}@claude-max-perf/RULES\.md[ \t]*$') { return 0 }
        }
        if ($fenceChar -ne '') { return 2 }
        return 1
    }

    function Add-CmpImport([string]$Path) {
        $text = ''
        $bytes = [byte[]]@()
        if ([IO.File]::Exists($Path)) {
            $bytes = [IO.File]::ReadAllBytes($Path)
            $text = [IO.File]::ReadAllText($Path)
        }
        $state = Get-CmpImportState $text
        if ($state -eq 0) { Say 'unchanged' $Path 'import present'; return }
        if ($state -eq 2) {
            Write-Warning "claude-max-perf: $Path ends inside an unclosed code fence; add the line $importLine outside it by hand."
            Say 'skipped' $Path
            return
        }
        if ($text.Length -eq 0) {
            [IO.File]::WriteAllText($Path, "$importLine`n", $utf8)
            Say 'created' $Path 'import added'
            return
        }
        $nl = "`n"
        if ($text.Contains("`r`n")) { $nl = "`r`n" }
        $add = ''
        if (-not $text.EndsWith("`n", [StringComparison]::Ordinal)) { $add = $nl }
        $add += $nl + $importLine + $nl
        # UTF-16/UTF-32 file: appending UTF-8 bytes would corrupt it, so back up and rewrite as UTF-8.
        $wide = ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or
            ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF)
        if ($wide) {
            [IO.File]::Copy($Path, "$Path.bak-$ts", $true)
            Say 'backup' "$Path.bak-$ts"
            [IO.File]::WriteAllText($Path, $text + $add, $utf8)
            Say 'rewrote' $Path 'import added, converted to UTF-8'
            return
        }
        [IO.File]::AppendAllText($Path, $add, $utf8)
        Say 'appended' $Path 'import added'
    }

    # True when the file starts with a UTF-8 BOM (Node's JSON.parse, used by caveman, rejects it).
    function Test-CmpBom([string]$Path) {
        if (-not [IO.File]::Exists($Path)) { return $false }
        $b = [IO.File]::ReadAllBytes($Path)
        return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    }

    # Write merged JSON (UTF-8, no BOM) only when its value changes or the file has a BOM;
    # back up the original first.
    function Set-CmpJson([string]$Path, $Original, $Merged) {
        $exists = [IO.File]::Exists($Path)
        if ($exists -and -not (Test-CmpBom $Path) -and
            ((Format-CmpJson $Original -Canonical) -ceq (Format-CmpJson $Merged -Canonical))) { Say 'unchanged' $Path; return }
        New-CmpDir (Split-Path -Parent $Path)
        $text = (Format-CmpJson $Merged) + "`n"
        if ($exists) {
            [IO.File]::Copy($Path, "$Path.bak-$ts", $true)
            Say 'backup' "$Path.bak-$ts"
            [IO.File]::WriteAllText($Path, $text, $utf8)
            Say 'merged' $Path
        } else {
            [IO.File]::WriteAllText($Path, $text, $utf8)
            Say 'created' $Path
        }
    }

    function Invoke-CmpClaude([string]$Exe, [string[]]$CmdArgs, [string]$Label) {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Exe @CmdArgs 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -eq 0) {
            Write-Host ('  {0,-10} {1}' -f 'plugin', $Label)
        } else {
            $last = @($lines | Where-Object { $_.Trim() }) | Select-Object -Last 1
            Write-Warning "claude-max-perf: $Label failed (continuing): $last"
        }
    }

    # ---- paths ---------------------------------------------------------------

    if ($env:CLAUDE_CONFIG_DIR) { $cfg = Resolve-CmpPath $env:CLAUDE_CONFIG_DIR } else { $cfg = Join-Path $homeDir '.claude' }
    if ($env:XDG_CONFIG_HOME) {
        $caveDir = Join-Path (Resolve-CmpPath $env:XDG_CONFIG_HOME) 'caveman'
    } elseif ($isWin) {
        $appData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $homeDir 'AppData\Roaming' }
        $caveDir = Join-Path $appData 'caveman'
    } else {
        $caveDir = Join-Path (Join-Path $homeDir '.config') 'caveman'
    }
    $settingsPath = Join-Path $cfg 'settings.json'
    $cavePath = Join-Path $caveDir 'config.json'

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('claude-max-perf-' + [guid]::NewGuid().ToString('N'))
    New-CmpDir $tmp
    try {
        # Stage 1: fetch everything and validate before touching any user file.
        $src = Join-Path $tmp 'src'
        Get-CmpFile 'RULES.md' (Join-Path $src 'RULES.md')
        Get-CmpFile 'settings.fragment.json' (Join-Path $src 'settings.fragment.json')
        foreach ($a in $agents) { Get-CmpFile "agents/$a.md" (Join-Path (Join-Path $src 'agents') "$a.md") }

        try { $fragment = Read-CmpJson (Join-Path $src 'settings.fragment.json') }
        catch { throw "claude-max-perf: settings.fragment.json from source is not a JSON object: $($_.Exception.Message)" }
        try { $settings = Read-CmpJson $settingsPath }
        catch { throw "claude-max-perf: $settingsPath is not valid JSON (object expected): $($_.Exception.Message). Fix it and re-run. Nothing was changed." }
        $settingsMerged = Merge-CmpNode $settings $fragment
        # Invalid caveman config: warn and skip that step only.
        $caveErr = $null
        try {
            $cave = Read-CmpJson $cavePath
            $caveFragment = New-Object System.Collections.Specialized.OrderedDictionary
            $caveFragment['defaultMode'] = 'ultra'
            $caveMerged = Merge-CmpNode $cave $caveFragment
        } catch {
            $caveErr = $_.Exception.Message
        }

        # Stage 2: apply.
        Write-Host "claude-max-perf: installing into $(Show-CmpPath $cfg)"
        New-CmpDir (Join-Path $cfg 'claude-max-perf')
        New-CmpDir (Join-Path $cfg 'agents')
        Install-CmpFile (Join-Path $src 'RULES.md') (Join-Path (Join-Path $cfg 'claude-max-perf') 'RULES.md') $false
        Add-CmpImport (Join-Path $cfg 'CLAUDE.md')
        foreach ($a in $agents) {
            Install-CmpFile (Join-Path (Join-Path $src 'agents') "$a.md") (Join-Path (Join-Path $cfg 'agents') "$a.md") $true
        }
        Set-CmpJson $settingsPath $settings $settingsMerged
        if ($null -eq $caveErr) {
            Set-CmpJson $cavePath $cave $caveMerged
        } else {
            Write-Warning "claude-max-perf: $cavePath is not valid JSON (object expected): $caveErr. Left unchanged; set ""defaultMode"": ""ultra"" in it by hand."
            Say 'skipped' $cavePath
        }

        $claude = Get-Command claude -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($claude) {
            Invoke-CmpClaude $claude.Source @('plugin', 'marketplace', 'add', 'JuliusBrussee/caveman') 'marketplace caveman added'
            Invoke-CmpClaude $claude.Source @('plugin', 'install', 'caveman@caveman') 'caveman@caveman installed'
        } else {
            Write-Host '  note       claude CLI not on PATH; enabledPlugins in settings.json enables caveman on next launch'
        }
        Write-Host 'claude-max-perf: done. Restart Claude Code to load the rules.'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Ignore
    }
}

Install-ClaudeMaxPerf
