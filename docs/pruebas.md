# Comprobaciones del laboratorio

1. `terraform fmt -check -recursive`, `validate` y las tres pruebas con proveedor
   simulado deben pasar antes de consultar o crear recursos en AWS. También deben
   pasar las pruebas de variables con `node --test --test-isolation=none tests/environment.test.cjs`.
2. El plan debe crear exactamente dos EC2, una VPC propia y reglas de acceso:
   frontend HTTP público, SSH con `/32`, API desde el frontend y sin regla 5432.
3. `scripts/verify.sh` comprueba página inicial, ruta SPA `/login`, proxy de la API
   y resolución del hostname del tenant mediante `sslip.io`.
4. Preparar `.local/backend.env` con la conexión existente de Supabase y SSL.
   No debe contener valores de ejemplo ni contraseñas en blanco.
5. Ingresar con un tenant y estudiante existentes en Supabase, recargar y comprobar
   la sesión. Cerrar sesión e ingresar con una cuenta administrativa existente.
6. Abrir `http://demo.<IP-con-guiones>.sslip.io/` y comprobar que el login muestra
   `Institución: demo` sin pedir que se escriba la institución. Repetir con otro
   tenant existente. El dominio base compilado debe coincidir con la IP del frontend.
7. Después de una actualización, confirmar los commits en `.local/releases.json`.
8. Al finalizar, revisar el plan de eliminación y destruir solo este laboratorio.
   Supabase debe mantenerse externo a Terraform; no se ejecutan seeds ni migraciones.

No copiar credenciales, tokens, claves privadas ni archivos de estado a capturas,
issues o al repositorio.
