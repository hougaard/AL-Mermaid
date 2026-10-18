/// <summary>
/// Renders Mermaid diagram text to SVG, in AL. A port of pele (https://github.com/obsidianmd/pele),
/// which renders Mermaid to SVG with no runtime dependencies and themes through CSS variables.
///
/// Supported diagram types: flowchart (graph / flowchart), sequenceDiagram, pie, classDiagram,
/// stateDiagram, erDiagram, gantt, gitGraph, mindmap, journey and timeline. Other types are detected
/// and reported as not supported yet.
///
/// Usage:
///   Svg := MermaidSvg.Render('flowchart LR' + LF + 'A[Start] --> B[End]');
/// or, without raising an error:
///   if MermaidSvg.TryRender(Source, Svg, ErrorMessage) then ...
///
/// The SVG sizes itself to its container (max-width:100%) unless SetResponsive(false) is called, and
/// takes its colours and fonts from --pele-* CSS variables, with fallbacks for a light theme.
/// </summary>
codeunit 68900 "Mermaid SVG"
{
    Access = Public;

    var
        MText: Codeunit "Mermaid Text";
        OptIdPrefix: Text;
        OptFontFamily: Text;
        OptFontSize: Decimal;
        OptResponsive: Boolean;
        ResponsiveSet: Boolean;
        SourceLimit: Integer;
        OutputLimit: Integer;
        EdgeLimit: Integer;
        LimitsSet: Boolean;
        LastCallStack: Text;
        NotSupportedErr: Label 'Diagram type "%1" is not supported yet. Supported types: %2.', Comment = '%1 = the detected diagram type, %2 = the supported types';
        NoTypeErr: Label 'No diagram type detected for the given text.';
        SourceLimitErr: Label 'Diagram source is longer than the limit of %1 characters.', Comment = '%1 = the limit';
        OutputLimitErr: Label 'Diagram output is longer than the limit of %1 characters.', Comment = '%1 = the limit';

    // ---------------------------------------------------------------- options

    /// <summary>The prefix of the ids written into the SVG (default "pele"). Use distinct prefixes for several diagrams on one page.</summary>
    procedure SetIdPrefix(NewIdPrefix: Text)
    begin
        OptIdPrefix := NewIdPrefix;
    end;

    /// <summary>The font size labels are measured and drawn in, in pixels (default 16).</summary>
    procedure SetFontSize(NewFontSize: Decimal)
    begin
        OptFontSize := NewFontSize;
    end;

    /// <summary>The font family drawn where the page sets no --pele-font (default sans-serif).</summary>
    procedure SetFontFamily(NewFontFamily: Text)
    begin
        OptFontFamily := NewFontFamily;
    end;

    /// <summary>Whether the SVG shrinks to fit its container. On by default, unless the diagram's config sets useMaxWidth to false.</summary>
    procedure SetResponsive(NewResponsive: Boolean)
    begin
        OptResponsive := NewResponsive;
        ResponsiveSet := true;
    end;

    /// <summary>The longest source, the longest output, and the most flowchart edges that are rendered.</summary>
    procedure SetLimits(NewSourceLimit: Integer; NewOutputLimit: Integer; NewEdgeLimit: Integer)
    begin
        SourceLimit := NewSourceLimit;
        OutputLimit := NewOutputLimit;
        EdgeLimit := NewEdgeLimit;
        LimitsSet := true;
    end;

    local procedure ApplyDefaults()
    begin
        if not LimitsSet then begin
            // Mermaid's default maxTextSize, pele's output limit and edge limit.
            SourceLimit := 50000;
            OutputLimit := 4000000;
            EdgeLimit := 5000;
        end;
    end;

    // ---------------------------------------------------------------- rendering

    /// <summary>Renders Mermaid text to an SVG document. Raises an error for text that cannot be drawn.</summary>
    procedure Render(Source: Text): Text
    var
        Svg: Text;
    begin
        RenderInternal(Source, Svg);
        exit(Svg);
    end;

    /// <summary>Renders Mermaid text to an SVG document, returning false and the error message for text that cannot be drawn.</summary>
    procedure TryRender(Source: Text; var Svg: Text; var ErrorMessage: Text): Boolean
    begin
        Svg := '';
        ErrorMessage := '';
        ClearLastError();
        LastCallStack := '';
        if TryRenderInternal(Source, Svg) then
            exit(true);
        ErrorMessage := GetLastErrorText();
        LastCallStack := GetLastErrorCallStack();
        Svg := '';
        exit(false);
    end;

    /// <summary>The AL call stack of the error that made the last TryRender return false, for diagnosing a failure.</summary>
    procedure GetLastCallStack(): Text
    begin
        exit(LastCallStack);
    end;

    [TryFunction]
    local procedure TryRenderInternal(Source: Text; var Svg: Text)
    begin
        RenderInternal(Source, Svg);
    end;

    local procedure RenderInternal(Source: Text; var Svg: Text)
    var
        Preprocessor: Codeunit "Mermaid Preprocessor";
        FlowParser: Codeunit "Mermaid Flowchart Parser";
        FlowRenderer: Codeunit "Mermaid Flowchart Renderer";
        Sequence: Codeunit "Mermaid Sequence Diagram";
        Pie: Codeunit "Mermaid Pie Chart";
        ClassDiagram: Codeunit "Mermaid Class Diagram";
        StateDiagram: Codeunit "Mermaid State Diagram";
        ERDiagram: Codeunit "Mermaid ER Diagram";
        GanttChart: Codeunit "Mermaid Gantt Chart";
        GitGraph: Codeunit "Mermaid Git Graph";
        Mindmap: Codeunit "Mermaid Mindmap";
        JourneyTimeline: Codeunit "Mermaid Journey Timeline";
        Config: Dictionary of [Text, Text];
        Body: Text;
        Title: Text;
        DiagramType: Text;
        Encoded: Text;
        Responsive: Boolean;
    begin
        ApplyDefaults();
        if StrLen(Source) > SourceLimit then
            Error(SourceLimitErr, SourceLimit);
        Preprocessor.Preprocess(Source, Body, Title, Config);
        DiagramType := Preprocessor.Detect(Body);
        if DiagramType = '' then
            Error(NoTypeErr);

        Responsive := not (MText.ConfigText(Config, ConfigSection(DiagramType) + '.useMaxWidth', '') = 'false');
        if ResponsiveSet then
            Responsive := OptResponsive;
        MText.SetOptions(OptIdPrefix, OptFontFamily, OptFontSize, Responsive);

        Encoded := Preprocessor.EncodeEntities(Body) + MText.LF();
        case DiagramType of
            'flowchart':
                begin
                    FlowParser.Parse(Encoded, Title, EdgeLimit, MText.ConfigBool(Config, 'flowchart.inheritDir', false));
                    Svg := FlowRenderer.Render(FlowParser, Config);
                end;
            'sequence':
                begin
                    Sequence.Parse(Encoded, Title, Config);
                    Svg := Sequence.Render(Config);
                end;
            'pie':
                begin
                    Pie.Parse(Encoded, Title);
                    Svg := Pie.Render(Config);
                end;
            'class':
                begin
                    ClassDiagram.Parse(Encoded, Title, Config);
                    Svg := ClassDiagram.Render(Config);
                end;
            'state':
                begin
                    StateDiagram.Parse(Encoded, Title, Config);
                    Svg := StateDiagram.Render(Config);
                end;
            'er':
                begin
                    ERDiagram.Parse(Encoded, Title, Config);
                    Svg := ERDiagram.Render(Config);
                end;
            'gantt':
                begin
                    GanttChart.Parse(Encoded, Title, Config);
                    Svg := GanttChart.Render(Config);
                end;
            'gitGraph':
                begin
                    GitGraph.Parse(Encoded, Title, Config);
                    Svg := GitGraph.Render(Config);
                end;
            'mindmap':
                begin
                    Mindmap.Parse(Encoded, Title, Config);
                    Svg := Mindmap.Render(Config);
                end;
            'journey':
                begin
                    JourneyTimeline.ParseJourney(Encoded, Title, Config);
                    Svg := JourneyTimeline.RenderJourney(Config);
                end;
            'timeline':
                begin
                    JourneyTimeline.ParseTimeline(Encoded, Title, Config);
                    Svg := JourneyTimeline.RenderTimeline(Config);
                end;
            else
                Error(NotSupportedErr, DiagramType, SupportedTypes());
        end;
        if StrLen(Svg) > OutputLimit then
            Error(OutputLimitErr, OutputLimit);
    end;

    local procedure ConfigSection(DiagramType: Text): Text
    begin
        exit(DiagramType);
    end;

    // ---------------------------------------------------------------- detection

    /// <summary>The diagram type Mermaid would detect for the text, such as flowchart, sequence or pie, or an empty text.</summary>
    procedure DetectType(Source: Text): Text
    var
        Preprocessor: Codeunit "Mermaid Preprocessor";
        Config: Dictionary of [Text, Text];
        Body: Text;
        Title: Text;
    begin
        if not TryPreprocess(Source, Body, Title, Config) then
            exit('');
        exit(Preprocessor.Detect(Body));
    end;

    [TryFunction]
    local procedure TryPreprocess(Source: Text; var Body: Text; var Title: Text; var Config: Dictionary of [Text, Text])
    var
        Preprocessor: Codeunit "Mermaid Preprocessor";
    begin
        Preprocessor.Preprocess(Source, Body, Title, Config);
    end;

    /// <summary>Whether the text is of a diagram type this port renders.</summary>
    procedure IsSupported(Source: Text): Boolean
    var
        DiagramType: Text;
    begin
        DiagramType := DetectType(Source);
        if DiagramType = '' then
            exit(false);
        exit(SupportedTypes().Split(',').Contains(DiagramType));
    end;

    /// <summary>The diagram types this port renders, comma separated, as DetectType names them.</summary>
    procedure SupportedTypes(): Text
    begin
        exit('flowchart,sequence,pie,class,state,er,gantt,gitGraph,mindmap,journey,timeline');
    end;
}
