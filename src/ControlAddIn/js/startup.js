// Builds the viewer inside the control add-in frame and tells AL that it is ready.
(function () {
  MermaidViewer.init(document.getElementById('controlAddIn'));
  Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('ControlReady', []);
})();
