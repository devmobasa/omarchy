// Intentionally not `.pragma library`: QML JavaScript imports get a private
// module instance per importing component. shell.qml's instance retains the
// authentication services; a third-party plugin importing this file receives
// a separate empty store rather than a shared path to credential-bearing QML.

var services = ({})
var trustedIds = ({})
var capturePublisher = null
var captureGeneration = 0
var captureConnections = []

// Publish scalars only. Neither the service nor a closure returning it crosses
// the authentication-store boundary. Unknown/blocked changes are synchronous;
// unlocking waits one event turn so multi-property recovery updates settle.
function setCaptureStatePublisher(publisher) {
  capturePublisher = publisher
  refreshCaptureState()
}

function publishCaptureState(known, locked) {
  captureGeneration++
  if (capturePublisher) capturePublisher(Object.freeze({
    version: 1, known: known, locked: locked, generation: captureGeneration
  }))
}

function refreshCaptureState() {
  publishCaptureState(false, true)
  var service = services["omarchy.lock"]
  if (!service || captureConnections.length !== 4) return
  if (service.locked === true) {
    publishCaptureState(true, true)
    return
  }
  var generation = captureGeneration
  Qt.callLater(function() {
    if (generation !== captureGeneration || services["omarchy.lock"] !== service) return
    if (service.strandedLockResolved === true && service.strandedLock === false && service.locked === false)
      publishCaptureState(true, false)
  })
}

function detachCaptureState() {
  publishCaptureState(false, true)
  for (var i = 0; i < captureConnections.length; i++) {
    var connection = captureConnections[i]
    connection.signal.disconnect(connection.handler)
  }
  captureConnections = []
}

function observeCaptureState(service) {
  var signals = [service.lockedChanged, service.strandedLockChanged,
    service.strandedLockResolvedChanged, service.captureStateInvalidated]
  if (!signals.every(function(signal) { return signal && typeof signal.connect === "function" })) return
  for (var i = 0; i < signals.length; i++) {
    var handler = i === 3 ? detachCaptureState : refreshCaptureState
    signals[i].connect(handler)
    captureConnections.push({ signal: signals[i], handler: handler })
  }
  refreshCaptureState()
}

function has(id) {
  return services[String(id || "")] !== undefined
}

function put(id, service) {
  var key = String(id || "")
  if (!key || !service) return
  if (key === "omarchy.lock") detachCaptureState()
  trustedIds[key] = true
  if (services[key] && services[key] !== service && typeof services[key].destroy === "function")
    services[key].destroy()
  services[key] = service
  if (key === "omarchy.lock") observeCaptureState(service)
}

function isTrusted(id) {
  return trustedIds[String(id || "")] === true
}

function ids() {
  return Object.keys(services)
}

function updateManifest(id, manifest) {
  var service = services[String(id || "")]
  if (service && "manifest" in service) service.manifest = manifest
}

function destroy(id) {
  var key = String(id || "")
  var service = services[key]
  if (key === "omarchy.lock") detachCaptureState()
  if (service && typeof service.destroy === "function") service.destroy()
  delete services[key]
}

function destroyAll() {
  var keys = ids()
  for (var i = 0; i < keys.length; i++) destroy(keys[i])
}
