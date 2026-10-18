/// <summary>
/// Tests for codeunit "Mermaid SVG". They need no test libraries; run them from the AL Test Tool.
/// </summary>
codeunit 68911 "Mermaid SVG Tests"
{
    Subtype = Test;
    Access = Internal;

    var
        MermaidSvg: Codeunit "Mermaid SVG";

    local procedure Lf(): Text
    var
        Value: Text[1];
    begin
        Value[1] := 10;
        exit(Value);
    end;

    local procedure AssertContains(Haystack: Text; Needle: Text)
    begin
        if StrPos(Haystack, Needle) = 0 then
            Error('Expected the output to contain "%1".', Needle);
    end;

    local procedure AssertNotContains(Haystack: Text; Needle: Text)
    begin
        if StrPos(Haystack, Needle) > 0 then
            Error('Expected the output not to contain "%1".', Needle);
    end;

    local procedure AssertEqual(Expected: Text; Actual: Text)
    begin
        if Expected <> Actual then
            Error('Expected "%1" but got "%2".', Expected, Actual);
    end;

    [Test]
    procedure FlowchartRendersNodesEdgesAndLabels()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('flowchart LR' + Lf() + 'A[Start] --> B{Ok?}' + Lf() + 'B -->|Yes| C(Done)' + Lf() + 'B -- No --> A' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-flowchart"');
        AssertContains(Svg, '>Start</text>');
        AssertContains(Svg, '>Ok?</text>');
        AssertContains(Svg, '>Yes</text>');
        AssertContains(Svg, '>No</text>');
        AssertContains(Svg, 'pele-shape-diam');
        AssertContains(Svg, 'pele-shape-rounded');
        AssertContains(Svg, 'class="pele-marker"');
        AssertContains(Svg, '</svg>');
    end;

    [Test]
    procedure FlowchartRendersSubgraphsAndClasses()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('graph TD' + Lf() + 'subgraph one [First group]' + Lf() + 'a1 --> a2' + Lf() + 'end' + Lf() +
                                 'a2 --> b1' + Lf() + 'classDef hot fill:#f96' + Lf() + 'class b1 hot' + Lf());
        AssertContains(Svg, 'class="pele-cluster" data-id="one"');
        AssertContains(Svg, '>First group</text>');
        AssertContains(Svg, 'class="pele-node pele-shape-rect hot" data-id="b1"');
        AssertContains(Svg, 'fill:#f96');
    end;

    [Test]
    procedure FlowchartEscapesLabels()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('flowchart TB' + Lf() + 'A["<script>alert(1)</script> & co"]' + Lf());
        AssertNotContains(Svg, '<script>');
        AssertContains(Svg, '&amp; co');
    end;

    [Test]
    procedure SequenceRendersParticipantsAndMessages()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('sequenceDiagram' + Lf() + 'participant A as Alice' + Lf() + 'A->>+Bob: Hello Bob' + Lf() +
                                 'Bob-->>-A: Hi Alice' + Lf() + 'Note over A,Bob: A note' + Lf() + 'loop Daily' + Lf() + 'A->>A: Think' + Lf() + 'end' + Lf());
        AssertContains(Svg, 'class="pele pele-sequence"');
        AssertContains(Svg, '>Alice</text>');
        AssertContains(Svg, '>Hello Bob</text>');
        AssertContains(Svg, '>A note</text>');
        AssertContains(Svg, 'pele-frame-loop');
        AssertContains(Svg, 'pele-activation');
        AssertContains(Svg, 'stroke-dasharray="4 4"');
    end;

    [Test]
    procedure PieRendersSlicesAndPercentages()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('pie title Pets' + Lf() + '"Dogs" : 386' + Lf() + '"Cats" : 85' + Lf() + '"Rats" : 15' + Lf());
        AssertContains(Svg, 'class="pele pele-pie"');
        AssertContains(Svg, '>Pets</tspan>');
        AssertContains(Svg, 'data-id="Dogs"');
        AssertContains(Svg, '>79%</text>');
        AssertContains(Svg, 'var(--pele-series-1,#4c78a8)');
    end;

    [Test]
    procedure FrontMatterTitleAndConfig()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('---' + Lf() + 'title: My chart' + Lf() + 'config:' + Lf() + '  pie:' + Lf() + '    useMaxWidth: false' + Lf() + '---' + Lf() +
                                 'pie' + Lf() + '"A" : 1' + Lf());
        AssertContains(Svg, '>My chart</tspan>');
        AssertNotContains(Svg, 'max-width:100%');
    end;

    [Test]
    procedure DetectsDiagramTypes()
    begin
        AssertEqual('flowchart', MermaidSvg.DetectType('graph LR' + Lf() + 'A-->B'));
        AssertEqual('sequence', MermaidSvg.DetectType('%% comment' + Lf() + 'sequenceDiagram' + Lf() + 'A->>B: x'));
        AssertEqual('pie', MermaidSvg.DetectType('pie' + Lf() + '"a": 1'));
        AssertEqual('gantt', MermaidSvg.DetectType('gantt' + Lf() + 'title x'));
        AssertEqual('', MermaidSvg.DetectType('hello world'));
    end;

    [Test]
    procedure ReportsSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('flowchart LR' + Lf() + 'A --> B' + Lf() + 'C -->' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 3');
        AssertContains(ErrorMessage, 'Expecting ''NODE_STRING''');
    end;

    [Test]
    procedure ReportsUnsupportedTypes()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('classDiagram' + Lf() + 'class A' + Lf(), Svg, ErrorMessage) then
            Error('Expected an unsupported type error.');
        AssertContains(ErrorMessage, 'not supported yet');
    end;
}
