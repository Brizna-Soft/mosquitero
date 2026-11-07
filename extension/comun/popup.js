// La ventanita de Mosquitero: el sitio actual, «Activo en este sitio» y «Bloquear rastreadores».
const api = globalThis.browser ?? globalThis.chrome;
const $ = (id) => document.getElementById(id);

const REPO = "Brizna-Soft/mosquitero";
const FORMULARIO = "https://github.com/" + REPO + "/issues/new";

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

// El nombre del navegador, tal como sale en la lista del formulario de GitHub
async function nombreDelNavegador() {
  try {
    if (api.runtime.getBrowserInfo) {
      const info = await api.runtime.getBrowserInfo();
      if (info && /firefox/i.test(info.name)) return "Firefox";
    }
  } catch (e) {
    // sigue con lo demás
  }
  try {
    if (navigator.brave && (await navigator.brave.isBrave())) return "Brave";
  } catch (e) {
    // sigue con lo demás
  }
  const marcas = (navigator.userAgentData && navigator.userAgentData.brands) || [];
  if (marcas.some((m) => /edge/i.test(m.brand))) return "Edge";
  if (marcas.some((m) => /chrom/i.test(m.brand))) return "Chrome";
  return "Otro";
}

// Los formularios de GitHub se abren con lo que ya se sabe escrito: solo el nombre del sitio (nunca la dirección
// completa), la versión y el navegador. Nada se abre si no se pulsa.
function prepararReportes(sitio, version, navegador) {
  for (const [id, plantilla] of [["enlace-falla", "falla.yml"], ["enlace-anuncio", "anuncio.yml"]]) {
    const p = new URLSearchParams({ template: plantilla, version, navegador });
    if (sitio) p.set("sitio", sitio);
    $(id).href = FORMULARIO + "?" + p.toString();
  }
}

// «1.2.3» contra «1.2.4»: negativo si a es menor
function compararVersiones(a, b) {
  const partes = (v) => String(v).replace(/^v/i, "").split(".").map((x) => parseInt(x, 10) || 0);
  const pa = partes(a), pb = partes(b);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  }
  return 0;
}

// Solo al pulsar: le pregunta a GitHub cuál es la última versión. No manda nada tuyo.
async function buscarActualizacion(version) {
  const boton = $("buscar");
  boton.disabled = true;
  avisar("aviso-actualizacion", "Buscando…");
  try {
    const r = await fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
      credentials: "omit",
      cache: "no-store",
    });
    if (!r.ok) throw new Error(String(r.status));
    const j = await r.json();
    const etiqueta = String(j.tag_name || "");
    if (!etiqueta) throw new Error("sin versión");
    if (compararVersiones(etiqueta, version) <= 0) {
      avisar("aviso-actualizacion", "Ya tienes la versión más nueva (" + version + ").");
    } else {
      const p = $("aviso-actualizacion");
      p.classList.remove("mal");
      p.textContent =
        "Hay una versión nueva: " + etiqueta.replace(/^v/i, "") + " (tienes la " + version + "). Para ponerla, bájala, " +
        "descomprímela en la misma carpeta de ahora y pulsa Recargar en la página de extensiones. ";
      const a = document.createElement("a");
      a.href = "https://github.com/" + REPO + "/releases/latest";
      a.target = "_blank";
      a.rel = "noopener";
      a.textContent = "Ver la versión nueva";
      p.appendChild(a);
    }
  } catch (e) {
    avisar("aviso-actualizacion", "No pude buscar la actualización. Revisa tu internet y vuelve a intentarlo.", true);
  }
  boton.disabled = false;
}

// La fecha de las listas la escribe armar.ps1 en fecha-listas.txt («2026-10-28»)
async function mostrarFechaListas() {
  try {
    const r = await fetch(api.runtime.getURL("fecha-listas.txt"));
    if (!r.ok) return;
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec((await r.text()).trim());
    if (m) $("fecha-listas").textContent = " · listas del " + m[3] + "/" + m[2] + "/" + m[1];
  } catch (e) {
    // sin la fecha, el pie queda como antes
  }
}

function mostrarPalabra(activo) {
  $("palabra-activo").textContent = activo.checked ? "Sí" : "No";
}

async function iniciar() {
  const version = api.runtime.getManifest().version;
  $("version").textContent = version;
  mostrarFechaListas();
  $("buscar").addEventListener("click", () => buscarActualizacion(version));
  const activo = $("activo");
  const rastreadores = $("rastreadores");
  const navegador = nombreDelNavegador();
  prepararReportes("", version, "Otro");
  navegador.then((n) => prepararReportes("", version, n));

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
  if (!estado.contador) {
    $("nota-contador").textContent = "En este navegador no sale el número sobre el ícono, pero Mosquitero sí bloquea.";
  }

  if (estado.sitio) {
    $("sitio").textContent = estado.sitio;
    activo.checked = estado.activo;
    if (!estado.activo) avisar("aviso-sitio", "Mosquitero está apagado aquí: no bloquea ni oculta nada en este sitio.");
    prepararReportes(estado.sitio, version, await navegador);
  } else {
    $("sitio").textContent = "Esta página";
    activo.checked = false;
    activo.disabled = true;
    $("nota-recarga").hidden = true;
    avisar(
      "aviso-sitio",
      /^file:/i.test(url)
        ? "Mosquitero no trabaja en los archivos de tu PC. Abre un sitio web para usarlo."
        : "Mosquitero no trabaja en las páginas propias del navegador. Abre un sitio web para usarlo."
    );
  }
  mostrarPalabra(activo);

  activo.addEventListener("change", async () => {
    activo.disabled = true;
    mostrarPalabra(activo);
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
      mostrarPalabra(activo);
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
