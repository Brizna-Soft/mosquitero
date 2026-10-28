// La ventanita de Mosquitero: el sitio actual, «Activo en este sitio» y «Bloquear rastreadores».
const api = globalThis.browser ?? globalThis.chrome;
const $ = (id) => document.getElementById(id);

function avisar(id, texto, mal) {
  const p = $(id);
  p.textContent = texto;
  p.classList.toggle("mal", !!mal);
}

async function preguntar(mensaje) {
  const r = await api.runtime.sendMessage(mensaje);
  if (!r || r.error) throw new Error((r && r.error) || "Sin respuesta.");
  return r;
}

async function iniciar() {
  $("version").textContent = api.runtime.getManifest().version;
  const activo = $("activo");
  const rastreadores = $("rastreadores");

  let pestana = null;
  try {
    [pestana] = await api.tabs.query({ active: true, currentWindow: true });
  } catch (e) {
    pestana = null;
  }
  const url = (pestana && pestana.url) || "";

  let estado;
  try {
    estado = await preguntar({ tipo: "estado", url });
  } catch (e) {
    avisar("aviso-sitio", "No pude leer los ajustes. Cierra esta ventanita y vuelve a abrirla.", true);
    return;
  }

  rastreadores.checked = estado.rastreadores;
  if (!estado.contador) $("nota-contador").hidden = true;

  if (estado.sitio) {
    $("sitio").textContent = estado.sitio;
    activo.checked = estado.activo;
    if (!estado.activo) avisar("aviso-sitio", "Mosquitero está apagado aquí: no bloquea ni oculta nada en este sitio.");
  } else {
    $("sitio").textContent = "Esta página";
    activo.checked = false;
    activo.disabled = true;
    avisar("aviso-sitio", "Mosquitero no trabaja en las páginas propias del navegador. Abre un sitio web para usarlo.");
  }

  activo.addEventListener("change", async () => {
    activo.disabled = true;
    try {
      await preguntar({ tipo: "sitio", url, activo: activo.checked });
      avisar(
        "aviso-sitio",
        activo.checked
          ? "Listo: Mosquitero vuelve a trabajar aquí. Recargando la página…"
          : "Listo: Mosquitero queda apagado en este sitio. Recargando la página…"
      );
      if (pestana && typeof pestana.id === "number") api.tabs.reload(pestana.id);
    } catch (e) {
      activo.checked = !activo.checked;
      avisar("aviso-sitio", "No se pudo cambiar: " + e.message, true);
    }
    activo.disabled = false;
  });

  rastreadores.addEventListener("change", async () => {
    rastreadores.disabled = true;
    try {
      await preguntar({ tipo: "rastreadores", activo: rastreadores.checked });
      avisar(
        "aviso-rastreadores",
        rastreadores.checked
          ? "Los rastreadores se bloquean desde ahora, en todos los sitios."
          : "Los rastreadores ya no se bloquean. Los anuncios, sí."
      );
    } catch (e) {
      rastreadores.checked = !rastreadores.checked;
      avisar("aviso-rastreadores", "No se pudo cambiar: " + e.message, true);
    }
    rastreadores.disabled = false;
  });
}

iniciar();
