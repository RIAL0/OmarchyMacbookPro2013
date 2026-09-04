import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Shows which GPU is driving the built-in panel on a dual-GPU MacBook Pro
// (Apple gmux): "iGPU" (Intel) or "dGPU" (NVIDIA). Highlighted when a switch
// has been queued for the next boot. Click to open the switcher.
BarWidget {
  id: root
  moduleName: "rial.gpu-status"

  property string gpuState: "unknown"   // integrated | dedicated | pending | unknown
  property string label: "GPU"
  property string detail: "Checking GPU state..."

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.local/bin/omarchy-gpu-switch", "status", "--widget"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("|")
        root.gpuState = parts[0] || "unknown"
        root.label = parts[1] || "GPU"
        root.detail = parts[2] || ""
      }
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    active: root.gpuState === "pending"
    tooltipText: root.detail
    pressable: true
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-gpu-switch")
      } else {
        root.refresh()
      }
    }
  }
}
