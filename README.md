# Attendance · laboratorio AWS con Terraform

Administra un único entorno compartido del equipo: dos instancias EC2, frontend
React con Nginx y backend NestJS conectado al Supabase existente. La rama `master`
contiene la configuración común; el estado oficial se guarda en un bucket S3 privado.
Cada desarrollador utiliza sus propias credenciales de AWS y su clave SSH personal.

## Arquitectura y alcance

```text
Navegador -> frontend:80 (Nginx, React dist)
                         |
                         +-> /core/api/v1 -> IP privada backend:5000
                                              |
                                              +-> Supabase Session pooler:5432 (SSL)
```

- Ubuntu 24.04 oficial de Canonical, Node.js 24.15.0 y pnpm 10.11.0.
- Dos `t3.small` por defecto, cada una con 20 GiB gp3 cifrados y 2 GiB de swap.
- HTTP público; SSH desde la IPv4 `/32` del operador y las direcciones adicionales aprobadas.
- Ubuntu tiene una AMI fija para que ambos desarrolladores obtengan planes consistentes.
- S3 guarda el estado cifrado, con versionado y bloqueo nativo mediante `.tflock`.
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

## 1. Conectarse al entorno compartido

La cuenta, región, nombre del despliegue, AMI, tamaño y reglas comunes están en
`infra/team.auto.tfvars.json`.
`infra/keys/operator.pub` es la clave PÚBLICA estable del acceso inicial a las EC2.
No la reemplaces por tu propia clave al clonar, porque cambiaría la infraestructura.

Cada participante configura un perfil en su computadora con sus propias credenciales:

```bash
aws configure --profile attendance-terraform
export AWS_PROFILE=attendance-terraform
aws sts get-caller-identity
./scripts/prepare.sh
terraform -chdir=infra init
terraform -chdir=infra workspace show
terraform -chdir=infra state list
terraform -chdir=infra plan
```

Usa la cuenta `929571213233` y el workspace `default`. El perfil puede tener otro
nombre si exportas `AWS_PROFILE` con ese nombre. `prepare.sh` verifica la cuenta y
prepara una clave SSH personal; no cambia las variables comunes ni crea recursos.
La clave nueva no queda autorizada automáticamente en EC2.

No ejecutes la preparación antigua que generaba un despliegue por persona. Si
conservas `infra/lab.auto.tfvars.json`, muévelo a un respaldo privado en `.local/`
antes de unirte al entorno. Evita archivos `.tfvars` personales y variables `TF_VAR_*`
que cambien recursos compartidos; los cambios comunes se revisan mediante PR.

### Preparación inicial del bucket: solo el operador y una sola vez

```bash
export AWS_PROFILE=attendance-terraform
./scripts/setup-state.sh
```

El bucket definido en `infra/backend.tf` debe existir antes de `terraform init`.
El script verifica la cuenta y crea o configura el bucket privado, con bloqueo de
acceso público, versionado, cifrado AES256 y una política que exige HTTPS. No crea
EC2 ni concede permisos a usuarios. Está separado del Terraform de las aplicaciones:
`terraform destroy` conserva el bucket y su historial de estado. Volver a ejecutar
este script restablece la configuración de este bucket dedicado; úsalo solo allí.

Si estás migrando un estado local existente, haz una copia privada y ejecuta desde
la computadora que tiene el estado oficial:

```bash
install -d -m 700 .local
cp infra/terraform.tfstate .local/state-before-s3.tfstate
chmod 600 .local/state-before-s3.tfstate
terraform -chdir=infra init -migrate-state
```

Revisa la pregunta de migración antes de confirmarla. Migra una sola vez y no
sobrescribas un estado remoto que ya utiliza el equipo. Los demás participantes
solo ejecutan `terraform init`; no deben migrar estados personales al mismo destino.
No subas el archivo manualmente con `aws s3 cp`. Terraform administra la persistencia
y el bloqueo. En un entorno todavía sin EC2, una actualización de estado con
`terraform -chdir=infra apply -refresh-only` puede guardar sus salidas iniciales
sin crear infraestructura. La creación real se hace después con un plan normal.

### Variables del backend de Attendance: solo para quien haga deploy

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
No guardes credenciales en `team.auto.tfvars.json`, en `backend.tf` ni en el frontend.

## 2. Validar y revisar el plan

```bash
terraform -chdir=infra init
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra plan -lock-timeout=60s -out=../.local/lab.tfplan
terraform -chdir=infra show ../.local/lab.tfplan
```

El plan consulta AWS y el estado compartido. Comprueba cuenta, región, dos
instancias, discos y reglas de acceso. Un plan sobre un entorno ya creado debe
reconocer esos recursos; no debería proponer duplicarlos. No reutilices el mismo
objeto de estado para el despliegue independiente de OpenTofu.

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

Abre la URL de tenant que muestra el despliegue o `terraform -chdir=infra output frontend_demo_url`.
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

El estado oficial está en
`s3://attendance-tfstate-929571213233-us-east-2/attendance/equipo/terraform.tfstate`.
El bloqueo usa el objeto auxiliar `terraform.tfstate.tflock`; las versiones de S3
son historial del mismo estado. Todos usan el mismo bucket, key y workspace.
No mezcles este estado con el del laboratorio de OpenTofu.

Un compañero actualiza `master`, ejecuta `terraform plan` y revisa el resultado
antes de aplicar. El bloqueo impide escrituras simultáneas de Terraform, pero no
resuelve diferencias de código o variables: primero integren el cambio mediante PR.
Coordinen las publicaciones de `deploy.sh`, que operan por SSH y no adquieren el
bloqueo de Terraform. Los planes y las copias privadas del estado siguen fuera de Git.
Conserva las claves privadas y el entorno del backend aunque el estado esté en S3.

Si cambian las IP públicas después de detener/encender EC2, sincroniza el estado
con `terraform -chdir=infra apply -refresh-only` y vuelve a desplegar el frontend
para compilar el nuevo dominio. Revisa primero el plan que muestra el comando.

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
No elimina recursos externos del despliegue de OpenTofu. El estado remoto seguirá
registrando la eliminación. No borres el bucket ni el objeto de estado al finalizar
la práctica; el equipo puede reutilizarlos para volver a crear el entorno.

## Diagnóstico

- S3 AccessDenied: verificar cuenta, perfil, permisos del estado y del archivo `.tflock`.
- Estado bloqueado: esperar al otro operador; no forzar el desbloqueo de una operación activa.
- Fallo de SSH: revisar las IP `/32`, la autorización de la clave personal y el estado de EC2.
- Preparación incompleta: `sudo cloud-init status --long` y
  `sudo less /var/log/cloud-init-output.log` dentro de la instancia.
- API: `sudo systemctl status attendance-backend` y
  `sudo journalctl -u attendance-backend`.
- Frontend: `sudo nginx -t` y `sudo systemctl status nginx`.
- Revisar los logs localmente; la aplicación puede registrar datos de acceso.

Documentación: [Terraform AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs),
[cloud-init en EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html),
[estado en S3](https://developer.hashicorp.com/terraform/language/backend/s3).
