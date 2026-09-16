# Decisiones de diseño - Etapa II

Este documento explica las decisiones tomadas al construir el diagrama entidad-relación y el modelo relacional, y el motivo de cada una.

## 1. Cambios respecto del modelo preliminar

El modelo preliminar de la Etapa I describía una librería que vende su propio catálogo. Durante el modelado, el sistema pasó a funcionar como un marketplace, donde distintos vendedores publican ofertas de libros y los clientes compran esas ofertas.

Este cambio de enfoque llevó el precio y el stock del libro a una nueva entidad, PUBLICACION. Además, el género se reemplazó por CATEGORIA y se incorporaron IDIOMA, ENCUADERNACION y CONDICION para describir con más detalle cada libro y cada oferta. Por último, la compra pasó a modelarse como pedido y guarda sus propios datos de envío.

## 2. Usuarios y roles

Todos los actores del sistema (administradores, vendedores y clientes) se representan con una única entidad USUARIO, ya que comparten los mismos datos personales y de acceso. Lo que los diferencia es el rol, que se registra en la entidad USUARIO_ROL.

Cada usuario tiene exactamente un rol, y un mismo rol puede estar asignado a muchos usuarios. Los roles son excluyentes: solo el Cliente realiza pedidos y solo el Vendedor publica ofertas. Por eso USUARIO se relaciona tanto con PEDIDO como con PUBLICACION, y el rol determina cuál de las dos relaciones le corresponde a cada usuario.

El atributo es_activo permite dar de baja a un usuario sin eliminarlo. Así, los pedidos y las publicaciones que registró siguen haciendo referencia a él.

## 3. Direcciones y ubicación geográfica

Las direcciones forman una entidad propia porque un usuario puede registrar varias. Un usuario puede tener cero o más direcciones, ya que no todos los roles las necesitan, y cada dirección pertenece a un único usuario.

La ciudad y la provincia no se escriben como texto dentro de la dirección, sino que son entidades separadas: cada dirección pertenece a una CIUDAD y cada ciudad a una PROVINCIA. De esta forma, el nombre de una ciudad se registra una sola vez y no se repite en cada dirección. La dirección no se relaciona directamente con la provincia, porque la provincia se obtiene a través de la ciudad.

El nombre de una ciudad no es único por sí solo, ya que hay ciudades con el mismo nombre en distintas provincias. Lo que no puede repetirse es la combinación de nombre y provincia. El nombre de la provincia, en cambio, sí es único.

Calle, altura y código postal son obligatorios. Piso, departamento y referencia son opcionales, porque no todas las direcciones los tienen.

## 4. Libros y autores

LIBRO representa la ficha bibliográfica de una edición, identificada por su ISBN. Reúne los datos que no dependen de quién vende el libro: título, año de publicación, número de páginas, editorial, idioma, encuadernación y categoría. Como el ISBN distingue cada edición, la editorial y la encuadernación son propiedades del libro y no de la oferta.

Cada libro pertenece a una sola categoría, está escrito en un solo idioma, lo publica una sola editorial y tiene un único tipo de encuadernación. Estas cuatro relaciones son de uno a muchos: cada valor puede aplicarse a muchos libros o, por el momento, a ninguno.

La relación entre libros y autores es de muchos a muchos, porque un libro puede tener varios autores y un autor puede escribir varios libros. Se resuelve con la tabla intermedia LIBRO_AUTOR. Todo libro debe tener al menos un autor, mientras que un autor puede registrarse antes de tener libros asociados. El nombre del autor no es único, para admitir autores homónimos.

## 5. Publicaciones

PUBLICACION representa la oferta de un libro hecha por un vendedor. Se separa de LIBRO porque el precio, el stock y la condición del ejemplar dependen de cada vendedor. Así, un mismo libro puede ofrecerse por varios vendedores, en distintas condiciones y a distintos precios, sin repetir sus datos bibliográficos.

Cada publicación corresponde a un único libro, a un único vendedor y a una única condición, registrada en CONDICION. Un libro puede no tener publicaciones o tener muchas, y un vendedor puede publicar tantas ofertas como quiera.

Un vendedor puede tener una sola publicación por libro y condición. Si tiene más ejemplares en la misma condición, aumenta el stock de esa publicación en lugar de crear otra. Esto evita ofertas duplicadas del mismo producto.

El atributo es_activo permite pausar o dar de baja una publicación sin eliminarla, de modo que los pedidos que la incluyen conservan su referencia.

## 6. Pedidos

Cada pedido lo realiza un único cliente, y un cliente puede tener muchos pedidos. Un mismo pedido puede incluir publicaciones de distintos vendedores y se envía a una sola dirección.

La relación entre pedidos y publicaciones es de muchos a muchos: un pedido contiene una o más publicaciones, y una publicación puede formar parte de muchos pedidos. Como la relación tiene atributos propios (cantidad y precio unitario), se transforma en la tabla PEDIDO_DETALLE, donde cada fila es un renglón del pedido. Una publicación aparece una sola vez por pedido; si se compran varios ejemplares, se indica en la cantidad.

El precio unitario se copia en el detalle al momento de la compra, en lugar de tomarse de la publicación. Si el vendedor modifica el precio más adelante, los pedidos ya registrados mantienen el valor con el que se vendieron.

El importe total del pedido es un atributo derivado, que se calcula como la suma de cantidad por precio unitario de todos sus renglones. Por eso aparece en el DER pero no se almacena en el modelo relacional, lo que evita que el total quede inconsistente con el detalle.

La dirección de envío también se copia en el pedido (calle, altura, piso, departamento, código postal y referencia) en lugar de hacer referencia a DIRECCION. Así, el pedido conserva la dirección tal como estaba al momento de la compra, aunque después el usuario la modifique o la elimine. La ciudad, en cambio, se referencia con una clave foránea, porque forma parte de un catálogo que no depende de los cambios que haga el usuario.

## 7. Pagos

Un pedido puede tener cero o más pagos, y cada pago pertenece a un único pedido. Cada pago representa un intento: si uno es rechazado o cancelado, se registra uno nuevo y el anterior se conserva como historial. Un pedido recién creado todavía no tiene pagos, y se completa con un único pago aprobado por el total.

Cada pago utiliza un único método, registrado en PAGO_METODO (tarjeta de débito, tarjeta de crédito o transferencia), y tiene un estado registrado en PAGO_ESTADO.

El importe se guarda en cada pago aunque el total del pedido pueda calcularse a partir del detalle. Funciona como constancia del monto que se procesó en ese intento, independiente del cálculo del pedido.

El pago registra dos fechas con significado distinto. La fecha de creación indica cuándo se inició el intento y siempre está presente. La fecha de pago indica cuándo se acreditó, por lo que queda vacía mientras el pago no se aprueba.

## 8. Catálogos y estados

Los roles, las categorías, los idiomas, las editoriales, las encuadernaciones, las condiciones, los métodos de pago y los estados son entidades propias, en lugar de valores escritos en cada registro. Así se evitan distintas formas de escribir un mismo valor, se garantiza que solo se usen valores válidos y se pueden agregar valores nuevos sin modificar la estructura del modelo. Por la misma razón, el nombre de cada valor es único dentro de su catálogo.

Los estados del pedido y del pago están en entidades separadas, PEDIDO_ESTADO y PAGO_ESTADO, porque describen procesos distintos: el avance de la compra y el resultado de cada intento de pago. PEDIDO_ESTADO incluye además una descripción que explica el significado de cada estado. Tanto el pedido como el pago guardan únicamente una referencia a su estado actual.

## 9. Claves e identificadores

Todas las tablas tienen una clave primaria sustituta de una sola columna, cuyo nombre es el de la tabla seguido de _id (por ejemplo, libro_id). Se eligió este criterio por uniformidad: todas las relaciones se establecen de la misma manera, mediante una única clave foránea.

Los identificadores naturales, como el ISBN del libro o el DNI y el email del usuario, se definen como únicos, pero la clave primaria sigue siendo la sustituta.

Las tablas intermedias LIBRO_AUTOR y PEDIDO_DETALLE siguen el mismo criterio: tienen su propia clave sustituta en lugar de una clave compuesta por sus dos claves foráneas. Para evitar filas duplicadas, la combinación de ambas claves foráneas se define como única.
