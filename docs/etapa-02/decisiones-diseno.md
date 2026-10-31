# Decisiones de diseño - Etapa 2

Este documento explica las principales decisiones tomadas al pasar del dominio descrito en la Etapa 1 al modelo de datos, y el motivo de cada una. Las reglas de negocio se citan por su identificador (RN01, RN02, etc.).

## 1. Usuarios y roles

Administradores, vendedores y clientes se registran en una única tabla, USUARIO, porque comparten los mismos datos personales y de acceso (RN03). Lo que los distingue es el rol: cada usuario tiene exactamente uno (RN01), y los roles se guardan en su propia tabla.

El rol determina qué hace cada usuario en el sistema: el cliente realiza pedidos y el vendedor publica ofertas. Por eso USUARIO se relaciona tanto con PEDIDO como con PUBLICACION.

## 2. Direcciones y ubicación

Las direcciones forman una tabla propia porque un usuario puede registrar varias (RN05). Calle, altura y código postal son obligatorios; piso, departamento y referencia son opcionales.

La ubicación se modela en dos niveles: cada dirección pertenece a una ciudad y cada ciudad, a una provincia. Así, el nombre de cada ciudad se registra una sola vez y la provincia se obtiene a través de la ciudad. Dos ciudades pueden llamarse igual si están en provincias distintas.

La versión inicial solo carga la provincia de Corrientes. Agregar otras provincias no requiere cambiar la estructura.

## 3. Libro y publicación

El modelo separa el libro de la oferta:

- **LIBRO** es la ficha bibliográfica de una edición, identificada por su ISBN (RN06). Reúne lo que no depende de quién lo vende: título, páginas, año, editorial, categoría, idioma y encuadernación (RN07).
- **PUBLICACION** es la oferta de un vendedor sobre ese libro, con su propio precio, stock y condición del ejemplar (RN10).

Gracias a esta separación, un mismo libro puede ofrecerse por varios vendedores, a distintos precios y en distintas condiciones, sin repetir sus datos bibliográficos (RN11). Un vendedor no puede tener dos publicaciones vigentes del mismo libro en la misma condición: si tiene más ejemplares, aumenta el stock de la que ya existe.

## 4. Autores

La relación entre libros y autores es de muchos a muchos (RN08) y se resuelve con la tabla intermedia AUTOR_LIBRO. Un autor puede registrarse antes de tener libros asociados.

Solo el nombre y el apellido del autor son obligatorios. El resto de sus datos (nacionalidad, fechas de nacimiento y fallecimiento, y biografía) no siempre se conoce al darlo de alta.

El nombre no es único, porque pueden existir autores homónimos. Para distinguirlos hay dos datos opcionales:

- **ISNI.** Es el identificador internacional de autores. No puede repetirse cuando se registra.
- **Diferencial.** Es una nota breve que distingue al autor de otros con el mismo nombre, como un seudónimo.

## 5. Pedidos y detalle

Cada pedido pertenece a un único cliente y puede incluir publicaciones de varios vendedores (RN15, RN16). La relación entre pedidos y publicaciones es de muchos a muchos y tiene atributos propios, la cantidad y el precio unitario. Por eso se transforma en la tabla PEDIDO_DETALLE, donde cada fila es un renglón del pedido. Una publicación aparece una sola vez por pedido; si se compran varios ejemplares, se indica en la cantidad.

Tres decisiones protegen el historial de las ventas:

- **Precio histórico.** El renglón guarda el precio unitario del momento de la compra, en lugar de tomarlo de la publicación. Si el vendedor cambia el precio, los pedidos anteriores no se alteran (RN26).
- **Dirección copiada.** El pedido guarda una copia de la dirección de entrega, en lugar de referenciar una dirección del cliente. Así la conserva aunque el cliente la edite o la elimine (RN27). Solo la ciudad se referencia, porque pertenece a un catálogo que el cliente no modifica.
- **Total calculado.** El total del pedido no se almacena: se calcula a partir del detalle (RN17). De este modo no puede quedar inconsistente con los renglones.

El descuento sigue el mismo criterio: su porcentaje y su importe se derivan del total, así que tampoco se almacenan. Además, es informativo y no cambia lo que se cobra (RN30 a RN32).

## 6. Pagos

Cada pago es un intento de cobro de un pedido. Un pedido puede tener varios: si un intento es rechazado o cancelado, se registra uno nuevo y el anterior se conserva como historial (RN24, RN29). Cada intento usa un único método de pago y tiene un estado (RN21 a RN23).

El pago guarda su propio importe aunque el total del pedido pueda calcularse. Funciona como constancia del monto procesado en ese intento.

Además, registra dos fechas con significados distintos (RN25):

- **Fecha de creación.** Indica cuándo se inició el intento y siempre está presente.
- **Fecha de pago.** Indica cuándo se acreditó y queda vacía hasta que el pago se aprueba. Si el cobro no concreta la venta, el pago queda cancelado y conserva esta fecha como rastro (RN37). Por eso, la fecha de pago por sí sola no indica que hubo una venta: lo indica el estado aprobado.

## 7. Bajas lógicas

Los usuarios y las publicaciones no se eliminan: se marcan como dados de baja, para que los pedidos que los incluyen sigan completos (RN28).

- **Usuarios.** La baja se registra con una fecha de eliminación; mientras está vacía, el usuario está activo. A diferencia de un simple indicador, la fecha registra además cuándo ocurrió la baja.
- **Publicaciones.** Se distinguen dos situaciones. La pausa es temporal y se indica con la marca de disponibilidad. La baja es definitiva y se registra con una fecha de eliminación. Una publicación dada de baja nunca puede figurar como disponible.

La regla que impide duplicar una oferta (sección 3) solo considera las publicaciones vigentes, es decir, las que no fueron dadas de baja. Así, un vendedor puede volver a publicar un libro cuya oferta anterior dio de baja. Una publicación pausada sigue vigente: para volver a ofrecerla, el vendedor la reactiva.

En línea con este criterio, las claves foráneas no propagan borrados: no se puede eliminar una fila mientras otra tabla la referencie.

## 8. Catálogos

Los roles, las categorías, los idiomas, las editoriales, las encuadernaciones, las condiciones, las nacionalidades, los métodos de pago y los estados son tablas propias, en lugar de texto escrito en cada registro. Así se evitan distintas formas de escribir un mismo valor, se garantiza que solo se usen valores válidos y se pueden agregar valores nuevos sin modificar la estructura. Todos los catálogos tienen el mismo formato: un identificador y un nombre que no puede repetirse.

Los estados del pedido y del pago están en tablas separadas porque describen procesos distintos: el avance de la compra (RN19, RN20) y el resultado de cada intento de pago (RN23). Aunque algunos nombres coinciden, como «Pendiente» o «Cancelado», no significan lo mismo en cada proceso.

## 9. Claves

Todas las tablas tienen una clave primaria sustituta de una sola columna, con el nombre de la tabla seguido de `_id` (por ejemplo, `libro_id`). Con este criterio uniforme, todas las relaciones se establecen del mismo modo: con una única clave foránea.

Los identificadores naturales, como el ISBN del libro o el DNI y el email del usuario, se definen como únicos, pero no se usan como clave primaria.

Las tablas intermedias siguen el mismo criterio: tienen su propia clave sustituta en lugar de una clave compuesta. Para evitar filas repetidas, la combinación de sus dos claves foráneas se define como única.

## 10. Reservas de stock

La reserva de stock (RN33 a RN35) no agrega tablas ni columnas. Su vencimiento y el stock libre se calculan al consultarlos, con datos que el modelo ya guarda: la fecha del pedido y, si tiene un pago pendiente, la fecha de creación y el método de ese pago.

Al ser un cálculo, una reserva deja de contar en cuanto vence, sin que haya que actualizar ninguna fila: un pedido vencido sigue pendiente, pero ya no reserva. El stock de PUBLICACION conserva siempre las unidades reales y solo baja al confirmarse la venta (RN14).
