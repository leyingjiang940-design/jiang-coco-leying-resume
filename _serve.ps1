$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$port = 8944
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Output "READY http://localhost:$port/"
$ct = @{
  '.html'='text/html; charset=utf-8'; '.js'='text/javascript'; '.mjs'='text/javascript';
  '.css'='text/css'; '.json'='application/json';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.webp'='image/webp'; '.gif'='image/gif'; '.svg'='image/svg+xml';
  '.woff'='font/woff'; '.woff2'='font/woff2'; '.mp3'='audio/mpeg'; '.mp4'='video/mp4'; '.webm'='video/webm';
  '.pdf'='application/pdf'; '.pptx'='application/vnd.openxmlformats-officedocument.presentationml.presentation'; '.docx'='application/vnd.openxmlformats-officedocument.wordprocessingml.document'; '.doc'='application/msword'; '.txt'='text/plain'
}
function SendBytes($res, $bytes, $status, $ctype) {
  $res.StatusCode = $status
  $res.ContentType = $ctype
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}
while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $req = $ctx.Request; $res = $ctx.Response
    $raw = $req.Url.AbsolutePath
    $rel = if ($raw -eq '/') { 'index.html' } else { $raw.TrimStart('/') }
    $full = Join-Path $root ($rel -replace '/', '\')
    if ((Test-Path $full -PathType Leaf) -and $full.StartsWith($root)) {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $ctype = if ($ct.ContainsKey($ext)) { $ct[$ext] } else { 'application/octet-stream' }
      $res.Headers.Add('Accept-Ranges', 'bytes')
      $fi = [System.IO.FileInfo]::new($full)
      $size = $fi.Length
      $rangeHeader = $req.Headers['Range']
      if ($rangeHeader -and $rangeHeader -match 'bytes=(\d*)-(\d*)') {
        $start = if ($matches[1] -ne '') { [int64]$matches[1] } else { 0 }
        $end = if ($matches[2] -ne '') { [int64]$matches[2] } else { $size - 1 }
        if ($start -ge $size -or $end -ge $size) {
          $res.StatusCode = 416
          $res.Headers.Add('Content-Range', "bytes */$size")
          $res.Close(); continue
        }
        if ($end -gt $size - 1) { $end = $size - 1 }
        $len = $end - $start + 1
        $res.StatusCode = 206
        $res.ContentType = $ctype
        $res.Headers.Add('Content-Range', "bytes $start-$end/$size")
        $res.ContentLength64 = $len
        $fs = [System.IO.File]::OpenRead($full)
        try {
          $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
          $buf = New-Object byte[] 65536
          $remaining = $len
          while ($remaining -gt 0) {
            $toRead = [Math]::Min($buf.Length, $remaining)
            $n = $fs.Read($buf, 0, $toRead)
            if ($n -le 0) { break }
            $res.OutputStream.Write($buf, 0, $n)
            $remaining -= $n
          }
        } finally { $fs.Close() }
      } else {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        SendBytes $res $bytes 200 $ctype
      }
    } else {
      $body = [System.Text.Encoding]::UTF8.GetBytes('not found')
      $res.StatusCode = 404
      $res.ContentType = 'text/plain'
      $res.ContentLength64 = $body.Length
      $res.OutputStream.Write($body, 0, $body.Length)
    }
    $res.Close()
  } catch {
    try { $res.Close() } catch {}
  }
}
