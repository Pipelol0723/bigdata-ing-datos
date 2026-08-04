# =============================================================================
#  cargar-credenciales.ps1 -- credenciales del Learner Lab, sin tocar el disco
# =============================================================================
#  COMO SE USA
#    1. En el panel del lab: "AWS Details" -> "AWS CLI" -> boton "Show"
#    2. Copiar TODO el bloque (incluida la linea [default])
#    3. En PowerShell, parado en la carpeta del curso:
#         .\scripts\cargar-credenciales.ps1
#
#  POR QUE ASI Y NO CON 'aws configure'
#    Las credenciales del Learner Lab son TEMPORALES (~4 h) y incluyen un
#    session_token. Si las guardas con 'aws configure' quedan en texto plano
#    en C:\Users\<vos>\.aws\credentials -- un archivo que ademas vive dentro
#    de tu perfil y se sincroniza/respalda sin que te des cuenta.
#    Este script las carga como variables de entorno de ESTA sesion: cuando
#    cerras la terminal, se evaporan. Nada queda escrito.
# =============================================================================

$texto = Get-Clipboard -Raw

if ([string]::IsNullOrWhiteSpace($texto)) {
    Write-Host "[X] El portapapeles esta vacio." -ForegroundColor Red
    Write-Host "    Copia el bloque de AWS Details -> AWS CLI y volve a correr esto."
    exit 1
}

$claves = @{}
foreach ($linea in ($texto -split "`r?`n")) {
    if ($linea -match '^\s*(aws_access_key_id|aws_secret_access_key|aws_session_token)\s*=\s*(.+?)\s*$') {
        $claves[$Matches[1]] = $Matches[2]
    }
}

$faltantes = @()
foreach ($k in @('aws_access_key_id','aws_secret_access_key','aws_session_token')) {
    if (-not $claves.ContainsKey($k)) { $faltantes += $k }
}

if ($faltantes.Count -gt 0) {
    Write-Host "[X] No encontre en el portapapeles: $($faltantes -join ', ')" -ForegroundColor Red
    Write-Host "    Asegurate de copiar el bloque COMPLETO, no solo una linea."
    exit 1
}

$env:AWS_ACCESS_KEY_ID     = $claves['aws_access_key_id']
$env:AWS_SECRET_ACCESS_KEY = $claves['aws_secret_access_key']
$env:AWS_SESSION_TOKEN     = $claves['aws_session_token']
$env:AWS_DEFAULT_REGION    = 'us-east-1'
$env:AWS_PAGER             = ''

Write-Host ""
Write-Host "[OK] Credenciales cargadas en esta sesion de PowerShell." -ForegroundColor Green
Write-Host "     Region por defecto: us-east-1"
Write-Host ""

# Verificacion contra AWS. Solo muestra la cuenta, nunca la clave.
$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (Test-Path $aws) {
    Write-Host "Verificando contra AWS..."
    $ident = & $aws sts get-caller-identity --output json
    if ($LASTEXITCODE -eq 0) {
        $o = $ident | ConvertFrom-Json
        Write-Host "[OK] Conectado. Cuenta: $($o.Account)" -ForegroundColor Green
        Write-Host "     Identidad: $($o.Arn)"
        Write-Host ""
        Write-Host "Recorda: estas credenciales vencen con la sesion del lab (~4 h)." -ForegroundColor Yellow
        Write-Host "Cuando empiecen a fallar, volve a copiar el bloque y corre esto de nuevo."
    } else {
        Write-Host "[X] AWS rechazo las credenciales. Probablemente ya vencieron." -ForegroundColor Red
        Write-Host "    Reinicia el lab, copia el bloque nuevo y volve a intentar."
    }
} else {
    Write-Host "[!] No encontre aws.exe. Abri una terminal NUEVA (el PATH se actualizo recien)." -ForegroundColor Yellow
}
