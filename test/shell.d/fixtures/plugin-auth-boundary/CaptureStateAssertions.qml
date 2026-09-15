import QtQuick
import "services/AuthServiceStore.js" as Store

QtObject {
  id: root
  property var failures: []
  property var afterDestruction: null
  property Timer destructionCheck: Timer {
    interval: 10
    onTriggered: root.afterDestruction()
  }
  property Component serviceComponent: Component {
    QtObject {
      property bool locked: false
      property bool strandedLock: false
      property bool strandedLockResolved: true
      property string enteredPassword: "synthetic-secret"
      signal captureStateInvalidated()
      Component.onDestruction: captureStateInvalidated()
    }
  }

  function expect(condition, message) {
    if (!condition) failures = failures.concat([message])
  }

  function run(api, done) {
    Store.setCaptureStatePublisher(function(state) { api._workspaceCaptureState = state })
    expect(api.workspaceCaptureState.known === false && api.workspaceCaptureState.locked === true, "unknown startup")
    var source = serviceComponent.createObject(null)
    Store.put("omarchy.lock", source)
    expect(api.workspaceCaptureState.known === false, "unlock is deferred until state settles")
    Qt.callLater(function() {
      expect(api.workspaceCaptureState.known && !api.workspaceCaptureState.locked, "initial unlocked state")
      var previous = api.workspaceCaptureState
      expect(Object.isFrozen(previous), "frozen scalar snapshot")
      expect(Object.keys(previous).sort().join(",") === "generation,known,locked,version", "no authentication references")
      source.locked = true
      expect(api.workspaceCaptureState.locked && api.workspaceCaptureState.generation > previous.generation, "synchronous lock request")
      expect(!previous.locked, "old snapshots remain detached")
      source.locked = false
      expect(!api.workspaceCaptureState.known && api.workspaceCaptureState.locked, "unlock remains blocked until settled")
      Qt.callLater(function() {
        expect(api.workspaceCaptureState.known && !api.workspaceCaptureState.locked, "settled unlock")
        source.strandedLockResolved = false
        expect(!api.workspaceCaptureState.known && api.workspaceCaptureState.locked, "lost lock knowledge")
        source.strandedLock = true
        source.strandedLockResolved = true
        Qt.callLater(function() {
          expect(!api.workspaceCaptureState.known && api.workspaceCaptureState.locked, "stranded lock")
          source.strandedLock = false
          var replacement = serviceComponent.createObject(null, { locked: true })
          Store.put("omarchy.lock", replacement)
          Qt.callLater(function() {
            expect(api.workspaceCaptureState.locked, "replacement cancels stale unlock completion")
            Store.destroy("omarchy.lock")
            expect(!api.workspaceCaptureState.known && api.workspaceCaptureState.locked, "store removal clears synchronously")
            var disposable = serviceComponent.createObject(null)
            Store.put("omarchy.lock", disposable)
            Qt.callLater(function() {
              expect(api.workspaceCaptureState.known && !api.workspaceCaptureState.locked, "replacement can become ready")
              root.afterDestruction = function() {
                expect(!api.workspaceCaptureState.known && api.workspaceCaptureState.locked, "QObject destruction clears readiness")
                done(root.failures)
              }
              disposable.destroy()
              root.destructionCheck.start()
            })
          })
        })
      })
    })
  }
}
