# Builds Cra for Windows into Windows/build/Cra: Cra.exe, CraHelper.exe, the DLLs SwiftPM
# built, the Swift runtime, and CEF's DLLs and resources. Then checks every DLL is there.
param([ValidateSet('debug', 'release')] [string]$Configuration = 'release')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'fetch-deps.ps1')

# /DEBUG writes a PDB with every function's name, so a crash in the start-up check below can be
# read as a stack (the PDBs stay in the build folder and are not shipped).
swift build --package-path $root -c $Configuration -Xlinker /DEBUG
if ($LASTEXITCODE) { throw 'swift build failed' }
$bin = (swift build --package-path $root -c $Configuration --show-bin-path).Trim()

$out = Join-Path $root 'build\Cra'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item (Join-Path $bin '*.exe'), (Join-Path $bin '*.dll') $out
# Both executables need Resources/app.manifest (Windows 10 support, per-monitor DPI): without
# it Chromium's GPU process crashes and the page area stays black. mt.exe ships with the
# Windows SDK that Swift on Windows already needs.
$mt = (Get-Command mt.exe -ErrorAction SilentlyContinue).Source
if (-not $mt) {
    $mt = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\mt.exe" -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]"0.0" } } -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $mt) { throw 'mt.exe (Windows SDK) not found' }
$manifest = Join-Path $root 'Resources\app.manifest'
foreach ($exe in 'Cra.exe', 'CraHelper.exe') {
    $target = Join-Path $out $exe
    & $mt -nologo -manifest $manifest "-outputresource:$target;#1"
    if ($LASTEXITCODE) { throw "mt.exe could not embed the manifest in $exe" }
    if (-not (Select-String -Path $target -Pattern '8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a' -SimpleMatch -Quiet)) {
        throw "$exe has no embedded manifest"
    }
}
# The icon and version information (Resources/Cra.rc), which Explorer, Task Manager and the
# browser registration's icon read (a registration whose exe had neither was never listed in
# Settings ▸ Default apps). rc.exe ships next to mt.exe; its .res is written into the
# linked executables here because SwiftPM's link flags must stay as they are (see windows.yml).
$rc = Join-Path (Split-Path $mt) 'rc.exe'
if (-not (Test-Path $rc)) { $rc = (Get-Command rc.exe -ErrorAction SilentlyContinue).Source }
if (-not $rc) { throw 'rc.exe (Windows SDK) not found' }
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class CraResources {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResourceW(string file, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateResourceW(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EndUpdateResourceW(IntPtr update, bool discard);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern uint ExtractIconExW(string file, int index, IntPtr[] large, IntPtr[] small, uint count);

    // A .res file is a run of entries: DataSize, HeaderSize, TYPE and NAME (each 0xFFFF and a
    // number, or a string), DataVersion, MemoryFlags, LanguageId, Version, Characteristics, then
    // the data, each entry DWORD-aligned. The first entry is an empty marker.
    public static void Embed(string res, string exe) {
        byte[] b = File.ReadAllBytes(res);
        IntPtr update = BeginUpdateResourceW(exe, false);
        if (update == IntPtr.Zero) throw new Exception("BeginUpdateResource failed: " + Marshal.GetLastWin32Error());
        bool done = false;
        try {
            int at = 0;
            while (at + 8 <= b.Length) {
                int dataSize = BitConverter.ToInt32(b, at), headerSize = BitConverter.ToInt32(b, at + 4);
                int p = at + 8;
                IntPtr type = Id(b, ref p), name = Id(b, ref p);
                p = (p + 3) & ~3;
                ushort language = BitConverter.ToUInt16(b, p + 6);
                if (dataSize > 0) {
                    byte[] data = new byte[dataSize];
                    Array.Copy(b, at + headerSize, data, 0, dataSize);
                    if (!UpdateResourceW(update, type, name, language, data, (uint)dataSize))
                        throw new Exception("UpdateResource failed: " + Marshal.GetLastWin32Error());
                }
                at = (at + headerSize + dataSize + 3) & ~3;
            }
            done = true;
        } finally {
            bool ended = EndUpdateResourceW(update, !done);
            if (done && !ended) throw new Exception("EndUpdateResource failed: " + Marshal.GetLastWin32Error());
        }
    }

    // A numbered resource, or a named one (the string is left allocated: a few per build).
    static IntPtr Id(byte[] b, ref int p) {
        if (BitConverter.ToUInt16(b, p) == 0xFFFF) { IntPtr id = (IntPtr)BitConverter.ToUInt16(b, p + 2); p += 4; return id; }
        int start = p;
        while (BitConverter.ToUInt16(b, p) != 0) p += 2;
        string s = System.Text.Encoding.Unicode.GetString(b, start, p - start);
        p += 2;
        return Marshal.StringToHGlobalUni(s);
    }

    public static uint IconCount(string exe) { return ExtractIconExW(exe, -1, null, null, 0); }
}
'@
Push-Location (Join-Path $root 'Resources')
try {
    foreach ($exe in 'Cra.exe', 'CraHelper.exe') {
        $res = Join-Path $env:TEMP "cra-$exe.res"
        $defines = if ($exe -eq 'CraHelper.exe') { @('/d', 'HELPER') } else { @() }
        & $rc /nologo @defines /fo $res Cra.rc
        if ($LASTEXITCODE) { throw "rc.exe could not compile Cra.rc for $exe" }
        $target = Join-Path $out $exe
        [CraResources]::Embed($res, $target)
        $info = (Get-Item $target).VersionInfo
        if ($info.ProductName -ne 'Cra' -or [CraResources]::IconCount($target) -lt 1) {
            throw "$exe has no icon or version information"
        }
        Write-Host "$exe`: $($info.FileDescription) $($info.FileVersion), $([CraResources]::IconCount($target)) icon(s)"
    }
} finally {
    Pop-Location
}
Get-ChildItem $bin -Directory -Filter '*.resources' | Copy-Item -Destination $out -Recurse
# The Swift runtime (swiftCore, Foundation, Dispatch, ...) is installed with the toolchain, not
# built by SwiftPM, so it is copied from wherever the toolchain put it on PATH.
$runtime = $env:Path -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'swiftCore.dll')) } | Select-Object -First 1
if (-not $runtime) { throw 'Swift runtime (swiftCore.dll) not found on PATH' }
Copy-Item (Join-Path $runtime '*.dll') $out
$cef = Join-Path $root 'vendor\cef'
Copy-Item (Join-Path $cef 'Release\*') $out -Recurse -Exclude '*.lib'
Copy-Item (Join-Path $cef 'Resources\*') $out -Recurse
# Everything shipped is x64: an ARM64 DLL (the Windows App SDK bootstrap once was) fails to
# load and crashes Cra.exe before it opens a window.
foreach ($file in Get-ChildItem $out -Recurse -Include *.exe, *.dll) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $machine = [BitConverter]::ToUInt16($bytes, [BitConverter]::ToInt32($bytes, 0x3c) + 4)
    if ($machine -ne 0x8664) { throw "$($file.FullName) is not x64 (machine 0x$('{0:X4}' -f $machine))" }
}
# Every DLL the executables load must now be in $out: start each with only System32 on PATH.
# 0xC0000135 (STATUS_DLL_NOT_FOUND) means one is missing; a crash code fails the build too, with
# the faulting module from the event log. Cra.exe opens a window, so it is
# stopped after a few seconds if it is still running.
# Runs $exe again under cdb (Windows SDK debugging tools, when installed) and prints the stack
# at the first access violation or fail-fast, with names from the PDBs in $symbols.
function Show-CrashStack([string]$exe, [string]$symbols) {
    $cdb = @("${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
             "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $cdb) { Write-Host 'cdb not found; no stack'; return }
    $stack = '.echo ==== crash; .exr -1; .ecxr; r; kn 40; ub @rip L10; u @rip L3; lm; q'
    $script = Join-Path $env:TEMP 'cra-crash.cdb'
    Set-Content $script @(
        "sxe -c `"$stack`" av",
        "sxe -c `"$stack`" c0000409",
        "sxe -c `"$stack`" c000001d",
        'g',
        'q')
    $log = Join-Path $env:TEMP 'cra-crash.log'
    $d = Start-Process $cdb -ArgumentList @('-G', '-lines', '-y', "`"$symbols`"", '-cf', "`"$script`"", "`"$exe`"") `
        -WorkingDirectory (Split-Path $exe) -RedirectStandardOutput $log -NoNewWindow -PassThru
    if (-not $d.WaitForExit(120000)) { $d.Kill(); Write-Host 'cdb timed out' }
    Get-Content $log | Write-Host
}
$cleanPath = Join-Path $env:SystemRoot 'System32'
$savedPath = $env:Path
$failures = @()
try {
    $env:Path = $cleanPath
    foreach ($exe in 'Cra.exe', 'CraHelper.exe') {
        $started = Get-Date
        $p = Start-Process (Join-Path $out $exe) -WorkingDirectory $out -PassThru
        if (-not $p.WaitForExit(5000)) { $p.Kill(); Write-Host "$exe still running after 5 s"; continue }
        $code = '0x{0:X8}' -f $p.ExitCode
        Write-Host "$exe exited with $code"
        # Missing DLL, Swift trap (illegal instruction), access violation, fail-fast.
        if ($p.ExitCode -in -1073741515, -1073741795, -1073741819, -1073740791) {
            $failures += "$exe exited with $code"
            # Windows Error Reporting names the faulting module and offset.
            Start-Sleep -Seconds 2
            Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $started } -ErrorAction SilentlyContinue |
                Where-Object Message -Match ([regex]::Escape($exe)) | Select-Object -First 1 |
                ForEach-Object { Write-Host $_.Message }
            Show-CrashStack (Join-Path $out $exe) $bin
        }
    }
} finally {
    $env:Path = $savedPath
}
if ($failures) { throw ($failures -join '; ') }
Write-Host "Built $out"
