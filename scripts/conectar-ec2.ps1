# =============================================================================
#  conectar-ec2.ps1 -- averigua todo lo necesario para entrar por SSH a tu EC2
# =============================================================================
#  Solo LEE de AWS. No crea, no modifica y no borra nada.
#  Si falta abrir el puerto 22, te IMPRIME el comando para que lo corras vos.
#
#  USO:
#     .\scripts\cargar-credenciales.ps1     # primero, credenciales del lab
#     .\scripts\conectar-ec2.ps1            # despues, esto
#     .\scripts\conectar-ec2.ps1 -ConfigurarVSCode   # + entrada en ~/.ssh/config
# =============================================================================

param(
    [string]$Clave  = "$env:USERPROFILE\.ssh\vockey.pem",
    [string]$Region = "us-east-1",
    [switch]$ConfigurarVSCode
)

$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $aws)) { Write-Host "[X] No encontre aws.exe. Abri una terminal nueva." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Clave)) { Write-Host "[X] No encontre la clave en $Clave" -ForegroundColor Red; exit 1 }

# --- credenciales vigentes? -------------------------------------------------
& $aws sts get-caller-identity --output json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Credenciales vencidas o no cargadas." -ForegroundColor Red
    Write-Host "    Corre primero:  .\scripts\cargar-credenciales.ps1"
    exit 1
}

# --- mi IP publica, para la regla del security group ------------------------
$miIP = "0.0.0.0"
try { $miIP = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim() } catch { }

Write-Host ""
Write-Host "Tu IP publica: $miIP" -ForegroundColor Cyan
Write-Host "Region:        $Region"
Write-Host ""

# --- instancias corriendo ---------------------------------------------------
$json = & $aws ec2 describe-instances --region $Region `
    --filters "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].{Id:InstanceId,IP:PublicIpAddress,DNS:PublicDnsName,Ami:ImageId,Clave:KeyName,Tipo:InstanceType,SG:SecurityGroups[0].GroupId,Nombre:Tags[?Key=='Name']|[0].Value}" `
    --output json

$instancias = $json | ConvertFrom-Json
if (-not $instancias -or $instancias.Count -eq 0) {
    Write-Host "No hay instancias EC2 corriendo en $Region." -ForegroundColor Yellow
    exit 0
}

foreach ($i in $instancias) {
    Write-Host "=============================================================" -ForegroundColor White
    $etiqueta = $i.Nombre; if (-not $etiqueta) { $etiqueta = "(sin tag Name)" }
    Write-Host " $($i.Id)   $etiqueta   [$($i.Tipo)]"
    Write-Host "=============================================================" -ForegroundColor White

    # --- que usuario SSH corresponde, segun la AMI --------------------------
    $nombreAmi = & $aws ec2 describe-images --region $Region --image-ids $i.Ami `
                    --query "Images[0].Name" --output text 2>$null
    if (-not $nombreAmi) { $nombreAmi = "desconocida" }

    $usuario = "ec2-user"   # Amazon Linux, RHEL, SUSE
    switch -Regex ($nombreAmi) {
        'ubuntu'  { $usuario = "ubuntu";   break }
        'debian'  { $usuario = "admin";    break }
        'bitnami' { $usuario = "bitnami";  break }
        'centos'  { $usuario = "centos";   break }
    }
    Write-Host "  AMI:     $nombreAmi"
    Write-Host "  Usuario: $usuario" -ForegroundColor Green
    Write-Host "  Clave:   $($i.Clave)"

    if ($i.Clave -ne "vockey") {
        Write-Host "  [!] La instancia usa la clave '$($i.Clave)', no 'vockey'." -ForegroundColor Yellow
        Write-Host "      vockey.pem no te va a servir para entrar." -ForegroundColor Yellow
    }

    if (-not $i.IP) {
        Write-Host "  [X] Sin IP publica: la lanzaste en una subnet privada." -ForegroundColor Red
        Write-Host "      Opciones: relanzarla en una subnet publica, o usar Session Manager."
        continue
    }
    Write-Host "  IP:      $($i.IP)"

    # --- el security group deja entrar por el puerto 22? --------------------
    $rangos = & $aws ec2 describe-security-groups --region $Region --group-ids $i.SG `
        --query 'SecurityGroups[].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' `
        --output text 2>$null

    Write-Host ""
    if ([string]::IsNullOrWhiteSpace($rangos)) {
        Write-Host "  [X] El security group $($i.SG) NO tiene abierto el puerto 22." -ForegroundColor Red
        Write-Host "      El SSH va a quedar colgado hasta dar timeout."
        Write-Host ""
        Write-Host "      Para abrirlo SOLO a tu IP (correlo vos si estas de acuerdo):" -ForegroundColor Yellow
        Write-Host "      aws ec2 authorize-security-group-ingress --region $Region ``"
        Write-Host "          --group-id $($i.SG) --protocol tcp --port 22 --cidr $miIP/32"
    } else {
        Write-Host "  [ok] Puerto 22 abierto desde: $rangos" -ForegroundColor Green
        if ($rangos -match '0\.0\.0\.0/0') {
            Write-Host "  [!] Esta abierto al mundo entero. Anda, pero en la vida real" -ForegroundColor Yellow
            Write-Host "      es una mala practica: restringilo a $miIP/32." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  CONECTATE ASI:" -ForegroundColor Cyan
    Write-Host "  ssh -i `"$Clave`" $usuario@$($i.IP)" -ForegroundColor White
    Write-Host ""

    # --- entrada en ~/.ssh/config para VS Code Remote-SSH -------------------
    if ($ConfigurarVSCode) {
        $alias  = "ec2-bigdata"
        $config = "$env:USERPROFILE\.ssh\config"
        $bloque = @"
Host $alias
    HostName $($i.IP)
    User $usuario
    IdentityFile $Clave
    StrictHostKeyChecking accept-new
"@
        $previo = ""
        if (Test-Path $config) { $previo = Get-Content $config -Raw }
        # saca cualquier bloque anterior con el mismo alias (la IP cambia al reiniciar)
        $previo = [regex]::Replace($previo, "(?ms)^Host\s+$alias\s*$.*?(?=^Host\s|\z)", "")
        # WriteAllText escribe UTF8 SIN BOM. Ojo: 'Set-Content -Encoding utf8'
        # en PowerShell 5.1 agrega BOM, y ssh no parsea bien el config con BOM.
        [System.IO.File]::WriteAllText($config, ($previo.TrimEnd() + "`r`n`r`n" + $bloque).TrimStart())
        Write-Host "  [ok] Alias '$alias' escrito en ~/.ssh/config" -ForegroundColor Green
        Write-Host "       VS Code: F1 -> 'Remote-SSH: Connect to Host' -> $alias"
        Write-Host "       Terminal: ssh $alias"
        Write-Host ""
        break   # solo configuramos la primera instancia
    }
}

Write-Host "=============================================================" -ForegroundColor White
Write-Host " RECORDA: la EC2 cobra mientras este 'running'." -ForegroundColor Yellow
Write-Host " En el Learner Lab, DETENERLA NO ALCANZA: se reinicia sola al" -ForegroundColor Yellow
Write-Host " abrir la proxima sesion. Cuando termines, terminala." -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor White
