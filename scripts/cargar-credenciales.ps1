# =============================================================================
#  cargar-credenciales.ps1 -- credenciales del Learner Lab, sin tocar el disco
# =============================================================================
#  COMO SE USA
#    1. En el panel del lab: "AWS Details" -> "AWS CLI" -> boton "Show"
#    2. Copiar TODO el bloque (incluida la linea [default])
#    3. Correr:   .\scripts\cargar-credenciales.ps1
#
#  Si el portapapeles no tiene las credenciales (porque copiaste otra cosa),
#  el script te las pide para pegar a mano. No hace falta ningun orden especial.
#
#  POR QUE ASI Y NO CON 'aws configure'
#    Las credenciales del Learner Lab son TEMPORALES (~4 h) e incluyen un
#    session_token. Si las guardas con 'aws configure' quedan en texto plano
#    en C:\Users\<vos>\.aws\credentials -- un archivo dentro de tu perfil que
#    ademas se respalda/sincroniza sin que te des cuenta.
#    Este script las carga como variables de entorno de ESTA sesion de
#    PowerShell: al cerrar la terminal, se evaporan. Nada queda escrito.
# =============================================================================

$REQUERIDAS = @('aws_access_key_id','aws_secret_access_key','aws_session_token')

function Extraer-Claves([string]$texto) {
    $m = @{}
    if ([string]::IsNullOrWhiteSpace($texto)) { return $m }
    foreach ($linea in ($texto -split "`r?`n")) {
        if ($linea -match '^\s*(aws_access_key_id|aws_secret_access_key|aws_session_token)\s*=\s*(.+?)\s*$') {
            $m[$Matches[1]] = $Matches[2]
        }
    }
    return $m
}

function Estan-Todas($mapa) {
    foreach ($k in $REQUERIDAS) { if (-not $mapa.ContainsKey($k)) { return $false } }
    return $true
}

# --- 1) intento el portapapeles ---------------------------------------------
$claves = @{}
try { $claves = Extraer-Claves (Get-Clipboard -Raw) } catch { }
$oculto = $true

# --- 2) si no estaban, las pido para pegar a mano ---------------------------
if (-not (Estan-Todas $claves)) {
    Write-Host ""
    Write-Host "No encontre las credenciales en el portapapeles." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Pega ahora el bloque de AWS Details -> AWS CLI" -ForegroundColor Cyan
    Write-Host "y despues apreta ENTER en una linea vacia para terminar:" -ForegroundColor Cyan
    Write-Host ""

    $lineas = @()
    while ($true) {
        $l = Read-Host
        if ([string]::IsNullOrWhiteSpace($l)) { break }
        $lineas += $l
    }
    $claves = Extraer-Claves ($lineas -join "`n")
    $oculto = $false
}

# --- 3) validacion -----------------------------------------------------------
if (-not (Estan-Todas $claves)) {
    $faltan = @()
    foreach ($k in $REQUERIDAS) { if (-not $claves.ContainsKey($k)) { $faltan += $k } }
    Write-Host ""
    Write-Host "[X] Falta: $($faltan -join ', ')" -ForegroundColor Red
    Write-Host "    Copia el bloque COMPLETO (las 4 lineas, empezando por [default])."
    exit 1
}

$env:AWS_ACCESS_KEY_ID     = $claves['aws_access_key_id']
$env:AWS_SECRET_ACCESS_KEY = $claves['aws_secret_access_key']
$env:AWS_SESSION_TOKEN     = $claves['aws_session_token']
$env:AWS_DEFAULT_REGION    = 'us-east-1'
$env:AWS_PAGER             = ''

# Si las pegaste a mano quedaron a la vista: limpio la pantalla.
if (-not $oculto) { Clear-Host }

Write-Host ""
Write-Host "[OK] Credenciales cargadas en esta sesion de PowerShell." -ForegroundColor Green
Write-Host "     Region por defecto: us-east-1"
Write-Host ""

# --- 4) verificacion contra AWS (nunca muestra la clave) ---------------------
$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $aws)) {
    Write-Host "[!] No encontre aws.exe. Abri una terminal NUEVA (el PATH se actualizo recien)." -ForegroundColor Yellow
    return
}

Write-Host "Verificando contra AWS..."
$ident = & $aws sts get-caller-identity --output json 2>$null
if ($LASTEXITCODE -eq 0) {
    $o = $ident | ConvertFrom-Json
    Write-Host "[OK] Conectado. Cuenta: $($o.Account)" -ForegroundColor Green
    Write-Host "     Identidad: $($o.Arn)"
    Write-Host ""
    Write-Host "Estas credenciales vencen con la sesion del lab (~4 h)." -ForegroundColor Yellow
    Write-Host "Cuando empiecen a fallar, copia el bloque nuevo y corre esto otra vez."
} else {
    Write-Host "[X] AWS rechazo las credenciales: ya vencieron o estan incompletas." -ForegroundColor Red
    Write-Host "    Volve al lab, apreta 'AWS Details' de nuevo y copia el bloque actualizado."
}
