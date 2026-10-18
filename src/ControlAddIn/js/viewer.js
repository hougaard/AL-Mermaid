// Viewer for SVG produced by the AL port of pele. AL calls ShowSvg, ShowError and ShowPlaceholder.
var MermaidViewer = (function () {
  var root = null;
  var stage = null;
  var message = null;
  var zoomLabel = null;
  var zoom = 1;
  var fit = true;
  var dark = false;

  var SVG_NS = 'http://www.w3.org/2000/svg';

  function button(text, title, onClick) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = text;
    b.title = title;
    b.addEventListener('click', onClick);
    return b;
  }

  function init(host) {
    root = document.createElement('div');
    root.className = 'mv-root';

    var toolbar = document.createElement('div');
    toolbar.className = 'mv-toolbar';
    toolbar.appendChild(button('−', 'Zoom out', function () { setZoom(zoom / 1.25); }));
    zoomLabel = document.createElement('span');
    zoomLabel.className = 'mv-zoom';
    toolbar.appendChild(zoomLabel);
    toolbar.appendChild(button('+', 'Zoom in', function () { setZoom(zoom * 1.25); }));
    toolbar.appendChild(button('Fit', 'Fit to width', function () { fit = true; zoom = 1; apply(); }));
    toolbar.appendChild(button('1:1', 'Actual size', function () { fit = false; zoom = 1; apply(); }));
    toolbar.appendChild(button('Theme', 'Switch between light and dark', function () {
      dark = !dark;
      root.classList.toggle('mv-dark', dark);
    }));

    stage = document.createElement('div');
    stage.className = 'mv-stage';

    message = document.createElement('div');
    message.className = 'mv-message';

    root.appendChild(toolbar);
    root.appendChild(message);
    root.appendChild(stage);
    host.appendChild(root);
    apply();
  }

  function setZoom(value) {
    fit = false;
    zoom = Math.max(0.1, Math.min(8, value));
    apply();
  }

  function apply() {
    var svg = stage ? stage.querySelector('svg') : null;
    if (zoomLabel) zoomLabel.textContent = fit ? 'Fit' : Math.round(zoom * 100) + '%';
    if (!svg) return;
    var w = parseFloat(svg.getAttribute('width')) || 0;
    if (fit) {
      svg.style.width = '';
      svg.style.maxWidth = '100%';
      svg.style.height = 'auto';
    } else {
      svg.style.maxWidth = 'none';
      svg.style.width = (w * zoom) + 'px';
      svg.style.height = 'auto';
    }
  }

  // Keeps only what draws: no scripts, no foreign content, no event handlers, no script URLs.
  function clean(node) {
    var children = Array.prototype.slice.call(node.childNodes);
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (child.nodeType !== 1) continue;
      var name = child.localName.toLowerCase();
      if (name === 'script' || name === 'foreignobject' || name === 'iframe' || name === 'object' || name === 'embed') {
        node.removeChild(child);
        continue;
      }
      var attrs = Array.prototype.slice.call(child.attributes);
      for (var j = 0; j < attrs.length; j++) {
        var attr = attrs[j];
        var an = attr.name.toLowerCase();
        var value = (attr.value || '').replace(/[\s\u0000-\u001f]+/g, '').toLowerCase();
        if (an.indexOf('on') === 0) child.removeAttribute(attr.name);
        else if ((an === 'href' || an === 'xlink:href') && (value.indexOf('javascript:') === 0 || value.indexOf('data:text') === 0 || value.indexOf('vbscript:') === 0)) {
          child.removeAttribute(attr.name);
        }
      }
      clean(child);
    }
  }

  function clear() {
    while (stage.firstChild) stage.removeChild(stage.firstChild);
    message.textContent = '';
    message.className = 'mv-message';
  }

  function showSvg(text) {
    if (!stage) return;
    clear();
    var doc = new DOMParser().parseFromString(text, 'image/svg+xml');
    var svg = doc.documentElement;
    if (!svg || svg.localName !== 'svg' || svg.namespaceURI !== SVG_NS || doc.getElementsByTagName('parsererror').length > 0) {
      showError('The SVG could not be read.');
      return;
    }
    clean(svg);
    // Links in a diagram open outside the Business Central frame.
    var anchors = svg.getElementsByTagName('a');
    for (var i = 0; i < anchors.length; i++) anchors[i].setAttribute('target', '_blank');
    stage.appendChild(document.importNode(svg, true));
    apply();
  }

  function showError(text) {
    if (!stage) return;
    clear();
    message.className = 'mv-message mv-error';
    message.textContent = text;
  }

  function showPlaceholder(text) {
    if (!stage) return;
    clear();
    message.className = 'mv-message mv-placeholder';
    message.textContent = text;
  }

  return { init: init, showSvg: showSvg, showError: showError, showPlaceholder: showPlaceholder };
})();

function ShowSvg(svg) {
  MermaidViewer.showSvg(svg);
}

function ShowError(text) {
  MermaidViewer.showError(text);
}

function ShowPlaceholder(text) {
  MermaidViewer.showPlaceholder(text);
}
