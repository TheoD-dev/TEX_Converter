# Maakt op Windows het Linux-downloadbestand (tar.gz) van een op Linux gecompileerd programma.
#
# Gebruik (in de projectmap, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File make-linux-release.ps1
#
# Waarom zelf een tar-bestand schrijven? Op Linux moet het programma het recht "uitvoerbaar"
# hebben, anders start het niet. Een zip-bestand en de tar van Windows bewaren dat recht niet;
# hier zetten we het zelf in het tar-bestand (mode 755).

param(
  [string]$Binary  = "SS1TexConverter2.x64",   # het op Linux gecompileerde programma
  [string]$Version = "1.00"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$name = "SS-TexConverter-$Version-Linux"
$out  = Join-Path $PSScriptRoot "Release\$name.tar.gz"
if (-not (Test-Path $Binary)) { throw "$Binary not found. Compile TexConverter.pb on Linux first." }
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot "Release") | Out-Null

$ascii = [Text.Encoding]::ASCII
$mtime = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

# Schrijft een getal als octale tekst van Width tekens (met een 0-byte erachter).
function Octal([int64]$value, [int]$width) {
  [Convert]::ToString($value, 8).PadLeft($width - 1, '0') + [char]0
}

# Maakt de kop (512 bytes) van één bestand of map in het tar-bestand (USTAR-formaat).
function TarHeader([string]$path, [int64]$size, [string]$mode, [char]$type) {
  $h = New-Object byte[] 512
  $ascii.GetBytes($path).CopyTo($h, 0)                      # naam (max. 100 tekens)
  $ascii.GetBytes((Octal ([Convert]::ToInt64($mode, 8)) 8)).CopyTo($h, 100)
  $ascii.GetBytes((Octal 0 8)).CopyTo($h, 108)              # gebruiker
  $ascii.GetBytes((Octal 0 8)).CopyTo($h, 116)              # groep
  $ascii.GetBytes((Octal $size 12)).CopyTo($h, 124)
  $ascii.GetBytes((Octal $mtime 12)).CopyTo($h, 136)
  $h[156] = [byte][char]$type                               # '0' = bestand, '5' = map
  $ascii.GetBytes("ustar").CopyTo($h, 257) ; $h[262] = 0
  $ascii.GetBytes("00").CopyTo($h, 263)
  # Controlegetal: som van alle bytes, met het controleveld zelf als 8 spaties
  for ($i = 148; $i -lt 156; $i++) { $h[$i] = 32 }
  $sum = 0 ; foreach ($b in $h) { $sum += $b }
  $ascii.GetBytes([Convert]::ToString($sum, 8).PadLeft(6, '0') + [char]0 + " ").CopyTo($h, 148)
  return ,$h
}

$tar = New-Object IO.MemoryStream
function AddDir([string]$path) {
  $h = TarHeader "$path/" 0 "755" '5' ; $tar.Write($h, 0, 512)
}
function AddFile([string]$source, [string]$path, [string]$mode) {
  $data = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $source))
  $h = TarHeader $path $data.Length $mode '0' ; $tar.Write($h, 0, 512)
  $tar.Write($data, 0, $data.Length)
  $pad = (512 - ($data.Length % 512)) % 512                 # aanvullen tot een veelvoud van 512
  if ($pad) { $tar.Write((New-Object byte[] $pad), 0, $pad) }
}

AddDir  $name
AddFile $Binary     "$name/SS1TexConverter2" "755"           # uitvoerbaar
AddFile "README.md" "$name/README.md" "644"
AddFile "LICENSE"   "$name/LICENSE"   "644"
AddDir  "$name/Help"
AddFile "Help\TexConverter-Help.html" "$name/Help/TexConverter-Help.html" "644"
$tar.Write((New-Object byte[] 1024), 0, 1024)               # einde: twee lege blokken

# Inpakken met gzip
$file = [IO.File]::Create($out)
$gz = New-Object IO.Compression.GZipStream($file, [IO.Compression.CompressionMode]::Compress)
$bytes = $tar.ToArray() ; $gz.Write($bytes, 0, $bytes.Length)
$gz.Close() ; $file.Close()
Write-Host "Done: $out"
