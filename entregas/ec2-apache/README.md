# Práctico: EC2 + Apache

**Fecha:** 2026-08-06 · **Región:** us-east-1a

Levantar una instancia EC2, acceder por SSH desde local y servir una página web
en el puerto 80.

## Lo que se creó

| Recurso | Valor |
|---|---|
| Instancia | `i-082829eaed67d7086` — `t3.micro`, Ubuntu 26.04 LTS |
| Recursos | 2 vCPU · 908 MB RAM · sin swap · 6.7 GB disco |
| Key pair | `vockey` (la del Learner Lab) |
| Security Group | `sg-06269c038daa2d634` (`launch-wizard-1`) |
| VPC / Subnet | `vpc-099e92d8e5feb8b90` / `subnet-0e44e937b437991a7` |
| IP pública | `54.90.158.108` ⚠️ cambia en cada reinicio |

### Reglas de entrada (las que pidió el profesor)

| Tipo | Protocolo | Puerto | Origen |
|---|---|---|---|
| SSH | TCP | 22 | `0.0.0.0/0` |
| HTTP | TCP | 80 | `0.0.0.0/0` |

## Cómo se rehace

En el Learner Lab la instancia no sobrevive, así que esta es la receta para
recrearla desde cero.

**1. Lanzar la instancia** — consola EC2, AMI Ubuntu, tipo `t3.micro`, key pair
`vockey`, y en *Network settings* marcar **Allow SSH traffic** y **Allow HTTP
traffic** (eso genera el `launch-wizard-N` con las dos reglas de arriba).

**2. Preparar el acceso local** (una sola vez por máquina):

```powershell
# la clave privada, con permisos que OpenSSH acepte
icacls "$env:USERPROFILE\.ssh\vockey.pem" /inheritance:r
icacls "$env:USERPROFILE\.ssh\vockey.pem" /grant:r "$($env:USERNAME):(R)"
```

**3. Generar el alias SSH** con la IP nueva:

```powershell
.\scripts\cargar-credenciales.ps1
.\scripts\conectar-ec2.ps1 -ConfigurarVSCode
```

**4. Instalar Apache y publicar la página:**

```bash
ssh ec2-bigdata "sudo apt update && sudo apt install -y apache2"
scp entregas/ec2-apache/index.html ec2-bigdata:/tmp/index.html
ssh ec2-bigdata "sudo mv /tmp/index.html /var/www/html/index.html"
```

**5. Verificar desde afuera:**

```bash
curl -I http://<IP-PUBLICA>
```

Tiene que devolver `HTTP/1.1 200 OK`.

## Notas

- El usuario SSH es **`ubuntu`** porque la AMI es Ubuntu. En Amazon Linux sería
  `ec2-user`. Errar el usuario da *Permission denied* aunque la clave esté bien.
- **VS Code Remote-SSH no necesita puerto extra**: su server escucha en
  `127.0.0.1` dentro de la instancia y el tráfico va tuneleado por el 22.
- Con 908 MB de RAM y sin swap, el VS Code Server (~150-250 MB) deja poco
  margen. Si la conexión se corta sola, es el OOM killer: agregar 1 GB de swap.
- `0.0.0.0/0` en el 22 es lo que pidió el ejercicio, pero en un caso real va
  restringido a la IP propia (`/32`).
