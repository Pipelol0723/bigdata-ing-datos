<#
  Abre Docker Desktop esquivando el error de los sockets huérfanos de esta laptop.

  El problema (18/10/2026): cada vez que Docker Desktop se cierra, deja sockets AF_UNIX
  (run\dockerInference y docker-secrets-engine\engine.sock) que Windows no deja borrar, y el
  arranque siguiente falla con:
     initializing Inference manager: listening on unix://...\dockerInference:
     remove ...: The file cannot be accessed by the system.

  La solución: antes de abrirlo, mover esas dos carpetas a un costado con la fecha. No se borra
  nada (Windows no lo permite); las carpetas viejas pesan bytes y se pueden borrar tras reiniciar.

  Uso:  .\scripts\iniciar-docker.ps1
#>
$ErrorActionPreference = 'Stop'
Get-Process -Name 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue |
    Stop-Process -Force -Confirm:$false
Start-Sleep -Seconds 3

$sufijo = 'viejo-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
foreach ($carpeta in "$env:LOCALAPPDATA\Docker\run", "$env:LOCALAPPDATA\docker-secrets-engine") {
    if (Test-Path -LiteralPath $carpeta) {
        Rename-Item -LiteralPath $carpeta -NewName ((Split-Path $carpeta -Leaf) + ".$sufijo")
        "movida a un costado: $carpeta"
    }
}

Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
'Docker Desktop lanzado; esperando el motor (hasta 4 min)...'
for ($i = 1; $i -le 48; $i++) {
    Start-Sleep -Seconds 5
    $v = docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { "Docker $v listo tras ~$($i * 5) s"; exit 0 }
}
'Docker no respondió en 4 min: mirar %LOCALAPPDATA%\Docker\backend.error.json'
exit 1
