// Solo para la copia de prueba. Si la dirección trae ?preparar=apagar-sitio o ?preparar=sin-rastreadores,
// le pide al trabajo de fondo que haga lo mismo que la ventanita y vuelve a abrir la página (en la misma
// sesión de Edge), con la respuesta en #datos= para que la página de prueba la muestre.
const parametros = new URLSearchParams(location.search);
const accion = parametros.get("preparar");

function seguir(control) {
  parametros.delete("preparar");
  parametros.set("paso", accion);
  location.replace(location.pathname + "?" + parametros.toString() + "#datos=" + encodeURIComponent(JSON.stringify({ control })));
}

if (accion) {
  chrome.runtime.sendMessage({ tipo: "prueba-control", accion, url: location.href }).then(seguir, (e) => seguir({ error: String(e) }));
}
