param(
    [string]$LexerPath
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
if (-not $LexerPath) {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\.build\lexer.exe'),
        (Join-Path $PSScriptRoot '..\lexer.exe')
    )
    $LexerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $LexerPath) { throw 'lexer.exe не найден. Укажите путь параметром -LexerPath.' }
}
$LexerPath = (Resolve-Path -LiteralPath $LexerPath).Path
Write-Host "Лексер: $LexerPath"
Write-Host ''
# Подключаем DLL MinGW, если рядом с lexer.exe есть CMakeCache.txt.
$cachePath = Join-Path (Split-Path -Parent $LexerPath) 'CMakeCache.txt'
if (Test-Path -LiteralPath $cachePath) {
    $compilerLine = Get-Content -LiteralPath $cachePath | Where-Object { $_ -match '^CMAKE_CXX_COMPILER:[^=]+=' } | Select-Object -First 1
    if ($compilerLine) {
        $compilerDirectory = Split-Path -Parent ($compilerLine -replace '^[^=]+=', '')
        if (Test-Path -LiteralPath $compilerDirectory -PathType Container) {
            $env:PATH = $compilerDirectory + ';' + $env:PATH
        }
    }
}
$cases = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'cases') -Filter '*.st' | Sort-Object Name)
if ($cases.Count -eq 0) { throw 'No test files found.' }

$requiredTypes = @(
    'IDENTIFIER', 'KEYWORD', 'BINARY_SELECTOR', 'MINUS', 'BAR',
    'SELF', 'SUPER', 'TRUE', 'FALSE', 'NIL', 'INTEGER', 'FLOAT',
    'SCALED_DECIMAL', 'CHARACTER', 'STRING', 'SYMBOL_LITERAL', 'SELECTOR_LITERAL',
    'ASSIGN', 'RETURN', 'LPAREN', 'RPAREN', 'LBRACKET', 'RBRACKET',
    'HASH', 'COLON', 'PERIOD', 'SEMICOLON', 'CHUNK_END',
    'LBRACE', 'RBRACE', 'SCOPE_SEPARATOR', 'ERROR'
)
$covered = @{}
$passed = 0
$failed = 0
$number = 0

foreach ($case in $cases) {
    $expectedPath = [IO.Path]::ChangeExtension($case.FullName, 'expected.txt')
    $expected = [IO.File]::ReadAllText($expectedPath).Replace("`r`n", "`n")
    $expected = $expected.Replace("`r", "`n").TrimEnd([char]10)
    $expectedLines = $expected.Split([char]10)
    if ($expectedLines[-1] -notmatch '^\d+ tokens, (\d+) lexical errors$') {
        throw "Invalid expected summary: $expectedPath"
    }
    $expectedExit = if ([int]$Matches[1] -eq 0) { 0 } else { 1 }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $LexerPath
    $info.Arguments = '"' + $case.FullName + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            $process.Kill()
            throw "Lexer timed out: $($case.Name)"
        }
        $actual = $outputTask.GetAwaiter().GetResult().Replace("`r`n", "`n")
        $actual = $actual.Replace("`r", "`n").TrimEnd([char]10)
        $stderr = $errorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }

    $number++
    Write-Host "$number) $($case.BaseName -replace '^\d+_', '')"
    Write-Host ''
    Write-Host 'Строка:'
    $source = [IO.File]::ReadAllText($case.FullName)
    if ($source.Length -eq 0) { Write-Host '(пустой ввод)' } else { Write-Host $source }
    Write-Host 'Ожидание:'
    Write-Host $expected
    Write-Host 'Выход:'
    Write-Host $actual
    if ($actual -ceq $expected -and $exitCode -eq $expectedExit -and $stderr.Length -eq 0) {
        Write-Host '+' -ForegroundColor Green
        $passed++
        foreach ($line in $actual.Split([char]10)) {
            if ($line -match '^\d+:\d+  ([A-Z_]+)  value=') { $covered[$Matches[1]] = $true }
        }
    } else {
        Write-Host '-' -ForegroundColor Red
        Write-Host "Код завершения: ожидание $expectedExit, выход $exitCode"
        if ($stderr.Length -gt 0) { Write-Host $stderr }
        $actualLines = $actual.Split([char]10)
        for ($i = 0; $i -lt [Math]::Max($expectedLines.Count, $actualLines.Count); $i++) {
            $wanted = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { '<no line>' }
            $received = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { '<no line>' }
            if ($wanted -cne $received) {
                Write-Host "Output line $($i + 1):"
                Write-Host "  expected: $wanted"
                Write-Host "  got:      $received"
                break
            }
        }
        $failed++
    }
    Write-Host ''
}

$missing = @($requiredTypes | Where-Object { -not $covered.ContainsKey($_) })
if ($missing.Count -gt 0) {
    Write-Host "Missing token types: $($missing -join ', ')" -ForegroundColor Red
    $failed++
}
Write-Host "Пройдено: $passed; ошибок проверки: $failed; типов токенов: $($requiredTypes.Count - $missing.Count)."
if ($failed -gt 0) { exit 1 }
exit 0

