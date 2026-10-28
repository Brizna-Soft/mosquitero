// Solo para la copia de prueba (pruebas-locales\edge\extension-prueba): carga el trabajo de fondo de
// verdad y agrega el mensaje «prueba-control», que hace lo mismo que la ventanita: apaga el sitio de la
// página o los rastreadores. Además pregunta a Edge qué reglas cazarían algunas direcciones
// (testMatchOutcome, que solo existe en extensiones sin empaquetar). Nunca va dentro de los zip.
importScripts("background.js");

const DIRECCIONES = [
  ["https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js", "script"],
  ["https://securepubads.g.doubleclick.net/tag/js/gpt.js", "script"],
  ["https://www.googletagservices.com/tag/js/gpt.js", "script"],
  ["https://www.google-analytics.com/analytics.js", "script"],
  ["https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js", "script"],
];

async function probarDirecciones() {
  const salida = [];
  for (const [url, type] of DIRECCIONES) {
    try {
      const r = await chrome.declarativeNetRequest.testMatchOutcome({ url, type, initiator: "https://ejemplo.test", tabId: -1 });
      salida.push({ url, reglas: r.matchedRules.map((m) => m.rulesetId + "#" + m.ruleId) });
    } catch (e) {
      salida.push({ url, error: String((e && e.message) || e) });
    }
  }
  return salida;
}

chrome.runtime.onMessage.addListener((mensaje, _remitente, responder) => {
  if (!mensaje || mensaje.tipo !== "prueba-control") return false;
  (async () => {
    const antes = await probarDirecciones();
    const disponibles = await chrome.declarativeNetRequest.getAvailableStaticRuleCount();
    if (mensaje.accion === "apagar-sitio") await cambiarSitio(mensaje.url, false);
    else if (mensaje.accion === "sin-rastreadores") await cambiarRastreadores(false);
    return {
      accion: mensaje.accion,
      antes,
      disponibles,
      dinamicas: await chrome.declarativeNetRequest.getDynamicRules(),
      activos: await chrome.declarativeNetRequest.getEnabledRulesets(),
      ajustes: await chrome.storage.local.get(null),
    };
  })().then(responder, (e) => responder({ error: String((e && e.message) || e) }));
  return true;
});
