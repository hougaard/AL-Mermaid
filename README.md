# Mermaid to SVG for Business Central

Render [Mermaid](https://mermaid.js.org) diagrams to SVG in AL, on the Business Central server, with no JavaScript, no web service and no external dependency.

This extension is an AL port of [pele](https://github.com/obsidianmd/pele), a small Mermaid-to-SVG renderer. You pass Mermaid text in and get a complete SVG document back as `Text`. You can show the SVG on a page, store it, attach it to a record or send it in an email.

```al
var
    MermaidSvg: Codeunit "Mermaid SVG";
    Svg: Text;
begin
    Svg := MermaidSvg.Render('flowchart LR' + LF + 'A[Order] --> B[Invoice]');
end;
```

## Supported diagram types

| Diagram | First line of the Mermaid text | `DetectType` returns |
|---|---|---|
| Flowchart | `flowchart TD` or `graph LR` | `flowchart` |
| Sequence diagram | `sequenceDiagram` | `sequence` |
| Class diagram | `classDiagram` | `class` |
| State diagram | `stateDiagram-v2` or `stateDiagram` | `state` |
| Entity relationship diagram | `erDiagram` | `er` |
| Gantt chart | `gantt` | `gantt` |
| Pie chart | `pie` | `pie` |
| Git graph | `gitGraph` | `gitGraph` |
| Mindmap | `mindmap` | `mindmap` |
| User journey | `journey` | `journey` |
| Timeline | `timeline` | `timeline` |

Other Mermaid types, such as C4, quadrant charts or sankey diagrams, are recognised but not rendered. `Render` raises a "not supported yet" error for them, and `TryRender` returns `false`.

## Requirements

- Business Central 2026 release wave 1 (application 28) or later, runtime 17.
- No dependencies beyond the base application. The extension uses the System Application's `Temp Blob` and `Math` codeunits.

## Installation

1. Open the `Extension` folder in Visual Studio Code with the AL Language extension.
2. Download symbols for your environment (**AL: Download Symbols**).
3. Set your server in `.vscode/launch.json`. This file is ignored by Git, so each developer keeps their own.
4. Publish with **F5**, or **Ctrl+F5** to publish without debugging.

The object IDs are in the range 68900–68919. Change `idRanges` in `app.json` and renumber the objects if that range clashes with your other extensions.

## Try it in the Mermaid Playground

Search for **Mermaid Playground** in Business Central.

1. Pick a diagram in **Load sample**, or choose **Next Sample** to step through one sample of every supported type.
2. Edit the text, or paste your own Mermaid. The diagram renders when you leave the field, or when you choose **Render**.
3. Use the viewer toolbar to zoom, show the diagram at actual size, or switch to the dark theme.
4. Click an element of the diagram. **Last click** in the **Clicks** group shows what the click event reported.
5. Choose **Download SVG** to save the diagram, or **Show/Hide SVG Source** to see the markup.

If the text cannot be drawn, **Status** shows the error, which for syntax errors includes the line and a pointer to the column. The AL call stack follows the error, so a bug in the renderer can be traced to its line.

## Using it from your own AL code

To use the renderer from another extension, add a dependency on this one in your `app.json`:

```json
"dependencies": [
  {
    "id": "2fbc2282-a770-42df-a781-81c35ba930ae",
    "name": "AL-Mermaid",
    "publisher": "Hougaard",
    "version": "1.0.0.0"
  }
]
```

Then call the public codeunit `"Mermaid SVG"` (68900). Every other object is internal.

### Render, raising an error on failure

```al
procedure ShowOrderFlow()
var
    MermaidSvg: Codeunit "Mermaid SVG";
    Source: TextBuilder;
    Svg: Text;
begin
    Source.AppendLine('flowchart LR');
    Source.AppendLine('    Order[Sales order] --> Ship[Shipment] --> Invoice[Invoice]');
    Svg := MermaidSvg.Render(Source.ToText());
end;
```

Mermaid is line based, so separate statements with line feeds. `TextBuilder.AppendLine` adds a carriage return and a line feed, which the renderer accepts.

### Render without raising an error

```al
if MermaidSvg.TryRender(Source, Svg, ErrorMessage) then
    // use Svg
else
    Message(ErrorMessage);
```

After a failed `TryRender`, `GetLastCallStack()` returns the AL call stack of the error.

### Check the text before rendering

```al
DiagramType := MermaidSvg.DetectType(Source);   // 'flowchart', 'gantt', ... or '' if none
if MermaidSvg.IsSupported(Source) then ...
Types := MermaidSvg.SupportedTypes();            // comma-separated list of DetectType names
```

### Options

Set options on the codeunit variable before calling `Render` or `TryRender`.

| Procedure | Default | Effect |
|---|---|---|
| `SetFontSize(Size)` | 16 | Font size in pixels that labels are measured and drawn in. |
| `SetFontFamily(Family)` | `sans-serif` | Font used where the page sets no `--pele-font`. |
| `SetResponsive(Responsive)` | `true` | When true, the SVG shrinks to fit its container (`max-width:100%`). When false, it keeps its natural size. A diagram can also turn this off with `useMaxWidth: false` in its config. |
| `SetIdPrefix(Prefix)` | `pele` | Prefix of the ids inside the SVG. Use a distinct prefix for each diagram when several share one page. |
| `SetLimits(Source, Output, Edges)` | 50000, 4000000, 5000 | Longest source text, longest SVG output, and most flowchart edges that are rendered. |

## Showing the SVG on a page

The extension includes the control add-in **"Mermaid SVG Viewer"**, which the playground uses. Add it to your own page:

```al
usercontrol(Diagram; "Mermaid SVG Viewer")
{
    ApplicationArea = All;

    trigger ControlReady()
    begin
        CurrPage.Diagram.ShowSvg(MermaidSvg.Render(Rec."Diagram Source"));
    end;
}
```

The viewer has three display procedures, plus the click settings described in the next section:
- **`ShowSvg(Svg)`** draws a diagram. The viewer reads the SVG as XML and removes scripts, foreign content and event handler attributes before showing it.
- **`ShowError(Message)`** shows an error message in place of the drawing.
- **`ShowPlaceholder(Message)`** shows a hint when there is nothing to draw.

Wait for the `ControlReady` event before calling any of them.

## Interactive diagrams: handling clicks in AL

The viewer raises an AL event when the user clicks an element of the diagram:

```al
trigger ElementClicked(Kind: Text; Id: Text; Callback: Text; Arguments: Text; Href: Text; Classes: Text)
```

| Parameter | Contents |
|---|---|
| `Kind` | What was clicked: `node`, `edge`, `edge-label`, `cluster`, `actor`, `message`, `note`, `class`, `state`, `entity`, `task`, `milestone`, `slice`, `commit`, `branch`, `period` and so on. |
| `Id` | The element's id. For a flowchart node it is the node id from the Mermaid text, so `C10000[Adatum]` reports `C10000`. |
| `Callback`, `Arguments` | The callback from a Mermaid click statement, such as `click C10000 call openCustomer("10000")`. Both are empty when there is none. |
| `Href` | The link target, when the element is a link (`click A href "..."`). |
| `Classes` | The element's classes, including those the diagram assigned with `:::` or `class` statements. |

Callbacks are never run as script. The viewer only reads the name and the argument text and passes them to AL, so diagram text can't run code in the browser.

Two viewer procedures control the behaviour:

- **`SetClickMode(Mode)`:** `'all'` (the default) raises the event for every element with an id. `'clickable'` raises it only for elements that a `click` statement makes clickable. `'none'` turns clicks off.
- **`SetLinkHandling(HandleInAL)`:** when true, clicking a link only raises the event, and AL decides what to do. When false (the default), the link also opens in a new browser tab.

Clickable elements get a pointer cursor and a soft highlight in the accent colour on hover.

### Example: open records from a generated diagram

Generate the Mermaid text from your data with record keys as node ids, then open the record that was clicked:

```al
usercontrol(Diagram; "Mermaid SVG Viewer")
{
    ApplicationArea = All;

    trigger ControlReady()
    begin
        CurrPage.Diagram.SetClickMode('clickable');
        CurrPage.Diagram.ShowSvg(MermaidSvg.Render(BuildCustomerDiagram()));
    end;

    trigger ElementClicked(Kind: Text; Id: Text; Callback: Text; Arguments: Text; Href: Text; Classes: Text)
    var
        Customer: Record Customer;
    begin
        case Callback of
            'openCustomer':
                if Customer.Get(DelChr(Arguments, '<>', '"')) then
                    Page.Run(Page::"Customer Card", Customer);
        end;
    end;
}
```

Click statements with callbacks are kept for flowcharts, class diagrams and gantt charts. For the other types, use `SetClickMode('all')` and act on `Kind` and `Id`.

### Try it in the playground

The **Clicks** group on the Mermaid Playground has **Click events** (all elements, clickable elements only, or off) and **Handle links in AL**. **Last click** shows what each click reported. The flowchart-with-subgraphs, class and gantt samples include click statements.

For example, load **Flowchart with subgraphs** and click the **Paid** node. **Last click** shows `node "paid"` and `Callback: openInvoice("103001")`. Clicking **Customer order** reports its link to the Business Central documentation.

Other ways to use the SVG:
- **Image:** save it in a `Blob` or `Media` field, or embed it as a data URI: `data:image/svg+xml;utf8,` followed by the URL-encoded SVG.
- **Email or report:** an SVG works in HTML email bodies and in reports that accept images. Some email clients don't display SVG.

## Diagram configuration

Diagrams accept Mermaid's own configuration, in YAML front matter or in an `init` directive:

```text
---
title: Order to cash
config:
  flowchart:
    curve: linear
    nodeSpacing: 60
---
flowchart LR
    A --> B
```

```text
%%{init: {"gantt": {"barHeight": 24}}}%%
gantt
    ...
```

The front-matter `title` is drawn above the diagram for every type.

## Theming

The SVG takes its colours and fonts from CSS variables, with fallbacks for a light theme. Set them on any element that contains the SVG:

```css
.my-diagram {
  --pele-bg: #fffcf0;
  --pele-fg: #100f0f;
  --pele-muted: #6f6e69;
  --pele-line: #100f0f;
  --pele-surface: #f2f0e5;
  --pele-surface-alt: #e6e4d9;
  --pele-border: #cecdc3;
  --pele-accent: #205ea6;
  --pele-font: sans-serif;
  --pele-radius: 4px;
}
```

Charts use `--pele-series-1` to `--pele-series-8`. The viewer's **Theme** button switches these variables to a dark palette, and you can edit that palette in `src/ControlAddIn/css/viewer.css`. Author styles inside diagrams, such as `classDef` and `style`, still apply on top of the theme.

## Limitations

- **No icons or images:** `fa:` icons, `icon:` and `img:` shapes are not drawn.
- **No narrowing to fit:** pele can redraw a diagram narrower, for example turning a left-to-right flowchart top to bottom, when the container is small. This port always draws the normal layout and lets `max-width:100%` scale it down.
- **Simpler edge routing:** flowchart, class, state and ER edges are routed as plain curves rather than pele's tracks and levels.
- **Click callbacks:** callbacks are never run as JavaScript. They are passed to AL through the viewer's `ElementClicked` event instead, for flowcharts, class diagrams and gantt charts.
- **Approximate text widths:** labels are measured with a built-in Arial width table, as pele does on a server, so a very different font can make labels fit slightly loosely or tightly.
- **Gantt dates:** dates that don't match `dateFormat` are parsed only approximately, as a browser's lenient date parser would.

## Tests

Codeunit **"Mermaid SVG Tests"** (68911) has 32 tests covering every supported type, click callbacks, syntax errors and escaping. Run them from the AL Test Tool. They need no test libraries. Several tests compare exact output from pele, so a failure there points to a difference between this port and pele.

## Project structure

| Folder | Contents |
|---|---|
| `src/Core` | The public `"Mermaid SVG"` codeunit, preprocessing, text measuring, labels, SVG building and the compound layout shared by graph diagrams |
| `src/Flowchart` | Flowchart parser and renderer, node shapes and the layered layout engine |
| `src/Sequence`, `src/Class`, `src/State`, `src/ER`, `src/Gantt`, `src/Pie`, `src/Git`, `src/Mindmap`, `src/Journey` | One folder per diagram type. The journey folder holds both user journey and timeline. |
| `src/Playground` | The Mermaid Playground page and its sample list |
| `src/ControlAddIn` | The SVG viewer control add-in |
| `src/Test` | The test codeunit |

## Credits and license

This extension is a port of [pele](https://github.com/obsidianmd/pele) by kepano, released under the MIT License:

> MIT License
>
> Copyright (c) 2026 kepano
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Mermaid is a project of the Mermaid community and is also MIT licensed.
