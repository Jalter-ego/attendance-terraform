# Attendance · infraestructura compartida con Terraform

Este repositorio administra las dos EC2 y la red del equipo en AWS.
La rama `master` contiene la configuración común. El estado se guarda en S3,
según `infra/backend.tf`, y todos usamos el workspace `default`.

Necesitas Terraform >= 1.10 y < 2.0, AWS CLI v2 y Git. Ejecuta los comandos desde
la raíz de este repositorio. No necesitas los proyectos de React o NestJS para
trabajar en la infraestructura.

## 1. Configurar tu acceso a AWS

Cada integrante usa sus propias credenciales. Configura tu perfil una sola vez:

```bash
aws configure --profile attendance-terraform
```

Indica la región `us-east-2`. En cada terminal donde vayas a trabajar:

```bash
export AWS_PROFILE=attendance-terraform
aws sts get-caller-identity
```

La cuenta debe ser `929571213233`; el usuario debe ser el tuyo.
El nombre del perfil es local: si lo llamaste `pepito`, usa
`export AWS_PROFILE=pepito`. No se necesita `terraform login`.
Debes tener permisos para el estado S3 y las operaciones de AWS que ejecutarás.

## 2. Conectarte al estado compartido

Con tu copia actualizada de `master`:

```bash
terraform -chdir=infra init
terraform -chdir=infra workspace select default
terraform -chdir=infra workspace show
```

El último comando debe mostrar `default`. No crees un workspace por persona.
El bucket ya está preparado: no necesitas ejecutar `setup-state.sh`, migrar un
estado local ni subir archivos a S3 manualmente. Terraform lo hace automáticamente.

## 3. Preparar un cambio de infraestructura

Antes de comenzar, guarda tus cambios pendientes y actualiza el código:

```bash
git switch master
git pull --ff-only origin master
git switch -c cambio-infra
```

Reemplaza `cambio-infra` por un nombre para tu cambio. Edita los archivos necesarios:

- `infra/team.auto.tfvars.json`: valores comunes del entorno.
- `infra/compute.tf`: instancias y discos.
- `infra/network.tf`: red y rutas.
- `infra/security.tf`: reglas de acceso.

Todos deben usar los mismos valores comunes. No reemplaces la clave pública
`infra/keys/operator.pub` ni cambies el nombre del entorno por el tuyo. Para sumar
una IP de acceso SSH, se acuerda el cambio en `additional_ssh_allowed_cidrs`;
no se reemplaza la IP de otro integrante.

Comprueba el formato, valida y revisa la propuesta:

```bash
terraform -chdir=infra fmt -recursive
terraform -chdir=infra validate
terraform -chdir=infra plan -lock-timeout=60s
git diff
```

`plan` muestra qué se crearía, modificaría o eliminaría; no aplica esos cambios.
Revisa especialmente las eliminaciones y los reemplazos de instancias.

## 4. Subir el cambio a GitHub

```bash
git add infra/ README.md
git commit -m "Actualiza la infraestructura compartida"
git push -u origin cambio-infra
```

Usa el nombre real de tu rama. Abre un Pull Request hacia `master` y espera su
revisión e integración. Subir código a GitHub todavía no cambia los recursos de AWS.

## 5. Aplicar el cambio integrado en master

Coordinen quién lo aplicará. Ese integrante actualiza su copia y ejecuta:

```bash
git switch master
git pull --ff-only origin master
terraform -chdir=infra init
terraform -chdir=infra apply -lock-timeout=60s
```

`apply` genera un plan nuevo y pide confirmación. Revisa que corresponda al cambio
acordado y escribe `yes` para ejecutarlo; responde `no` para cancelar.
La primera creación genera las dos EC2 y su red. Las siguientes operaciones
modifican el mismo entorno, según el código y el estado compartido.

Para consultar los resultados:

```bash
terraform -chdir=infra output
```

Los demás pueden actualizar `master` y ejecutar `plan`: si AWS coincide con la
configuración, debería indicar que no hay cambios pendientes.

## Recordatorios

- El estado en S3 se actualiza automáticamente y tiene bloqueo para evitar
  operaciones simultáneas. Si está ocupado, espera; no fuerces su desbloqueo.
- No subas credenciales, claves privadas, `.tfstate`, planes ni `.terraform/` a Git.
  `team.auto.tfvars.json` y `operator.pub` sí son parte de la configuración común.
- No uses valores personales en otros `.tfvars` o en `TF_VAR_*` que cambien el entorno.
- Todos trabajan sobre los mismos recursos: aplicar o destruir afecta al equipo.
