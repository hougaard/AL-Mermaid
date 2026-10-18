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
}
