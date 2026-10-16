# Attendance · laboratorio AWS con Terraform

Crea dos instancias EC2 propias: frontend React con Nginx y backend NestJS conectado
a la base de datos existente en Supabase. Usa una VPC independiente; 
Cada compañero debe usar su propio nombre de despliegue, clave y estado.

## Arquitectura y alcance

```text
Navegador -> frontend:80 (Nginx, React dist)
                         |
                         +-> /core/api/v1 -> IP privada backend:5000
                                              |
                                              +-> Supabase Session pooler:5432 (SSL)
```

- Ubuntu 24.04 oficial de Canonical, Node.js 24.19.0 y pnpm 10.11.0.
- Dos `t3.small` por defecto, cada una con 20 GiB gp3 cifrados y 2 GiB de swap.
- HTTP público; SSH solo desde la IPv4 `/32` del operador.
- La API solo acepta tráfico del grupo de seguridad del frontend. No se instala
  PostgreSQL en las EC2. Ambas máquinas tienen IPv4 pública para instalar paquetes
  y permitir SSH; no se usa NAT Gateway, balanceador ni RDS en esta práctica.
- NestJS se inicia con systemd. Las variables del backend se preparan localmente,
  se transfieren por SSH y se instalan en `/etc/attendance/backend.env` con permisos
  de lectura restringidos. No pasan por Terraform ni por sus archivos de estado.
- No se ejecutan migraciones, seeds ni creación de bases de datos. Las tablas,
  tenants y usuarios deben existir previamente en Supabase. No se crea el superadmin.

## Requisitos locales

Terraform >= 1.10 y < 2, AWS CLI v2, Git, jq, curl, OpenSSH y Bash. Configura tus
credenciales fuera del repositorio:

```bash
aws configure --profile attendance-terraform
aws sts get-caller-identity --profile attendance-terraform
```

No se necesita `terraform login`. El proveedor usa el perfil AWS indicado y
verifica que la cuenta sea la esperada. No guardes access keys en `.tf` o `.tfvars`.

Los clones de las aplicaciones deben estar junto a este repositorio:

```text
develop/
  attendance/            # https://github.com/Jalter-ego/attendance-web
  attendance_core/       # https://github.com/Jalter-ego/attendance-core
  attendance_terraform/  # este repositorio
```

Como las aplicaciones son privadas, el operador debe poder descargarlas desde
GitHub en su computadora. El despliegue genera paquetes de commits con `git archive`
y los copia a las EC2 por SSH; no necesita deploy keys de GitHub en las instancias.
Nunca empaqueta los archivos locales sin confirmar ni los `.env` ignorados por Git.

## 1. Preparar la configuración local

Desde la raíz de este repositorio:

```bash
export AWS_PROFILE=attendance-terraform
export ATTENDANCE_DEPLOYMENT=attendance-tf-tu-nombre
./scripts/prepare.sh
```

El script consulta la cuenta, la región del perfil y la IP pública de tu conexión.
Genera una clave SSH de operador en `.local/ssh/` y crea
`infra/lab.auto.tfvars.json`. Estos archivos están excluidos de Git. Si ya existe
la configuración, el script no la sobrescribe. Puedes editarla o usar como base
`examples/lab.tfvars.example`.

La clave es para entrar a EC2; no es una deploy key de GitHub. Conserva la clave y
el estado para administrar este entorno. Si cambia tu IP de salida, actualiza
`ssh_allowed_cidr` y revisa/aplica un nuevo plan.

Prepara por separado el archivo privado de variables del backend:

```bash
./scripts/prepare-env.sh
nano .local/backend.env
```

El archivo está excluido de Git y tiene permisos `600`. Completa el usuario
`postgres.PROJECT_REF`, las contraseñas de lectura y escritura y comprueba los
datos de conexión del panel de Supabase. El script genera `JWT_SECRET` aleatoriamente
una sola vez; no reemplaza archivos existentes. Conserva ese valor para mantener
la firma de las sesiones entre despliegues. Si ya tienes un secreto válido que
deba mantenerse, configúralo en ese archivo.

La plantilla es `examples/backend.env.example`: usa `PORT=5000`, `DB_SSL=true`,
el Session pooler de Supabase en puerto `5432` y `JWT_EXPIRES_IN=8h`.
`CORS_ORIGIN=*` es un valor literal, sin barra inversa ni asteriscos de Markdown.
También puedes indicar los orígenes concretos del frontend; el despliegue conserva
el valor configurado. Para contraseñas que contengan `#` o espacios, utiliza comillas
simples o dobles siguiendo el formato dotenv. No se evalúan como comandos de shell.

Puedes elegir otro archivo con `ATTENDANCE_BACKEND_ENV=/ruta/privada/backend.env`.
No guardes credenciales en `lab.auto.tfvars.json` ni en el frontend.

## 2. Validar y revisar el plan

```bash
terraform -chdir=infra init
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra test
node --test --test-isolation=none tests/environment.test.cjs
terraform -chdir=infra plan -out=../.local/lab.tfplan
terraform -chdir=infra show ../.local/lab.tfplan
```

Las pruebas usan un proveedor simulado y no crean recursos. El plan real consulta
AWS. Comprueba cuenta, región, dos instancias, tipos de instancia, discos y reglas
de acceso antes de aplicar. No reutilices estados ni claves del laboratorio de
OpenTofu.

## 3. Crear las instancias

```bash
terraform -chdir=infra apply ../.local/lab.tfplan
terraform -chdir=infra output
```

Terraform crea las máquinas; cloud-init instala los componentes durante el primer
arranque. El siguiente script espera a que esa preparación termine. No vuelvas a
ejecutar cloud-init para actualizar una aplicación.

## 4. Publicar versiones de las aplicaciones

Actualiza las referencias remotas sin cambiar tus ramas de trabajo:

```bash
git -C ../attendance fetch origin master
git -C ../attendance_core fetch origin master
./scripts/deploy.sh
./scripts/verify.sh
```

Por defecto se publica el commit de `origin/master` de cada clon. Puedes elegir
otra referencia, etiqueta o SHA, y cambiar las rutas de los clones:

```bash
ATTENDANCE_FRONTEND_SOURCE=../attendance \
ATTENDANCE_BACKEND_SOURCE=../attendance_core \
ATTENDANCE_FRONTEND_REF=origin/master \
ATTENDANCE_BACKEND_REF=origin/master \
./scripts/deploy.sh
```

El script compila en cada EC2, valida y copia las variables del backend y publica
frontend y backend. No ejecuta migraciones ni seeds contra Supabase. Guarda los commits elegidos en
`.local/releases.json`. El frontend se compila con `VITE_API_URL=/core/api/v1`;
Nginx conserva ese prefijo al enviar las solicitudes a la IP privada de la API.
El puerto 5173 y el servidor de desarrollo de Vite no se usan en AWS.

El dominio base del frontend se calcula a partir de su IP pública: para
`3.143.17.104` será `3-143-17-104.sslip.io`. Se pasa como
`VITE_TENANT_BASE_DOMAIN` durante la compilación para identificar el tenant.
Para actualizar únicamente el frontend, sin transferir variables ni reiniciar
el backend, ejecuta `./scripts/deploy.sh --frontend-only`.

El archivo dotenv se interpreta con la misma biblioteca del backend, se convierte
al formato de systemd y se guarda con permisos `600`. El archivo temporal de
transferencia se elimina al terminar. Los errores de validación muestran nombres
de variables, no contraseñas. El servicio reinicia después de instalar el entorno.
Cambios posteriores deben hacerse en el archivo local antes de volver a desplegar;
ese archivo es la fuente de las variables, no los `.env` de los clones del código.

La primera conexión SSH registra la clave del host en `.local/known_hosts`; las
siguientes comprueban esa identidad. Para verificación independiente de las
huellas de la instancia, utiliza la salida de consola de EC2.

## 5. Probar acceso y tenants

Abre la URL de tenant que muestra el despliegue o `terraform output frontend_demo_url`.
Por ejemplo, si el frontend tiene IP `3.143.17.104`:

```text
http://demo.3-143-17-104.sslip.io/
http://wabi.3-143-17-104.sslip.io/
http://multicenter.3-143-17-104.sslip.io/
```

[sslip.io](https://sslip.io/) resuelve esos nombres a la IP incluida en ellos;
no tienes que comprar un dominio ni editar `/etc/hosts`. El frontend toma el slug
de la primera parte del nombre. No crea instituciones: cada tenant y su cuenta
deben existir en Supabase. La API se consume en el mismo dominio, bajo
`/core/api/v1`; no necesitas un dominio ni un puerto público separado para el backend.

También puedes abrir `frontend_url` por IP e indicar el slug de una
institución que ya exista en Supabase. `demo` aparece precompletado en el frontend,
pero solo funciona si ese tenant y sus usuarios ya existen en la base compartida.
Utiliza las credenciales actuales de esas cuentas; el despliegue no las genera,
reemplaza ni agrega estudiantes. Las acciones de la aplicación utilizan esa misma
base compartida, así que coordina las pruebas con el equipo.

Usa `http://` explícitamente; el puerto 80 es opcional. `sslip.io` proporciona DNS,
no instala un certificado TLS ni habilita HTTPS. Si el navegador fuerza HTTPS,
seguirá siendo necesario configurar HTTPS o permitir HTTP para ese sitio de pruebas.
No se puede agregar `demo.` directamente a una IP y esperar resolución DNS.
Si cambia la IP pública de EC2, cambia también la URL y debes volver a desplegar
el frontend para compilar el nuevo dominio base. No hace falta recrear instancias
para adoptar esta configuración en un despliegue existente; ejecuta
`./scripts/deploy.sh --frontend-only` y `./scripts/verify.sh`.

## Estado y cambios posteriores

Esta primera práctica usa estado local `infra/terraform.tfstate`, excluido de Git,
y una clave local. No compartas ni ejecutes el mismo despliegue desde varios clones
independientes: podrían crear recursos duplicados sin conocer el estado anterior.
Para administración compartida, migra el estado a un backend S3 propio con
versionado y bloqueo, y permisos por entorno. No uses el estado de OpenTofu.

Actualizar aplicaciones requiere volver a ejecutar `deploy.sh`; no recrear EC2.
El script conserva versiones anteriores en disco. Los cambios de esquema de la
base compartida se coordinan y ejecutan por separado, fuera de estos scripts.

Un cambio de AMI o de cloud-init puede reemplazar instancias: revisa siempre el
plan. La base de Supabase es externa: no se administra con este Terraform ni se
elimina al reemplazar las instancias.

## Eliminar el laboratorio

Cuando hayas terminado con las instancias:

```bash
terraform -chdir=infra plan -destroy
terraform -chdir=infra destroy
```

La eliminación borra las dos EC2 y sus discos. La base de Supabase se conserva.
No elimina recursos externos del despliegue de OpenTofu. Confirma que AWS ya no
tenga las instancias y volúmenes del laboratorio antes de borrar el estado local.

## Diagnóstico

- Fallo de SSH: revisar IP `/32`, estado de EC2 y ruta de la clave local.
- Preparación incompleta: `sudo cloud-init status --long` y
  `sudo less /var/log/cloud-init-output.log` dentro de la instancia.
- API: `sudo systemctl status attendance-backend` y
  `sudo journalctl -u attendance-backend`.
- Frontend: `sudo nginx -t` y `sudo systemctl status nginx`.
- Revisar los logs localmente; la aplicación puede registrar datos de acceso.

Documentación: [Terraform AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs),
[cloud-init en EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html),
[estado en S3](https://developer.hashicorp.com/terraform/language/backend/s3).
