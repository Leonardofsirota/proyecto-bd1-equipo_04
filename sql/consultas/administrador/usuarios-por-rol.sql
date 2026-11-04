/* Usuarios por rol: lista los usuarios de un rol, o de todos si @rol es NULL,
   con sus datos de contacto y si están activos o dados de baja. Es la base para
   gestionar los usuarios y sus roles (RN01 y RN02). No se muestra el hash de la
   contraseña.

   Los usuarios dados de baja se conservan (RN28) y aparecen después de los
   activos de su rol. Si el rol indicado no existe o no tiene usuarios, la
   consulta no devuelve filas. */

DECLARE @rol VARCHAR(50) = 'Vendedor'; -- NULL para listar todos los roles

SELECT
    U.usuario_id,
    U.nombre,
    U.apellido,
    U.dni,
    U.email,
    U.telefono,
    UR.nombre AS rol,
    CASE WHEN U.fecha_eliminacion IS NULL THEN 'Activo' ELSE 'Dado de baja' END AS estado,
    U.fecha_eliminacion AS fecha_baja
FROM dbo.USUARIO AS U
INNER JOIN dbo.USUARIO_ROL AS UR
    ON U.usuario_rol_id = UR.usuario_rol_id
WHERE @rol IS NULL
    OR UR.nombre = @rol
ORDER BY
    UR.nombre,
    CASE WHEN U.fecha_eliminacion IS NULL THEN 0 ELSE 1 END,
    U.apellido,
    U.nombre;
