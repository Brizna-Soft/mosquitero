# Mosquitero

**Deja afuera los anuncios y los rastreadores.**

Mosquitero es una extensión para **Chrome, Edge, Brave y Firefox**. Es gratis, no tiene publicidad, no
recoge datos y su código está abierto aquí mismo. La hace [Brizna Soft](https://brizna-soft.github.io),
un estudio pequeño de Honduras.

## Qué hace

- **Bloquea anuncios y rastreadores** antes de que se descarguen. Usa las listas EasyList, EasyList
  Spanish (para sitios en español) y EasyPrivacy, que mantiene la comunidad de EasyList.
- **Oculta los huecos** que dejan los anuncios en las páginas.
- **Cuenta lo que bloquea:** el número sobre el ícono dice cuántas cosas bloqueó en la página (en
  Chrome, Edge y Brave).
- **Se apaga en un sitio con un clic.** Si una página no funciona bien, desactiva «Activo en este sitio»
  y la página se recarga sin bloqueos.
- **Rastreadores aparte.** La casilla «Bloquear rastreadores» se puede quitar si algún sitio los
  necesita; los anuncios se siguen bloqueando.
- **Todo pasa dentro de tu navegador.** Las listas vienen dentro de la extensión: Mosquitero no se
  conecta a internet.

## Cómo instalarla (mientras no esté en las tiendas)

Mosquitero todavía no está en la Chrome Web Store, en la tienda de Edge ni en la de Firefox. Mientras
tanto se instala a mano. Baja el archivo de la página de
[versiones (Releases)](https://github.com/Brizna-Soft/mosquitero/releases).

### Chrome, Edge y Brave

1. Baja **`Mosquitero-0.1.0-chrome.zip`**.
2. Descomprímelo en una carpeta que no vayas a borrar, por ejemplo `Documentos\Mosquitero`.
   El navegador usa esa carpeta, así que tiene que quedarse ahí.
3. Abre la página de extensiones de tu navegador (cópiala en la barra de direcciones):
   - Chrome: `chrome://extensions`
   - Edge: `edge://extensions`
   - Brave: `brave://extensions`
4. Activa el **Modo de desarrollador**. En Chrome y Brave está arriba a la derecha; en Edge, a la
   izquierda.
5. Pulsa **Cargar descomprimida** (en Edge se llama **Cargar desempaquetada**) y elige la carpeta del
   paso 2, la que tiene el archivo `manifest.json`.
6. Listo. Para ver el ícono siempre, pulsa la pieza de rompecabezas de la barra y fija Mosquitero.

El navegador puede mostrar un aviso sobre las extensiones del modo de desarrollador. Es normal mientras
Mosquitero no esté en la tienda.

**Para actualizar:** borra lo que hay en la carpeta, descomprime ahí la versión nueva y pulsa
**Recargar** (la flecha circular) en la tarjeta de Mosquitero, en la página de extensiones.

### Firefox

Firefox solo instala para siempre las extensiones que **Mozilla firmó**. Mosquitero todavía no tiene esa
firma. Mientras tanto se puede probar así, pero se quita al cerrar Firefox:

1. Baja **`Mosquitero-0.1.0-firefox.zip`** y descomprímelo.
2. Abre `about:debugging` y elige **Este Firefox**.
3. Pulsa **Cargar complemento temporal…** y elige el archivo `manifest.json` de esa carpeta.

Cuando Mozilla la firme, se instalará normalmente desde un archivo `.xpi` o desde la tienda de Firefox.

En Firefox no aparece el número sobre el ícono: Firefox todavía no deja que las extensiones lo muestren.
Todo lo demás funciona igual.

## Cómo se usa

Pulsa el ícono de Mosquitero (un escudo con malla) para abrir la ventanita:

- Arriba ves el **sitio** en el que estás.
- **Activo en este sitio:** apágalo si una página no funciona bien. Mosquitero deja de bloquear y de
  ocultar ahí, y la página se recarga. Vuelve a encenderlo cuando quieras.
- **Bloquear rastreadores:** quítala solo si un sitio la necesita. Vale para todos los sitios.
- **Reportar un anuncio que se escapó**, **Brizna Soft** y **Donar** abren una página nueva solo si
  los pulsas.

## Permisos y privacidad

Mosquitero pide lo mínimo:

| Permiso | Para qué lo usa |
|---|---|
| `declarativeNetRequest` («Bloquear contenido en cualquier página») | Bloquear anuncios y rastreadores con las reglas que vienen dentro. El bloqueo lo hace el propio navegador: Mosquitero no ve las direcciones que visitas. |
| `storage` | Guardar tus dos ajustes, solo en tu navegador: los sitios donde lo apagaste y si se bloquean los rastreadores. |
| Acceso a todos los sitios (`<all_urls>`) | Poner en cada página la hoja que oculta los huecos de los anuncios, y saber en qué sitio estás para la ventanita y para «Activo en este sitio». |

No pide `declarativeNetRequestFeedback` (el navegador cuenta solo lo que bloquea), ni `tabs` (el acceso
a los sitios ya alcanza para saber en qué sitio estás), ni `scripting`.

**Privacidad:**

- Mosquitero **no recoge, no guarda y no manda datos** a nadie: ni a Brizna Soft ni a otros. No hay
  telemetría ni publicidad.
- **No se conecta a internet.** Las listas vienen dentro de la extensión y se ponen al día con cada
  versión nueva de Mosquitero.
- Lo único que guarda son tus dos ajustes, dentro de tu navegador. Si quitas la extensión, se borran.
- No lee lo que escribes ni el contenido de las páginas: solo oculta los huecos de los anuncios.

## Reportar un anuncio que se escapó

Pulsa **Reportar un anuncio que se escapó** en la ventanita, o entra a
[Reportar un problema](https://github.com/Brizna-Soft/mosquitero/issues/new/choose) y elige
**Se escapó un anuncio**. Pon la dirección del sitio y, si puedes, una captura del anuncio. Antes de
subir la captura, revisa que no muestre tu nombre, tu correo ni otros datos tuyos.

Si una página se rompe con Mosquitero, elige **Algo se rompe en un sitio**. Para ideas, **Idea**.

Hace falta una cuenta de GitHub (es gratis). Como las reglas vienen de EasyList, a veces el arreglo de
fondo hay que pedirlo también allá; eso lo hacemos nosotros.

## Límites conocidos (versión 0.1.0)

- **Ventanas emergentes:** no se cierran las ventanas de anuncios que se abren solas (`$popup`); las
  reglas del navegador no pueden hacerlo. Las páginas de anuncios más conocidas sí se bloquean enteras.
- **Páginas bloqueadas enteras:** si abres directamente una página de una red de anuncios conocida, el
  navegador muestra un aviso de que una extensión la bloqueó. Si de verdad la necesitas, apaga
  Mosquitero en ese sitio.
- **Filtros que se omiten:** las reglas del navegador no admiten todo lo que traen las listas. Se
  omiten las expresiones regulares, `$popup`, `$csp`, `$redirect`, `$rewrite`, `$removeparam`,
  `$badfilter`, las opciones desconocidas, lo que no es ASCII y los filtros cosméticos extendidos
  (`#?#`, `:has-text`, `:-abp-...`, `#$#` y los que cambian estilos). En esta versión son unas 3 100
  reglas de red de unas 107 500, y unas 400 de ocultar de unas 26 700.
- **Algunos anuncios difíciles** (por ejemplo, los de YouTube) necesitan trucos con scripts que esta
  versión no hace.
- **Lo propio de cada sitio** se oculta un instante después de que abre la página; lo general, al
  instante.
- **Las listas no se ponen al día solas:** se actualizan con cada versión nueva de Mosquitero.
- **Firefox:** sin número sobre el ícono y, por ahora, sin la firma de Mozilla.

## Cómo está hecha

Para quien quiera revisarla o armarla. Los scripts están hechos para Windows PowerShell 5.1 y para
PowerShell 7 (pwsh). Ninguno se conecta a internet, salvo `actualizar-listas.ps1` (baja las listas) y la
prueba en Edge (carga recursos reales de anuncios para ver si se bloquean).

| Archivo | Qué hace |
|---|---|
| `herramientas\actualizar-listas.ps1` | Baja las tres listas a `listas\`, con la fecha en el nombre, y anota su origen, versión y huella en `listas\descargas.txt`. |
| `herramientas\convertir-listas.ps1` | Convierte las listas en reglas del navegador y en las hojas para ocultar huecos (`extension\generado\`). |
| `armar.ps1` | Convierte, junta todo en `publicar\chrome` y `publicar\firefox`, lo revisa y arma los `.zip` con su `.sha256`. |
| `herramientas\revisar-generado.ps1` | Revisa que las reglas y los manifiestos estén bien formados y que no pasen del límite. |
| `pruebas\probar-en-edge.ps1` | Prueba la extensión en Edge sin ventana, con perfiles temporales en `pruebas-locales\`. |
| `herramientas\crear-iconos.ps1` | Dibuja los íconos. |
| `herramientas\hacer-captura.ps1` | Hace `publicar\captura.png`. |

**Cómo se convierten las listas:**

- Bloqueo de red: cada filtro pasa a una regla de `declarativeNetRequest`. Los patrones (`||`, `|`,
  `*`, `^`) van a `urlFilter`; `$third-party` y `~third-party`, a `domainType`; los tipos (`script`,
  `image`, `subdocument`…), a `resourceTypes`; `$domain=`, a `initiatorDomains` y
  `excludedInitiatorDomains`; `$match-case`, a `isUrlFilterCaseSensitive`. Las excepciones `@@` son
  reglas `allow` con más prioridad (2 contra 1), y `@@...$document` es `allowAllRequests`.
- Los filtros de solo dominio (`||dominio^`) con las mismas opciones se juntan en **una sola regla** con
  `requestDomains`. Así caben los más de 90 000 dominios de las listas sin pasar del límite de Chrome.
- Límite: Chrome garantiza 30 000 reglas estáticas por extensión. Esta versión usa **13 421**
  (anuncios: 4 312; rastreadores: 9 109), así que no hubo que recortar nada. Si alguna vez no caben, el
  convertidor quita primero las reglas que valen solo para unos pocos sitios y lo anota en el resumen.
- Ocultar huecos: los `##selector` generales van a `cosmetico\genericos.css`, que el navegador pone al
  empezar cada página, en grupos de 10 (si un selector no sirve, el navegador descarta solo su grupo).
  Los `dominio##selector`, las excepciones `#@#` y los sitios con `$generichide` van a
  `cosmetico\por-sitio.json`, que se aplica según el sitio.
- El resumen completo de cada conversión queda en `extension\generado\resumen.txt`.

**Publicar una versión:** cambia la versión en `version.txt` y en los dos manifiestos, sube los cambios y
crea una etiqueta `v0.1.0`. GitHub arma los zip y crea la versión (Release) solo.

## Licencias

- **El código de Mosquitero:** licencia MIT, © 2026 Brizna Soft. Ver [`LICENSE`](LICENSE).
- **Las listas:** EasyList, EasyList Spanish y EasyPrivacy son de
  [The EasyList authors](https://easylist.to/) y tienen doble licencia, GPLv3 o
  [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Mosquitero las usa bajo CC BY-SA 3.0,
  y las reglas convertidas que van dentro de la extensión siguen bajo esa misma licencia. Los detalles
  están en [`AVISOS-DE-TERCEROS.txt`](AVISOS-DE-TERCEROS.txt). Los autores de EasyList no tienen relación
  con Mosquitero.

Si Mosquitero te sirve, puedes apoyar a Brizna Soft con una
[donación por PayPal](https://paypal.me/BriznaSoft).

Hecho con ayuda de IA.
