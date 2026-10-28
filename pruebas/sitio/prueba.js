// Prueba de Mosquitero. probar-en-edge.ps1 escribe config.js (recursos y elementos) y lee el resultado
// del DOM con --dump-dom. Nada de esto va dentro de la extensión.
(async () => {
  // Con ?preparar=..., la copia de prueba de la extensión cambia un ajuste y vuelve a abrir la página.
  // Mientras tanto se deja una espera «de red», para que Edge sin ventana no dé la página por terminada.
  if (new URLSearchParams(location.search).has("preparar")) {
    fetch("/esperar?ms=8000").catch(() => {});
    return;
  }
  const C = window.CONFIG_PRUEBA;
  const resultado = { host: location.hostname, red: [], ocultar: [], pausa: false };

  // Elementos que se parecen a huecos de anuncios (y uno normal, que nunca debe ocultarse)
  const caja = document.getElementById("cosmetico");
  const elementos = [];
  for (const e of C.elementos) {
    const div = document.createElement("div");
    if (e.id) div.id = e.id;
    if (e.clase) div.className = e.clase;
    div.textContent = e.nombre + " (" + e.selector + ")";
    caja.appendChild(div);
    elementos.push([e, div]);
  }

  // Un momento para que la extensión termine de arrancar (y de aplicar sus ajustes)
  await fetch("/esperar?ms=" + (C.esperaInicial || 1500)).catch(() => {});

  function cargar(r) {
    return new Promise((listo) => {
      const fin = (estado) => listo({ nombre: r.nombre, grupo: r.grupo, como: r.como, url: r.url, estado });
      if (r.como === "fetch") {
        fetch(r.url, { mode: "no-cors", cache: "no-store", credentials: "omit" }).then(
          () => fin("cargó"),
          () => fin("no cargó")
        );
      } else if (r.como === "script") {
        // preload: el navegador lo baja como script, pero no lo ejecuta
        const l = document.createElement("link");
        l.rel = "preload";
        l.as = "script";
        l.href = r.url;
        l.onload = () => fin("cargó");
        l.onerror = () => fin("no cargó");
        document.head.appendChild(l);
      } else {
        const img = new Image();
        img.onload = () => fin("cargó");
        img.onerror = () => fin("no cargó");
        img.src = r.url;
      }
      setTimeout(() => fin("sin respuesta"), 20000);
    });
  }
  resultado.red = await Promise.all(C.recursos.map(cargar));

  // Otro momento (con la red ocupada, el reloj de Edge sin ventana no se adelanta)
  await fetch("/esperar?ms=1500").catch(() => {});
  resultado.pausa = document.documentElement.hasAttribute("data-mosquitero-pausa");
  for (const [e, div] of elementos) {
    resultado.ocultar.push({ nombre: e.nombre, tipo: e.tipo, selector: e.selector, oculto: getComputedStyle(div).display === "none" });
  }

  // Lo que dejó la copia de prueba de la extensión al preparar la página (ver prueba-control.js)
  resultado.previos = {};
  if (location.hash.startsWith("#datos=")) {
    try {
      resultado.previos = JSON.parse(decodeURIComponent(location.hash.slice(7)));
    } catch (e) {
      resultado.previos = { error: "no pude leer #datos" };
    }
  }

  const json = JSON.stringify(resultado).replace(/[\u007f-￿]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
  document.getElementById("resultado").textContent = json;
  document.title = "prueba lista";
})();
