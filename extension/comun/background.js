// Mosquitero: deja afuera los anuncios y los rastreadores.
//
// Trabajo de fondo de la extensión. Hace tres cosas:
//   1. Aplica los ajustes de la persona: los sitios donde la apagó (una regla allowAllRequests por
//      sitio) y si se bloquean los rastreadores (el conjunto de reglas «rastreadores»).
//   2. Le pide al navegador que muestre en el ícono cuántas cosas bloqueó en la página.
//   3. Le dice a cada página qué ocultar, según su sitio (cosmetico/por-sitio.json).
//
// Las listas viajan dentro de la extensión, ya convertidas. No se baja nada de internet y no se manda
// nada a ningún servidor. Lo único que se guarda, en el propio navegador, son los dos ajustes de arriba.

const api = globalThis.browser ?? globalThis.chrome;
const dnr = api.declarativeNetRequest;

const AJUSTES = { sitiosApagados: [], rastreadores: true };
const PRIORIDAD_APAGADO = 100; // gana a todas las reglas de las listas, que van de 1 a 3
const COLOR_CONTADOR = "#3C4650";

// ---------------------------------------------------------------- sitios

function hostDe(url) {
  let u;
  try {
    u = new URL(url);
  } catch (e) {
    return "";
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return "";
  const host = u.hostname.toLowerCase().replace(/\.$/, "");
  return /^[a-z0-9_-]+(\.[a-z0-9_-]+)*$/.test(host) ? host : "";
}

// «www.ejemplo.com» y «ejemplo.com» son el mismo sitio; sus subdominios quedan dentro.
function sitioDe(url) {
  const host = hostDe(url);
  if (host.startsWith("www.") && host.split(".").length > 2) return host.slice(4);
  return host;
}

function dentroDe(host, sitio) {
  return host === sitio || host.endsWith("." + sitio);
}

function apagadoEn(host, sitios) {
  return !!host && sitios.some((s) => dentroDe(host, s));
}

// Claves con las que un sitio aparece en las listas: el dominio, sus dominios de arriba y los
// comodines «sitio.*», que valen para sitio.com, sitio.com.mx, sitio.co.uk...
function clavesDe(host) {
  const claves = [];
  if (!host) return claves;
  const p = host.split(".");
  const n = p.length;
  for (let i = 0; i < n; i++) {
    claves.push(p.slice(i).join("."));
    if (n - i >= 2) claves.push(p.slice(i, n - 1).join(".") + ".*");
    if (n - i >= 3 && p[n - 2].length <= 3) claves.push(p.slice(i, n - 2).join(".") + ".*");
  }
  return claves;
}

// ---------------------------------------------------------------- ajustes

async function leerAjustes() {
  const a = await api.storage.local.get(AJUSTES);
  return {
    sitiosApagados: Array.isArray(a.sitiosApagados)
      ? a.sitiosApagados.filter((s) => typeof s === "string" && /^[a-z0-9_-]+(\.[a-z0-9_-]+)*$/.test(s))
      : [],
    rastreadores: a.rastreadores !== false,
  };
}

let ajustesEnMemoria = null;
function ajustes() {
  if (!ajustesEnMemoria) ajustesEnMemoria = leerAjustes();
  return ajustesEnMemoria;
}
api.storage.onChanged.addListener((_cambios, area) => {
  if (area === "local") ajustesEnMemoria = null;
});

// Una regla dinámica por sitio apagado: deja pasar todo lo de esa pestaña.
async function aplicarSitiosApagados(sitios) {
  const viejas = await dnr.getDynamicRules();
  const nuevas = sitios.map((sitio, i) => ({
    id: i + 1,
    priority: PRIORIDAD_APAGADO,
    action: { type: "allowAllRequests" },
    condition: { requestDomains: [sitio], resourceTypes: ["main_frame"] },
  }));
  await dnr.updateDynamicRules({ removeRuleIds: viejas.map((r) => r.id), addRules: nuevas });
}

async function aplicarRastreadores(activo) {
  const activos = await dnr.getEnabledRulesets();
  if (activos.includes("rastreadores") === activo) return;
  await dnr.updateEnabledRulesets(
    activo ? { enableRulesetIds: ["rastreadores"] } : { disableRulesetIds: ["rastreadores"] }
  );
}

// Chrome, Edge y Brave cuentan solos lo que bloquean y lo muestran en el ícono. Firefox todavía no.
function hayContador() {
  return typeof dnr.setExtensionActionOptions === "function";
}

async function prepararContador() {
  if (hayContador()) {
    try {
      await dnr.setExtensionActionOptions({ displayActionCountAsBadgeText: true });
    } catch (e) {
      // Sin contador: todo lo demás sigue igual
    }
  }
  try {
    await api.action.setBadgeBackgroundColor({ color: COLOR_CONTADOR });
    if (api.action.setBadgeTextColor) await api.action.setBadgeTextColor({ color: "#FFFFFF" });
  } catch (e) {
    // Solo es el color del número
  }
}

// Los cambios de ajustes van en fila, uno detrás de otro, para que nunca se pisen
let fila = Promise.resolve();
function enFila(tarea) {
  const hecho = fila.then(() => tarea());
  fila = hecho.catch(() => {});
  return hecho;
}

// Al instalar, al actualizar y al abrir el navegador se vuelven a aplicar los ajustes guardados
// (al actualizar, el navegador vuelve a activar todos los conjuntos de reglas).
function prepararTodo() {
  return enFila(async () => {
    try {
      const a = await leerAjustes();
      await aplicarRastreadores(a.rastreadores);
      await aplicarSitiosApagados(a.sitiosApagados);
      await prepararContador();
    } catch (e) {
      console.warn("Mosquitero:", e);
    }
  });
}
api.runtime.onInstalled.addListener(() => {
  prepararTodo();
});
api.runtime.onStartup.addListener(() => {
  prepararTodo();
});

// ---------------------------------------------------------------- lo que pregunta la ventanita

async function estadoPara(url) {
  const a = await ajustes();
  const sitio = sitioDe(url || "");
  return {
    sitio,
    activo: sitio ? !apagadoEn(hostDe(url), a.sitiosApagados) : true,
    rastreadores: a.rastreadores,
    contador: hayContador(),
  };
}

function cambiarSitio(url, activo) {
  return enFila(async () => {
    const sitio = sitioDe(url || "");
    const host = hostDe(url || "");
    if (!sitio) throw new Error("Mosquitero no funciona en esta página.");
    const a = await leerAjustes();
    let lista = a.sitiosApagados.slice();
    if (activo) lista = lista.filter((s) => !dentroDe(host, s));
    else if (!lista.includes(sitio)) lista.push(sitio);
    lista.sort();
    await api.storage.local.set({ sitiosApagados: lista });
    ajustesEnMemoria = null;
    await aplicarSitiosApagados(lista);
  }).then(() => estadoPara(url));
}

function cambiarRastreadores(activo) {
  return enFila(async () => {
    await api.storage.local.set({ rastreadores: activo });
    ajustesEnMemoria = null;
    await aplicarRastreadores(activo);
    return { rastreadores: activo };
  });
}

// ---------------------------------------------------------------- lo que pregunta cada página

let datosSitios = null;
function cargarDatos() {
  if (!datosSitios) {
    datosSitios = fetch(api.runtime.getURL("cosmetico/por-sitio.json"))
      .then((r) => r.json())
      .then((j) => ({
        selectores: j.selectores,
        conExcepcion: j.conExcepcion,
        ocultar: new Map(Object.entries(j.ocultar)),
        excepciones: new Map(Object.entries(j.excepciones)),
        sinGenericos: new Set(j.sinGenericos),
        sinOcultar: new Set(j.sinOcultar),
      }))
      .catch((e) => {
        datosSitios = null;
        throw e;
      });
  }
  return datosSitios;
}

// generales: false pausa la hoja general (genericos.css) en esa página.
// selectores: lo que esa página tiene que ocultar además de lo general.
async function queOcultar(remitente) {
  const a = await ajustes();
  const pestana = (remitente.tab && remitente.tab.url) || remitente.url || "";
  if (apagadoEn(hostDe(pestana), a.sitiosApagados)) return { generales: false, selectores: [] };

  const host = hostDe(remitente.url || "");
  if (!host) return { generales: true, selectores: [] };
  const datos = await cargarDatos();
  const claves = clavesDe(host);
  if (claves.some((c) => datos.sinOcultar.has(c))) return { generales: false, selectores: [] };
  const generales = !claves.some((c) => datos.sinGenericos.has(c));

  const ocultar = new Set();
  const excepto = new Set();
  for (const c of claves) {
    const o = datos.ocultar.get(c);
    if (o) for (const i of o) ocultar.add(i);
    const x = datos.excepciones.get(c);
    if (x) for (const i of x) excepto.add(i);
  }
  if (generales) for (const i of datos.conExcepcion) ocultar.add(i);
  const selectores = [];
  for (const i of ocultar) if (!excepto.has(i)) selectores.push(datos.selectores[i]);
  return { generales, selectores };
}

// ---------------------------------------------------------------- mensajes

// Solo las páginas de la propia extensión (la ventanita) pueden cambiar los ajustes; los scripts que
// corren dentro de las páginas web solo pueden preguntar qué ocultar.
function esDeLaVentanita(remitente) {
  return typeof remitente.url === "string" && remitente.url.startsWith(api.runtime.getURL(""));
}

api.runtime.onMessage.addListener((mensaje, remitente, responder) => {
  if (!mensaje || typeof mensaje.tipo !== "string" || remitente.id !== api.runtime.id) return false;
  let tarea = null;
  if (mensaje.tipo === "ocultar") {
    tarea = queOcultar(remitente);
  } else if (esDeLaVentanita(remitente)) {
    if (mensaje.tipo === "estado") tarea = estadoPara(mensaje.url);
    else if (mensaje.tipo === "sitio") tarea = cambiarSitio(mensaje.url, mensaje.activo === true);
    else if (mensaje.tipo === "rastreadores") tarea = cambiarRastreadores(mensaje.activo === true);
  }
  if (!tarea) return false;
  tarea.then(responder, (e) => responder({ error: String((e && e.message) || e) }));
  return true;
});
