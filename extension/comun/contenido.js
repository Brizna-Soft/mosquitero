// Mosquitero: oculta los huecos que dejan los anuncios.
//
// Lo general ya lo pone el navegador al abrir la página (cosmetico/genericos.css). Este archivo le
// pregunta al trabajo de fondo qué más hay que ocultar en este sitio. Donde la persona apagó Mosquitero
// (o donde las listas piden no usar lo general), marca la página para que la hoja general no se aplique.
// No lee ni guarda nada de lo que hay en la página.
(() => {
  const api = globalThis.browser ?? globalThis.chrome;
  const PAUSA = "data-mosquitero-pausa";
  const POR_GRUPO = 10; // si un selector no sirve, el navegador descarta solo su grupo

  function pausar() {
    const marcar = () => {
      const raiz = document.documentElement;
      if (raiz && !raiz.hasAttribute(PAUSA)) raiz.setAttribute(PAUSA, "");
    };
    marcar();
    // Si la página cambia su <html> o le quita la marca, se vuelve a poner
    const vigia = new MutationObserver(marcar);
    vigia.observe(document, { childList: true });
    if (document.documentElement) vigia.observe(document.documentElement, { attributes: true, attributeFilter: [PAUSA] });
  }

  function ocultar(selectores) {
    const grupos = [];
    for (let i = 0; i < selectores.length; i += POR_GRUPO) {
      grupos.push(selectores.slice(i, i + POR_GRUPO).join(",\n") + " { display: none !important; }");
    }
    const texto = grupos.join("\n");

    const estilo = document.createElement("style");
    estilo.textContent = texto;
    const poner = () => {
      const raiz = document.documentElement;
      if (raiz && estilo.parentNode !== raiz) raiz.appendChild(estilo);
    };
    poner();
    if (estilo.isConnected && !estilo.sheet) {
      // La página no deja poner estilos (su política de seguridad): se usa una hoja «adoptada»
      try {
        const hoja = new CSSStyleSheet();
        hoja.replaceSync(texto);
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, hoja];
        estilo.remove();
        return;
      } catch (e) {
        // Si tampoco se puede, queda lo general
      }
    }
    // Si la página quita la hoja o cambia su <html>, se vuelve a poner
    const vigia = new MutationObserver(poner);
    vigia.observe(document, { childList: true });
    if (document.documentElement) vigia.observe(document.documentElement, { childList: true });
  }

  let pregunta;
  try {
    pregunta = api.runtime.sendMessage({ tipo: "ocultar" });
  } catch (e) {
    return; // la extensión se actualizó o se quitó: esta página se queda como está
  }
  Promise.resolve(pregunta).then(
    (r) => {
      if (!r || r.error) return;
      if (r.generales === false) pausar();
      if (Array.isArray(r.selectores) && r.selectores.length) ocultar(r.selectores);
    },
    () => {}
  );
})();
