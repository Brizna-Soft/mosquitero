# Instrucciones para agentes de IA (Codex, Claude y otros)

Este repositorio es de **Brizna Soft**, un estudio pequeño de Honduras que hace programas gratis, sin
publicidad y sin recoger datos. Estas reglas valen para cualquier agente que lea, revise o cambie el código.

## Reglas que no se rompen

- **Idioma:** todo lo que ve la persona va en español sencillo: ventanas, avisos, README y notas. Se trata
  de «tú». Sin jerga técnica en los avisos; si hace falta un código, va al final («Para el técnico: …»).
- **Privacidad:** el programa no se conecta a internet salvo para hacer su trabajo o cuando la persona lo
  pide (por ejemplo «Buscar actualización»). Sin telemetría, sin publicidad y sin datos personales en los
  registros ni en los reportes (nada de usuario, nombre de la PC, rutas completas ni direcciones completas).
- **Seguridad:**
  - Nada se borra sin una confirmación clara, y lo que se borra va a la Papelera siempre que se pueda.
  - Nada pide ser administrador ni cambia la configuración de Windows, salvo las excepciones de la guía,
    que son opcionales y solo pasan si la persona pulsa un botón.
  - Nada se baja ni se instala solo.
- **Autor:** los commits van como «Brizna Soft»
  (`349058083+Brizna-Soft@users.noreply.github.com`), sin líneas que nombren a una IA ni `Co-Authored-By`.
  Se puede decir «Hecho con ayuda de IA».
- **Publicar:** nadie publica una versión (etiqueta `v*`) ni sube a la rama principal sin que el dueño lo
  apruebe. Lo que borra archivos o toca datos personales pasa antes por una revisión de solo lectura.

## Revisiones de solo lectura

Cuando se pide una revisión sin cambiar archivos:
- No cambies nada, ni siquiera para probar.
- Responde en español sencillo y empieza con **APROBADO** o **FALTA**.
- Para cada falla: gravedad (alta, media o baja), archivo, línea y qué le pasaría a la persona.

## Más detalles

Las reglas completas, la estructura de cada programa y cómo compilar están en
`Documents\Brizna-Soft\programas\GUIA-PROGRAMAS.md` (en la PC del estudio) y en el README de este
repositorio.

## Este programa: Mosquitero

Bloqueador de anuncios y rastreadores (extensión MV3 para Chrome, Edge, Brave y Firefox).

- Armar: `powershell -ExecutionPolicy Bypass -File armar.ps1` (sin internet).
- Probar: `powershell -ExecutionPolicy Bypass -File pruebas\probar-en-edge.ps1` (Edge sin ventana, perfiles
  temporales).
- Solo se conecta a internet si la persona pulsa «Buscar actualización». Los reportes llevan solo el nombre del
  sitio, nunca la dirección completa.
- Las listas son de EasyList (CC BY-SA 3.0) y van tal como se bajaron (`listas/*.txt`, con su huella).
