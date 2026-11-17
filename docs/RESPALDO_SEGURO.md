# Respaldo seguro de Drosalud

Este proceso genera una copia descargable de la base de datos sin depender del computador del usuario. Se ejecuta en GitHub Actions y puede iniciarse desde el navegador de Windows, Ubuntu o un celular.

## Qué hace

1. Exporta roles, estructura y datos usando Supabase CLI.
2. Comprueba que los archivos no estén vacíos y que el archivo comprimido sea válido.
3. Cifra el paquete con **age** antes de subirlo a GitHub Actions.
4. Publica únicamente el archivo cifrado y su huella SHA-256 como artefacto durante 3 días.
5. Se puede iniciar manualmente o se ejecuta cada domingo a las 06:00, hora de Colombia.

**Importante:** el repositorio Drosalud es público. El artefacto también puede ser descargable por otras personas con acceso al repositorio, por eso solo se publica cifrado. La clave privada age nunca se guarda en GitHub ni en el repositorio.

## Configuración inicial (una sola vez)

### 1. Crear la clave privada y la clave pública age

En Ubuntu, instala age y genera una clave:

```bash
sudo apt-get update
sudo apt-get install age
age-keygen -o drosalud-backup-key.txt
```

El archivo `drosalud-backup-key.txt` contiene la **clave privada**. Guárdalo fuera del repositorio, en un lugar seguro y con una copia de recuperación. No lo subas a GitHub ni lo envíes por chat.

Obtén la clave pública:

```bash
age-keygen -y drosalud-backup-key.txt
```

Copia la línea que comienza por `age1`. Esa es la clave pública; se puede compartir con GitHub.

### 2. Guardar la clave pública en GitHub

En el repositorio `cristhiam-code/drosalud`:

1. Abre **Settings**.
2. Entra a **Secrets and variables → Actions**.
3. En **Variables**, pulsa **New repository variable**.
4. Nombre: `BACKUP_AGE_RECIPIENT`.
5. Valor: pega la clave pública `age1...`.

### 3. Guardar la conexión de producción como secreto

En la misma página:

1. En **Secrets**, pulsa **New repository secret**.
2. Nombre: `SUPABASE_DB_URL`.
3. Valor: pega la cadena de conexión de la base de datos de producción, obtenida desde **Supabase → proyecto de producción → Connect → Session pooler**.

La cadena contiene la contraseña de la base de datos. Pégala únicamente en el formulario de secreto de GitHub. No la pongas en archivos, código, variables públicas ni mensajes. Si la contraseña contiene caracteres especiales, usa la cadena de conexión copiada por Supabase con su codificación correcta.

## Ejecutar y descargar

1. Abre la pestaña **Actions** del repositorio.
2. Selecciona **Respaldo seguro de Drosalud**.
3. Pulsa **Run workflow** y confirma.
4. Espera a que la ejecución termine en verde.
5. Abre esa ejecución y descarga el artefacto `drosalud-respaldo-cifrado`.

El artefacto se elimina automáticamente después de 3 días. Descárgalo y guárdalo en un lugar seguro. La copia semanal automática no sustituye la descarga y conservación de una copia fuera de GitHub.

## Comprobar y descifrar en Ubuntu

Primero verifica la huella del archivo descargado:

```bash
sha256sum --check drosalud-respaldo.tar.gz.age.sha256
```

Luego descífralo usando la clave privada que conservaste:

```bash
age --decrypt --identity drosalud-backup-key.txt --output drosalud-respaldo.tar.gz drosalud-respaldo.tar.gz.age
tar -tzf drosalud-respaldo.tar.gz
```

El último comando solo muestra el contenido; no restaura ni modifica ninguna base de datos.

## Alcance y límites

- El volcado de Supabase CLI excluye los esquemas administrados `auth` y `storage`, así como esquemas creados por extensiones. No debe considerarse una copia integral de todos los componentes del proyecto.
- No incluye archivos subidos a Storage, configuración de proveedores de inicio de sesión, secretos/API keys, dominios, funciones Edge ni configuración del panel de Supabase.
- Las contraseñas de roles personalizados no se exportan como contraseñas recuperables.
- La copia de datos y estructura **todavía debe probarse en una instancia aislada** antes de considerarla un plan de recuperación validado.
- No restaurar nunca sobre producción para hacer pruebas.
- GitHub Actions y el almacenamiento de artefactos tienen cuotas y condiciones que pueden cambiar. Configura un límite de gasto de GitHub de 0 si no autorizas cargos; si la cuota gratuita se agota, el respaldo puede fallar en lugar de completarse.
- El Excel de Drosalud sigue siendo un informe útil, pero no sustituye este respaldo SQL.

## Seguridad

- No añadir la clave privada age ni la cadena de conexión a Git.
- No publicar archivos SQL sin cifrar.
- No compartir el artefacto cifrado junto con la clave privada.
- Si se pierde la clave privada, los respaldos cifrados existentes no se podrán descifrar.
- Esta automatización solo consulta y exporta la base de datos; no ejecuta migraciones ni modifica registros de producción.
