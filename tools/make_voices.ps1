<#
Records CHUDForever's spoken alerts with the voices Windows has (the same ones
the game's text-to-speech uses), one MP3 per phrase and voice:

  Media\Voice\Female\<Phrase>.mp3   Microsoft Zira
  Media\Voice\Male\<Phrase>.mp3     Microsoft David

and writes VoiceList.lua, the list the addon reads. The phrases are in
tools\voice_phrases.txt. The game can't speak on its own when it plays a sound
for a buff ending in combat, so the phrases are recorded ahead of time.

Run from anywhere:
  powershell -ExecutionPolicy Bypass -File tools\make_voices.ps1
Phrases already recorded are skipped; -Force records them all again. The game
only notices new sound files after a full restart (a /reload isn't enough).
#>
param([switch]$Force)

$ErrorActionPreference = "Stop"
$addon = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$phraseFile = Join-Path $addon "tools\voice_phrases.txt"
$voiceDir = Join-Path $addon "Media\Voice"
$listFile = Join-Path $addon "VoiceList.lua"
$voices = [ordered]@{ Female = "Microsoft Zira Desktop"; Male = "Microsoft David Desktop" }

# Phrases ----------------------------------------------------------------------------------

$sections = @{ alerts = New-Object System.Collections.ArrayList; spells = New-Object System.Collections.ArrayList }
$section = $null
foreach ($line in Get-Content -LiteralPath $phraseFile -Encoding UTF8) {
  $text = $line.Trim()
  if ($text -eq "" -or $text.StartsWith("#")) { continue }
  if ($text -match '^\[(\w+)\]$') { $section = $Matches[1]; continue }
  if (-not $sections.ContainsKey($section)) { throw "Phrase outside [alerts] or [spells]: $text" }
  [void]$sections[$section].Add($text)
}

# "Power Word: Shield" -> "PowerWordShield"
function FileName([string]$phrase) {
  $words = ($phrase -replace "[^A-Za-z0-9 ]", "") -split " " | Where-Object { $_ -ne "" }
  ($words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ""
}

$files = [ordered]@{}
foreach ($phrase in @($sections.alerts) + @($sections.spells)) {
  $name = FileName $phrase
  if ($files.Contains($name) -and $files[$name] -ne $phrase) { throw "'$phrase' and '$($files[$name])' would share a file name" }
  $files[$name] = $phrase
}

# Trimming --------------------------------------------------------------------------------
# The synthesizer leaves silence around each phrase and speaks softly; alerts
# should start at once and be about as loud as the game's own sounds.

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;

public static class CombatHudWav {
  // Cuts the silence off both ends of a 16-bit mono WAV, keeps a little
  // padding, fades the edges and raises the loudest sample to 'peak' (0..1).
  public static void Trim(string path, double padStart, double padEnd, double peak) {
    byte[] data = File.ReadAllBytes(path);
    int rate = 44100, start = -1, length = 0, position = 12;
    while (position + 8 <= data.Length) {
      string id = Encoding.ASCII.GetString(data, position, 4);
      int size = BitConverter.ToInt32(data, position + 4);
      if (id == "fmt ") rate = BitConverter.ToInt32(data, position + 12);
      if (id == "data") { start = position + 8; length = Math.Min(size, data.Length - start); break; }
      position += 8 + size + (size & 1);
    }
    if (start < 0) throw new InvalidDataException("No audio in " + path);
    int count = length / 2;
    short[] samples = new short[count];
    Buffer.BlockCopy(data, start, samples, 0, count * 2);
    int loudest = 1;
    for (int i = 0; i < count; i++) loudest = Math.Max(loudest, Math.Abs((int)samples[i]));
    int threshold = loudest / 200; // soft starts like "Th" and "Sh" stay in
    int first = 0, last = count - 1;
    while (first < count && Math.Abs((int)samples[first]) < threshold) first++;
    while (last > first && Math.Abs((int)samples[last]) < threshold) last--;
    first = Math.Max(0, first - (int)(padStart * rate));
    last = Math.Min(count - 1, last + (int)(padEnd * rate));
    int kept = last - first + 1, fade = rate / 200;
    double gain = peak * 32767.0 / loudest;
    short[] output = new short[kept];
    for (int i = 0; i < kept; i++) {
      double value = samples[first + i] * gain;
      if (i < fade) value *= (double)i / fade;
      if (kept - 1 - i < fade) value *= (double)(kept - 1 - i) / fade;
      output[i] = (short)Math.Max(-32768, Math.Min(32767, Math.Round(value)));
    }
    using (BinaryWriter writer = new BinaryWriter(File.Create(path))) {
      writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + kept * 2);
      writer.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
      writer.Write((short)1); writer.Write((short)1); writer.Write(rate); writer.Write(rate * 2);
      writer.Write((short)2); writer.Write((short)16);
      writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(kept * 2);
      byte[] bytes = new byte[kept * 2];
      Buffer.BlockCopy(output, 0, bytes, 0, bytes.Length);
      writer.Write(bytes);
    }
  }
}
"@

# MP3 encoding (Windows' own encoder, through its media API) ----------------------------------

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 }
function Await($operation, [Type]$resultType) {
  $method = $asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
  $task = $method.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait(-1) | Out-Null
  $task.Result
}
function AwaitProgress($action, [Type]$progressType) {
  $method = $asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1' } | Select-Object -First 1
  $task = $method.MakeGenericMethod($progressType).Invoke($null, @($action))
  $task.Wait(-1) | Out-Null
}
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]
[void][Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]

$mp3Profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp3([Windows.Media.MediaProperties.AudioEncodingQuality]::Medium)
$mp3Profile.Audio.ChannelCount = 1
$mp3Profile.Audio.Bitrate = 64000
$transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder

function ToMp3([string]$wav, [string]$folderPath, [string]$name) {
  $source = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($wav)) ([Windows.Storage.StorageFile])
  $folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($folderPath)) ([Windows.Storage.StorageFolder])
  $target = Await ($folder.CreateFileAsync($name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
  $prepared = Await ($transcoder.PrepareFileTranscodeAsync($source, $target, $mp3Profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
  if (-not $prepared.CanTranscode) { throw "Can't encode $name ($($prepared.FailureReason))" }
  AwaitProgress ($prepared.TranscodeAsync()) ([double])
}

# Recording ---------------------------------------------------------------------------------

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$installed = $synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(44100,
  [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$work = Join-Path ([System.IO.Path]::GetTempPath()) "CHUDForeverVoice"
New-Item -ItemType Directory -Force $work | Out-Null
$wav = Join-Path $work "phrase.wav"
$made = 0

foreach ($folderName in $voices.Keys) {
  $voiceName = $voices[$folderName]
  if ($installed -notcontains $voiceName) { throw "Windows voice '$voiceName' isn't installed" }
  $folder = Join-Path $voiceDir $folderName
  New-Item -ItemType Directory -Force $folder | Out-Null
  $synth.SelectVoice($voiceName)
  $synth.Rate = 1
  $synth.Volume = 100
  foreach ($name in $files.Keys) {
    $mp3 = Join-Path $folder "$name.mp3"
    if ((Test-Path -LiteralPath $mp3) -and -not $Force) { continue }
    $synth.SetOutputToWaveFile($wav, $format)
    $synth.Speak($files[$name])
    $synth.SetOutputToNull()
    [CombatHudWav]::Trim($wav, 0.02, 0.08, 0.92)
    ToMp3 $wav $folder "$name.mp3"
    $made++
  }
  # Recordings of phrases no longer on the list.
  Get-ChildItem -LiteralPath $folder -Filter *.mp3 | Where-Object { -not $files.Contains($_.BaseName) } | Remove-Item
}
$synth.Dispose()
Remove-Item -Recurse -Force $work

# The list for the addon ----------------------------------------------------------------------

function LuaString([string]$text) { '"' + ($text -replace '\\', '\\' -replace '"', '\"') + '"' }
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add("-- Spoken phrases, recorded in Media\Voice\Female and Media\Voice\Male.")
[void]$lines.Add("-- Written by tools\make_voices.ps1 from tools\voice_phrases.txt: change the")
[void]$lines.Add("-- list there and run the script again rather than editing this file.")
[void]$lines.Add("local _, ns = ...")
[void]$lines.Add("")
[void]$lines.Add("ns.VOICE = {")
[void]$lines.Add("  -- General phrases, in menu order: { phrase, file }")
[void]$lines.Add("  alerts = {")
foreach ($phrase in $sections.alerts) { [void]$lines.Add("    { $(LuaString $phrase), $(LuaString (FileName $phrase)) },") }
[void]$lines.Add("  },")
[void]$lines.Add("  -- Names of buffs, debuffs and procs: phrase -> file")
[void]$lines.Add("  spells = {")
foreach ($phrase in $sections.spells) { [void]$lines.Add("    [$(LuaString $phrase)] = $(LuaString (FileName $phrase)),") }
[void]$lines.Add("  },")
[void]$lines.Add("}")
[System.IO.File]::WriteAllText($listFile, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

"Recorded $made clips; $($files.Count) phrases in each of $($voices.Count) voices. Wrote VoiceList.lua."
