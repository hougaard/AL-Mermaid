// Viewer for SVG produced by the AL port of pele. AL calls ShowSvg, ShowError, ShowPlaceholder, SetClickMode and
// SetLinkHandling; the viewer raises ElementClicked when the user clicks an element of the diagram.
var MermaidViewer = (function () {
  var root = null;
  var stage = null;
  var message = null;
  var zoomLabel = null;
  var zoom = 1;
  var fit = true;
  var dark = false;
  var clickMode = 'all';
  var linksInAL = false;

  var SVG_NS = 'http://www.w3.org/2000/svg';

  // What a clicked element is, from its pele-* classes, most specific first.
  var KINDS = [
    'actor', 'message', 'note', 'activation', 'lifeline',
    'task', 'milestone', 'vert',
    'commit', 'branch',
    'slice', 'legend-item',
    'period', 'event', 'section',
    'entity', 'class', 'interface', 'namespace',
    'state',
    'edge-label', 'edge',
    'node', 'cluster', 'box'
  ];

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
    stage.addEventListener('click', onStageClick);

    message = document.createElement('div');
    message.className = 'mv-message';

    root.appendChild(toolbar);
    root.appendChild(message);
    root.appendChild(stage);
    host.appendChild(root);
    applyClickMode();
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

  // ---------------------------------------------------------------- clicks

  function applyClickMode() {
    if (!root) return;
    root.classList.remove('mv-click-all', 'mv-click-clickable');
    if (clickMode === 'all') root.classList.add('mv-click-all');
    else if (clickMode === 'clickable') root.classList.add('mv-click-clickable');
  }

  function setClickMode(mode) {
    var m = String(mode || '').toLowerCase();
    clickMode = m === 'clickable' || m === 'none' ? m : 'all';
    applyClickMode();
  }

  function setLinkHandling(handleInAL) {
    linksInAL = !!handleInAL;
  }

  function classesOf(el) {
    return el.getAttribute('class') || '';
  }

  function kindOf(classes) {
    var list = ' ' + classes + ' ';
    for (var i = 0; i < KINDS.length; i++) {
      if (list.indexOf(' pele-' + KINDS[i] + ' ') >= 0) return KINDS[i];
    }
    var first = classes.split(/\s+/).filter(function (c) { return c.indexOf('pele-') === 0; })[0];
    return first ? first.substring(5) : 'element';
  }

  function isClickable(el, anchor) {
    var classes = ' ' + classesOf(el) + ' ';
    return !!anchor || el.hasAttribute('data-callback') || classes.indexOf(' clickable ') >= 0 || classes.indexOf(' pele-clickable ') >= 0;
  }

  // The nearest element with an id, inside the diagram.
  function targetOf(node) {
    var svg = stage.querySelector('svg');
    while (node && node !== stage) {
      if (node.nodeType === 1 && node.hasAttribute && node.hasAttribute('data-id') && node !== svg) return node;
      node = node.parentNode;
    }
    return null;
  }

  function anchorOf(node) {
    while (node && node !== stage) {
      if (node.nodeType === 1 && node.localName && node.localName.toLowerCase() === 'a') return node;
      node = node.parentNode;
    }
    return null;
  }

  function onStageClick(e) {
    if (clickMode === 'none') return;
    var el = targetOf(e.target);
    if (!el) return;
    var anchor = anchorOf(e.target);
    if (clickMode === 'clickable' && !isClickable(el, anchor)) return;
    var href = anchor ? (anchor.getAttribute('href') || anchor.getAttributeNS('http://www.w3.org/1999/xlink', 'href') || '') : '';
    if (anchor && linksInAL) e.preventDefault();
    var classes = classesOf(el);
    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('ElementClicked', [
      kindOf(classes),
      el.getAttribute('data-id') || '',
      el.getAttribute('data-callback') || '',
      el.getAttribute('data-args') || '',
      href,
      classes
    ]);
  }

  // ---------------------------------------------------------------- content

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
    // Links in a diagram open outside the Business Central frame, unless AL handles them.
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

  return {
    init: init,
    showSvg: showSvg,
    showError: showError,
    showPlaceholder: showPlaceholder,
    setClickMode: setClickMode,
    setLinkHandling: setLinkHandling
  };
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

function SetClickMode(mode) {
  MermaidViewer.setClickMode(mode);
}

function SetLinkHandling(handleInAL) {
  MermaidViewer.setLinkHandling(handleInAL);
}
