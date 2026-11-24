# Hallazgos de auditoría: seguridad y permisos

Fecha: 24 de noviembre de 2026. Revisión de solo lectura en producción, más pruebas funcionales previas en QA.

## Roles
- 1 usuario activo con rol administrador.
- 1 usuario activo con rol vendedor.
- No se copiaron correos, identificadores ni datos personales en este informe.

## RLS y funciones
- Todas las tablas públicas revisadas tienen RLS activo; no se encontraron tablas con RLS desactivado.
- Hay 6 tablas con RLS activo y sin políticas. Ninguna de esas tablas concede SELECT directo a anon o authenticated; permanecen cerradas por defecto.
- Se revisaron 42 funciones SECURITY DEFINER del esquema public.
- Ninguna de las 42 es ejecutable por anon.
- 31 son ejecutables por authenticated según sus permisos explícitos.
- Todas las funciones revisadas fijan search_path vacío.

## Pruebas funcionales anteriores
- El usuario vendedor no pudo aprobar una operación administrativa de inventario en QA; el backend devolvió rechazo de permiso.
- La recepción con diferencia de costo exige rol administrador y motivo escrito; vendedor y administrador sin motivo son rechazados.
- Los controles de interfaz no sustituyen las validaciones de backend/RLS/RPC.

## Conclusión

No se encontró exposición directa a anon en las funciones SECURITY DEFINER revisadas ni tablas públicas sin RLS. Las funciones autenticadas deben seguir auditándose por operación y rol, especialmente cuando se agreguen nuevas RPC. No se modificaron roles, permisos ni políticas de producción.