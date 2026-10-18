/// <summary>
/// Shows an SVG document produced by codeunit "Mermaid SVG". The SVG is parsed as XML and cleaned of
/// scripts and event handlers before it is put on the page. A small toolbar zooms the drawing and
/// switches between a light and a dark theme through pele's --pele-* CSS variables.
/// </summary>
controladdin "Mermaid SVG Viewer"
{
    Scripts = 'src/ControlAddIn/js/viewer.js';
    StartupScript = 'src/ControlAddIn/js/startup.js';
    StyleSheets = 'src/ControlAddIn/css/viewer.css';
    RequestedHeight = 540;
    MinimumHeight = 540;
    VerticalStretch = true;
    VerticalShrink = true;
    HorizontalStretch = true;
    HorizontalShrink = true;

    /// <summary>Raised once the viewer is loaded and can take an SVG.</summary>
    event ControlReady();

    /// <summary>Shows an SVG document.</summary>
    procedure ShowSvg(Svg: Text);

    /// <summary>Shows an error message in place of the drawing.</summary>
    procedure ShowError(Message: Text);

    /// <summary>Shows a hint when there is nothing to draw.</summary>
    procedure ShowPlaceholder(Message: Text);

    /// <summary>
    /// Raised when the user clicks an element of the diagram that has an id.
    /// Kind is what was clicked, such as node, edge, cluster, actor, message, class, state, entity, task, slice,
    /// commit or period. Id is the element's id: for a flowchart node, the node id written in the Mermaid text.
    /// Callback and Arguments come from a Mermaid click statement (click A call openCustomer("10000")) and are
    /// empty otherwise. Href is the link target when the element is a link (click A href "..."). Classes is the
    /// element's class attribute, including classes the diagram assigned with ::: or class statements.
    /// </summary>
    event ElementClicked(Kind: Text; Id: Text; Callback: Text; Arguments: Text; Href: Text; Classes: Text);

    /// <summary>
    /// Which elements raise ElementClicked: 'all' (every element with an id, the default), 'clickable' (only
    /// elements the diagram makes clickable with a click statement), or 'none'.
    /// </summary>
    procedure SetClickMode(Mode: Text);

    /// <summary>
    /// When true, clicking a link in the diagram only raises ElementClicked, with the target in Href, and AL decides
    /// what happens. When false (the default), the link also opens in a new browser tab.
    /// </summary>
    procedure SetLinkHandling(HandleInAL: Boolean);
}
