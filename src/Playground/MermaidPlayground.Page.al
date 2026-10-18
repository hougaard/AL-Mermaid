/// <summary>
/// A page to type or paste Mermaid text and see the SVG that codeunit "Mermaid SVG" renders for it.
/// </summary>
page 68900 "Mermaid Playground"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Tasks;
    Caption = 'Mermaid Playground';
    InsertAllowed = false;
    DeleteAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            group(SourceGroup)
            {
                Caption = 'Mermaid';

                field(MermaidSourceField; MermaidSource)
                {
                    ApplicationArea = All;
                    Caption = 'Mermaid source';
                    ShowCaption = false;
                    MultiLine = true;
                    ToolTip = 'Specifies the Mermaid text to render. Type or paste a flowchart, sequence diagram or pie chart, then leave the field or choose Render.';

                    trigger OnValidate()
                    begin
                        RenderDiagram();
                    end;
                }
                field(DiagramTypeField; DiagramType)
                {
                    ApplicationArea = All;
                    Caption = 'Diagram type';
                    Editable = false;
                    ToolTip = 'Specifies the diagram type detected in the Mermaid text.';
                }
                field(StatusField; StatusText)
                {
                    ApplicationArea = All;
                    Caption = 'Status';
                    Editable = false;
                    StyleExpr = StatusStyle;
                    MultiLine = true;
                    ToolTip = 'Specifies whether the text rendered, or the error that stopped it.';
                }
            }
            group(PreviewGroup)
            {
                Caption = 'Preview';

                usercontrol(Viewer; "Mermaid SVG Viewer")
                {
                    ApplicationArea = All;

                    trigger ControlReady()
                    begin
                        ViewerReady := true;
                        RenderDiagram();
                    end;
                }
            }
            group(SvgGroup)
            {
                Caption = 'SVG source';
                Visible = ShowSvgSource;

                field(SvgField; SvgText)
                {
                    ApplicationArea = All;
                    Caption = 'SVG';
                    ShowCaption = false;
                    MultiLine = true;
                    Editable = false;
                    ToolTip = 'Specifies the SVG document that was rendered.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RenderAction)
            {
                ApplicationArea = All;
                Caption = 'Render';
                Image = Refresh;
                ToolTip = 'Render the Mermaid text to SVG.';

                trigger OnAction()
                begin
                    RenderDiagram();
                end;
            }
            action(DownloadSvgAction)
            {
                ApplicationArea = All;
                Caption = 'Download SVG';
                Image = Export;
                ToolTip = 'Download the rendered SVG as a file.';

                trigger OnAction()
                begin
                    DownloadSvg();
                end;
            }
            action(ToggleSvgAction)
            {
                ApplicationArea = All;
                Caption = 'Show/Hide SVG Source';
                Image = ShowList;
                ToolTip = 'Show or hide the SVG markup under the preview.';

                trigger OnAction()
                begin
                    ShowSvgSource := not ShowSvgSource;
                    CurrPage.Update(false);
                end;
            }
            action(ClearAction)
            {
                ApplicationArea = All;
                Caption = 'Clear';
                Image = ClearLog;
                ToolTip = 'Clear the Mermaid text.';

                trigger OnAction()
                begin
                    SetSource('');
                end;
            }
            group(SamplesGroup)
            {
                Caption = 'Samples';
                Image = Template;

                action(SampleFlowchartAction)
                {
                    ApplicationArea = All;
                    Caption = 'Flowchart';
                    Image = Workflow;
                    ToolTip = 'Load a sample flowchart.';

                    trigger OnAction()
                    begin
                        SetSource(SampleFlowchart());
                    end;
                }
                action(SampleSubgraphAction)
                {
                    ApplicationArea = All;
                    Caption = 'Flowchart with Subgraphs';
                    Image = Hierarchy;
                    ToolTip = 'Load a sample flowchart with subgraphs, shapes and styles.';

                    trigger OnAction()
                    begin
                        SetSource(SampleSubgraphs());
                    end;
                }
                action(SampleSequenceAction)
                {
                    ApplicationArea = All;
                    Caption = 'Sequence Diagram';
                    Image = Timeline;
                    ToolTip = 'Load a sample sequence diagram.';

                    trigger OnAction()
                    begin
                        SetSource(SampleSequence());
                    end;
                }
                action(SamplePieAction)
                {
                    ApplicationArea = All;
                    Caption = 'Pie Chart';
                    Image = AnalysisView;
                    ToolTip = 'Load a sample pie chart.';

                    trigger OnAction()
                    begin
                        SetSource(SamplePie());
                    end;
                }
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(RenderPromoted; RenderAction)
                {
                }
                actionref(DownloadSvgPromoted; DownloadSvgAction)
                {
                }
                actionref(ToggleSvgPromoted; ToggleSvgAction)
                {
                }
            }
            group(Category_Samples)
            {
                Caption = 'Samples';

                actionref(SampleFlowchartPromoted; SampleFlowchartAction)
                {
                }
                actionref(SampleSubgraphPromoted; SampleSubgraphAction)
                {
                }
                actionref(SampleSequencePromoted; SampleSequenceAction)
                {
                }
                actionref(SamplePiePromoted; SamplePieAction)
                {
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if MermaidSource = '' then
            MermaidSource := SampleFlowchart();
    end;

    var
        MermaidSvg: Codeunit "Mermaid SVG";
        MermaidSource: Text;
        SvgText: Text;
        DiagramType: Text;
        StatusText: Text;
        StatusStyle: Text;
        ViewerReady: Boolean;
        ShowSvgSource: Boolean;
        EmptyMsg: Label 'Type or paste Mermaid text above.';
        RenderedMsg: Label 'Rendered %1 characters of SVG.', Comment = '%1 = the length of the SVG';
        NothingToDownloadErr: Label 'There is no SVG to download. Render a diagram first.';
        DownloadTitleTxt: Label 'Download SVG';
        FileFilterTxt: Label 'SVG files (*.svg)|*.svg', Locked = true;
        FileNameTxt: Label 'diagram.svg', Locked = true;

    local procedure SetSource(NewSource: Text)
    begin
        MermaidSource := NewSource;
        RenderDiagram();
        CurrPage.Update(false);
    end;

    local procedure RenderDiagram()
    var
        ErrorMessage: Text;
        StartTime: DateTime;
    begin
        DiagramType := MermaidSvg.DetectType(MermaidSource);
        if DelChr(MermaidSource, '=', ' ') = '' then begin
            SvgText := '';
            StatusText := EmptyMsg;
            StatusStyle := 'Subordinate';
            if ViewerReady then
                CurrPage.Viewer.ShowPlaceholder(EmptyMsg);
            exit;
        end;
        StartTime := CurrentDateTime();
        if MermaidSvg.TryRender(MermaidSource, SvgText, ErrorMessage) then begin
            StatusText := StrSubstNo(RenderedMsg, StrLen(SvgText)) + ' (' + Format(CurrentDateTime() - StartTime) + ')';
            StatusStyle := 'Favorable';
            if ViewerReady then
                CurrPage.Viewer.ShowSvg(SvgText);
        end else begin
            StatusText := ErrorMessage;
            StatusStyle := 'Unfavorable';
            if ViewerReady then
                CurrPage.Viewer.ShowError(ErrorMessage);
        end;
    end;

    local procedure DownloadSvg()
    var
        TempBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        InStr: InStream;
        FileName: Text;
    begin
        if SvgText = '' then
            RenderDiagram();
        if SvgText = '' then
            Error(NothingToDownloadErr);
        TempBlob.CreateOutStream(OutStr, TextEncoding::UTF8);
        OutStr.WriteText(SvgText);
        TempBlob.CreateInStream(InStr, TextEncoding::UTF8);
        FileName := FileNameTxt;
        DownloadFromStream(InStr, DownloadTitleTxt, '', FileFilterTxt, FileName);
    end;

    local procedure Lines(Parts: List of [Text]): Text
    var
        Builder: TextBuilder;
        Part: Text;
        Lf: Text[1];
    begin
        Lf[1] := 10;
        foreach Part in Parts do begin
            Builder.Append(Part);
            Builder.Append(Lf);
        end;
        exit(Builder.ToText());
    end;

    local procedure SampleFlowchart(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('flowchart TD');
        Parts.Add('    A[Christmas] -->|Get money| B(Go shopping)');
        Parts.Add('    B --> C{Let me think}');
        Parts.Add('    C -->|One| D[Laptop]');
        Parts.Add('    C -->|Two| E[iPhone]');
        Parts.Add('    C -->|Three| F[Car]');
        exit(Lines(Parts));
    end;

    local procedure SampleSubgraphs(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('---');
        Parts.Add('title: Order to cash');
        Parts.Add('---');
        Parts.Add('flowchart LR');
        Parts.Add('    start([Customer order]) --> check{In stock?}');
        Parts.Add('    check -- yes --> pick');
        Parts.Add('    check -. no .-> po[[Create purchase order]]');
        Parts.Add('    po ==> receive[(Warehouse)]');
        Parts.Add('    receive --> pick');
        Parts.Add('    subgraph wh [Warehouse]');
        Parts.Add('        direction TB');
        Parts.Add('        pick[/Pick items/] --> ship>Ship]');
        Parts.Add('    end');
        Parts.Add('    ship --> invoice{{Post invoice}}');
        Parts.Add('    invoice --> paid((Paid))');
        Parts.Add('    classDef done fill:#d4f4dd,stroke:#2e7d32');
        Parts.Add('    class paid done');
        Parts.Add('    style start stroke-width:2px');
        exit(Lines(Parts));
    end;

    local procedure SampleSequence(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('sequenceDiagram');
        Parts.Add('    autonumber');
        Parts.Add('    actor User');
        Parts.Add('    participant BC as Business Central');
        Parts.Add('    participant API as Web Service');
        Parts.Add('    User->>+BC: Post sales order');
        Parts.Add('    BC->>API: Request shipping label');
        Parts.Add('    alt label available');
        Parts.Add('        API-->>BC: Label PDF');
        Parts.Add('    else service down');
        Parts.Add('        API--xBC: Timeout');
        Parts.Add('        Note over BC,API: Retry in 5 minutes');
        Parts.Add('    end');
        Parts.Add('    loop Every order line');
        Parts.Add('        BC->>BC: Update inventory');
        Parts.Add('    end');
        Parts.Add('    BC-->>-User: Shipment posted');
        exit(Lines(Parts));
    end;

    local procedure SamplePie(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('pie showData');
        Parts.Add('    title Sales by region');
        Parts.Add('    "North" : 42.5');
        Parts.Add('    "South" : 27');
        Parts.Add('    "East" : 18');
        Parts.Add('    "West" : 12.5');
        exit(Lines(Parts));
    end;
}
