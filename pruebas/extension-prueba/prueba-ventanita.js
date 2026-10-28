// Solo para la copia de prueba: revisa que la ventanita arranque, que hable con el trabajo de fondo y
// que la casilla «Bloquear rastreadores» apague de verdad ese conjunto de reglas.
(async () => {
  const puerto = new URLSearchParams(location.search).get("puerto");
  // Esperas «de red», para que el reloj de Edge sin ventana no se adelante
  const esperar = (ms) => fetch("http://127.0.0.1:" + puerto + "/esperar?ms=" + ms).catch(() => {});
  await new Promise((r) => (document.readyState === "complete" ? r() : addEventListener("load", r)));
  await esperar(1500);

  const d = document.getElementById("ventanita").contentDocument;
  const r = {
    version: d.getElementById("version").textContent,
    sitio: d.getElementById("sitio").textContent,
    interruptorDesactivado: d.getElementById("activo").disabled,
    rastreadores: d.getElementById("rastreadores").checked,
    notaContador: !d.getElementById("nota-contador").hidden,
    aviso: d.getElementById("aviso-sitio").textContent,
    activosAntes: await chrome.declarativeNetRequest.getEnabledRulesets(),
  };
  d.getElementById("rastreadores").click();
  await esperar(1500);
  r.avisoRastreadores = d.getElementById("aviso-rastreadores").textContent;
  r.activosDespues = await chrome.declarativeNetRequest.getEnabledRulesets();
  r.ajustes = await chrome.storage.local.get(null);

  document.getElementById("resultado").textContent = JSON.stringify(r).replace(
    /[\u007f-￿]/g,
    (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0")
  );
})();
