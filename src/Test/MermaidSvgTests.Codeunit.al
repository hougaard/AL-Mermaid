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
        if MermaidSvg.TryRender('quadrantChart' + Lf() + 'title Reach' + Lf(), Svg, ErrorMessage) then
            Error('Expected an unsupported type error.');
        AssertContains(ErrorMessage, 'not supported yet');
    end;

    // ---------------------------------------------------------------- diagram types added later

    [Test]
    procedure ClassDiagramRendersClassesMembersAndRelations()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('classDiagram' + Lf() + 'Animal <|-- Duck' + Lf() + 'Animal : +int age' + Lf() + 'Animal: +isMammal() bool' + Lf() +
                                 'class Duck{' + Lf() + '  +String beakColor' + Lf() + '  +swim()$' + Lf() + '}' + Lf() +
                                 'link Duck "https://example.com" "Docs"' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-class"');
        AssertContains(Svg, 'class="pele-node pele-class" data-id="Animal"');
        AssertContains(Svg, 'class="pele-node pele-class clickable" data-id="Duck"');
        AssertContains(Svg, '>+int age</text>');
        AssertContains(Svg, '>+isMammal() : bool</text>');
        AssertContains(Svg, '>+String beakColor</text>');
        AssertContains(Svg, 'pele-static" style="text-decoration:underline"');
        AssertContains(Svg, 'class="pele-edge pele-relation"');
        AssertContains(Svg, 'class="pele-marker"');
        AssertContains(Svg, '<a href="https://example.com" target="_blank" rel="noopener"><title>Docs</title>');
    end;

    [Test]
    procedure ClassDiagramRendersNamespacesNotesAndCardinalities()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('classDiagram' + Lf() + 'namespace Shapes {' + Lf() + '  class Square~Shape~' + Lf() + '  class Circle' + Lf() + '}' + Lf() +
                                 '<<interface>> Square' + Lf() + 'Square "1" --> "*" Circle : draws' + Lf() + 'note for Circle "Round thing"' + Lf());
        AssertContains(Svg, 'class="pele-cluster pele-namespace" data-id="Shapes"');
        AssertContains(Svg, '>Shapes</text>');
        AssertContains(Svg, 'Square&lt;Shape&gt;');
        AssertContains(Svg, 'class="pele-annotation"');
        AssertContains(Svg, 'interface»</text>');
        AssertContains(Svg, 'class="pele-cardinality"');
        AssertContains(Svg, '>draws</text>');
        AssertContains(Svg, 'class="pele-node pele-note" data-id="note0"');
        AssertContains(Svg, '>Round thing</text>');
        AssertContains(Svg, 'pele-note-edge');
    end;

    [Test]
    procedure ClassDiagramReportsSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('classDiagram' + Lf() + 'class A' + Lf() + 'A <|-- ' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 3');
        AssertContains(ErrorMessage, 'got ''NEWLINE''');
    end;

    [Test]
    procedure ErRendersEntitiesAttributesAndKeys()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('erDiagram' + Lf() + 'CUSTOMER ||--o{ ORDER : places' + Lf() + 'CUSTOMER {' + Lf() +
                                 '  string name' + Lf() + '  string custNumber PK "the id"' + Lf() + '}' + Lf());
        AssertContains(Svg, 'class="pele pele-er"');
        AssertContains(Svg, 'class="pele-node pele-entity" data-id="CUSTOMER"');
        AssertContains(Svg, 'class="pele-node pele-entity" data-id="ORDER"');
        AssertContains(Svg, '>CUSTOMER</text>');
        AssertContains(Svg, 'class="pele-er-stripes"');
        AssertContains(Svg, 'class="pele-er-divider"');
        AssertContains(Svg, '>custNumber</text>');
        AssertContains(Svg, '>PK</text>');
        AssertContains(Svg, '>the id</text>');
        AssertContains(Svg, '>places</text>');
        AssertContains(Svg, 'class="pele-edge pele-er-identifying"');
        AssertContains(Svg, 'class="pele-marker"');
        AssertNotContains(Svg, 'stroke-dasharray="4 3"');
    end;

    [Test]
    procedure ErRendersAliasesLoopsGenericsAndClasses()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('erDiagram' + Lf() + 'direction LR' + Lf() + 'p["Person"] {' + Lf() + '  List~int~ ids' + Lf() + '}' + Lf() +
                                 'p }|..|{ p : knows' + Lf() + 'classDef hot fill:#f96' + Lf() + 'class p hot' + Lf());
        AssertContains(Svg, 'class="pele-node pele-entity hot" data-id="p"');
        AssertContains(Svg, '>Person</text>');
        AssertContains(Svg, '>List&lt;int&gt;</text>');
        AssertContains(Svg, '>knows</text>');
        AssertContains(Svg, 'class="pele-edge pele-er-non-identifying"');
        AssertContains(Svg, 'stroke-dasharray="4 3"');
        AssertContains(Svg, 'fill:#f96');
    end;

    [Test]
    procedure ErReportsSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('erDiagram' + Lf() + 'CUSTOMER ||--' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 2');
        AssertContains(ErrorMessage, 'Expecting ''ZERO_OR_ONE'', ''ZERO_OR_MORE'', ''ONE_OR_MORE'', ''ONLY_ONE'', ''MD_PARENT'', got ''NEWLINE''');
    end;

    [Test]
    procedure StateRendersStatesTransitionsAndLabels()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('stateDiagram-v2' + Lf() + '[*] --> Still' + Lf() + 'Still --> Moving : push' + Lf() +
                                 'Moving --> Still' + Lf() + 'Moving --> [*]' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-state"');
        AssertContains(Svg, 'class="pele-node pele-state-start" data-id="root_start"');
        AssertContains(Svg, 'class="pele-node pele-state-end" data-id="root_end"');
        AssertContains(Svg, 'class="pele-node pele-state" data-id="Still"');
        AssertContains(Svg, '>Still</text>');
        AssertContains(Svg, '>push</text>');
        AssertContains(Svg, 'class="pele-edge pele-transition"');
        AssertContains(Svg, 'class="pele-marker"');
        AssertContains(Svg, '</svg>');
    end;

    [Test]
    procedure StateRendersCompositesChoicesNotesAndClasses()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('stateDiagram' + Lf() + 'state Busy {' + Lf() + '  [*] --> Working' + Lf() + '  --' + Lf() + '  [*] --> Waiting' + Lf() + '}' + Lf() +
                                 'state check <<choice>>' + Lf() + 'Idle --> check' + Lf() + 'check --> Busy : yes' + Lf() + 'check --> Idle : no' + Lf() +
                                 'note right of Idle : Waiting here' + Lf() + 'classDef hot fill:#f96' + Lf() + 'class Busy hot' + Lf());
        AssertContains(Svg, 'class="pele-cluster pele-state-composite hot" data-id="Busy"');
        AssertContains(Svg, '>Busy</text>');
        AssertContains(Svg, 'fill:#f96');
        AssertContains(Svg, 'class="pele-node pele-state-choice" data-id="check"');
        AssertContains(Svg, 'class="pele-note"');
        AssertContains(Svg, '>Waiting here</text>');
        AssertContains(Svg, 'pele-note-edge');
        AssertContains(Svg, 'class="pele-divider"');
        AssertContains(Svg, 'data-id="divider-id-1_start"');
    end;

    [Test]
    procedure StateReportsSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('stateDiagram-v2' + Lf() + 'A -->' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 2');
        AssertContains(ErrorMessage, 'Expecting ''ID'', ''EDGE_STATE'', got ''NL''');
    end;

    [Test]
    procedure GitGraphRendersCommitsBranchesAndTags()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('gitGraph' + Lf() + '  commit' + Lf() + '  commit id: "Normal" tag: "v1.0"' + Lf() + '  branch develop' + Lf() +
                                 '  checkout develop' + Lf() + '  commit type: HIGHLIGHT' + Lf() + '  checkout main' + Lf() + '  merge develop tag: "v2.0"' + Lf());
        AssertContains(Svg, 'class="pele pele-gitGraph"');
        AssertContains(Svg, 'class="pele-branch" data-id="develop"');
        // Generated ids follow pele: the sequence number and seven hex digits derived from it.
        AssertContains(Svg, 'class="pele-commit pele-commit-normal" data-id="0-9e3779b"');
        AssertContains(Svg, '>0-9e3779b</text>');
        AssertContains(Svg, 'class="pele-commit pele-commit-highlight" data-id="2-daa66d1"');
        AssertContains(Svg, 'class="pele-commit pele-commit-merge" data-id="3-78dde6c"');
        AssertContains(Svg, '>v1.0</text>');
        AssertContains(Svg, '>v2.0</text>');
        AssertContains(Svg, '<path class="pele-edge" d="M44,0C62,0 62,83.8 80,83.8L88,83.8" stroke="var(--pele-series-2,#f58518)"/>');
        AssertContains(Svg, '<path class="pele-edge pele-edge-merge" d="M88,83.8L96,83.8C114,83.8 114,0 132,0"');
        AssertContains(Svg, 'viewBox="0 0 254 195"');
    end;

    [Test]
    procedure GitGraphTopToBottomCherryPickAndErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        Svg := MermaidSvg.Render('---' + Lf() + 'config:' + Lf() + '  gitGraph:' + Lf() + '    showCommitLabel: false' + Lf() + '---' + Lf() +
                                 'gitGraph TB:' + Lf() + '  commit id: "A"' + Lf() + '  branch hotfix' + Lf() + '  commit id: "B" type: REVERSE' + Lf() +
                                 '  checkout main' + Lf() + '  cherry-pick id: "B"' + Lf());
        AssertContains(Svg, '<path class="pele-lane" d="M136.74,-20L136.74,108"');
        AssertContains(Svg, 'class="pele-commit pele-commit-reverse" data-id="B"');
        AssertContains(Svg, 'class="pele-commit pele-commit-cherry-pick" data-id="2-daa66d1"');
        AssertContains(Svg, '<path class="pele-edge pele-edge-cherry-pick" d="M136.74,44C136.74,62 0,62 0,80L0,88" stroke="var(--pele-series-1,#4c78a8)" stroke-dasharray="4 3"/>');
        AssertContains(Svg, '>cherry-pick:B</text>');
        AssertNotContains(Svg, 'pele-commit-label');

        if MermaidSvg.TryRender('gitGraph' + Lf() + '  commit' + Lf() + '  checkout nope' + Lf(), Svg, ErrorMessage) then
            Error('Expected a checkout error.');
        AssertContains(ErrorMessage, 'Trying to checkout branch which is not yet created. (Help try using "branch nope")');

        if MermaidSvg.TryRender('gitGraph' + Lf() + '  commit' + Lf() + '  comit' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 3');
        AssertContains(ErrorMessage, 'Expecting a statement, a title, or a line break but found `comit`.');
    end;

    [Test]
    procedure MindmapRendersShapesSectionsAndClasses()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('mindmap' + Lf() + '  root((Plan))' + Lf() + '    Goals' + Lf() + '      [Grow]' + Lf() + '      (Keep)' + Lf() +
                                 '    Risks' + Lf() + '      ))Fire((' + Lf() + '      {{Cost}}' + Lf() + '      )Mist(' + Lf() +
                                 '      Urgent' + Lf() + '      :::urgent' + Lf() + '      ::icon(fa fa-book)' + Lf());
        AssertContains(Svg, 'class="pele pele-mindmap"');
        AssertContains(Svg, '<g class="pele-node pele-shape-circle pele-root" data-id="root" transform="translate(0,0)">');
        AssertContains(Svg, '<g class="pele-branch pele-section-0">');
        AssertContains(Svg, '<g class="pele-branch pele-section-1">');
        AssertContains(Svg, '<g class="pele-node pele-shape-branch" data-id="Goals" transform="translate(112.9,0)">');
        AssertContains(Svg, '<g class="pele-node pele-shape-rect" data-id="Grow" transform="translate(218.91,-28)">');
        AssertContains(Svg, 'class="pele-node pele-shape-rounded" data-id="Keep"');
        AssertContains(Svg, 'class="pele-node pele-shape-bang" data-id="Fire"');
        AssertContains(Svg, 'class="pele-node pele-shape-hex" data-id="Cost"');
        AssertContains(Svg, 'class="pele-node pele-shape-cloud" data-id="Mist"');
        AssertContains(Svg, '<g class="pele-node pele-shape-text urgent" data-id="Urgent" transform="translate(-209.12,96)">');
        AssertNotContains(Svg, 'pele-icon');
    end;

    [Test]
    procedure MindmapMarkdownTitleAndErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        Svg := MermaidSvg.Render('---' + Lf() + 'title: Ideas' + Lf() + '---' + Lf() + 'mindmap' + Lf() + '  root' + Lf() + '    a["`**Bold** and *it*`"]' + Lf());
        AssertContains(Svg, '>Ideas</tspan>');
        AssertContains(Svg, 'class="pele-node pele-shape-stadium pele-root" data-id="root"');
        AssertContains(Svg, '<path class="pele-edge" d="M39.78,0C65.78,0 65.78,0 91.78,0"/>');
        AssertContains(Svg, '<tspan x="0" y="5.6" font-weight="var(--_w)">Bold</tspan>');
        AssertContains(Svg, '<tspan font-style="italic">it</tspan>');

        if MermaidSvg.TryRender('mindmap' + Lf() + '  root' + Lf() + '  second' + Lf(), Svg, ErrorMessage) then
            Error('Expected a second root error.');
        AssertContains(ErrorMessage, 'There can be only one root. No parent could be found for ("second")');

        if MermaidSvg.TryRender('mindmap' + Lf() + '  root' + Lf() + '    a{oops}' + Lf(), Svg, ErrorMessage) then
            Error('Expected a lexical error.');
        AssertContains(ErrorMessage, 'Lexical error on line 3. Unrecognized text.');
    end;

    [Test]
    procedure JourneyRendersSectionsTasksFacesAndLegend()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('journey' + Lf() + 'title My working day' + Lf() + 'section Go to work' + Lf() +
                                 'Make tea: 5: Me' + Lf() + 'Go upstairs: 3: Me' + Lf() + 'Do work: 1: Me, Cat' + Lf() +
                                 'section Go home' + Lf() + 'Go downstairs: 5: Me' + Lf() + 'Sit down: 5: Me' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-journey"');
        AssertContains(Svg, '>My working day</tspan>');
        AssertContains(Svg, 'class="pele-cluster pele-section" data-id="Go to work"');
        AssertContains(Svg, 'class="pele-cluster pele-section" data-id="Go home"');
        AssertContains(Svg, 'class="pele-node pele-task" data-id="Make tea"');
        AssertContains(Svg, '>Make tea</text>');
        AssertContains(Svg, 'pele-face pele-face-happy');
        AssertContains(Svg, 'pele-face pele-face-neutral');
        AssertContains(Svg, 'pele-face pele-face-sad');
        AssertContains(Svg, 'class="pele-grid"');
        AssertContains(Svg, 'class="pele-edge"');
        AssertContains(Svg, '<title>Cat</title>');
        AssertContains(Svg, 'class="pele-legend-item" data-id="Cat"');
        AssertContains(Svg, 'class="pele-legend-item" data-id="Me"');
        // Actors are sorted, so Cat takes the first series colour and Me the second.
        AssertContains(Svg, 'r="5" fill="var(--pele-series-1,#4c78a8)"/>');
        AssertContains(Svg, 'fill="var(--pele-series-2,#f58518)"');
    end;

    [Test]
    procedure JourneyAccessibilityAndSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        Svg := MermaidSvg.Render('journey' + Lf() + 'accTitle: Daily routine' + Lf() + 'accDescr: How the day goes' + Lf() + 'Wake up: x' + Lf());
        AssertContains(Svg, '<title id="pele-title">Daily routine</title>');
        AssertContains(Svg, '<desc id="pele-desc">How the day goes</desc>');
        // A score that is not a number is drawn at the middle, with a neutral face.
        AssertContains(Svg, 'pele-face pele-face-neutral');
        AssertNotContains(Svg, 'class="pele-legend"');

        if MermaidSvg.TryRender('journey' + Lf() + 'title Day' + Lf() + 'Task without a score' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 3');
        AssertContains(ErrorMessage, 'Expecting ''taskData'', got ''NEWLINE''');
    end;

    [Test]
    procedure TimelineRendersPeriodsAndEvents()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('timeline' + Lf() + 'title History of Social Media' + Lf() + '2002 : LinkedIn' + Lf() +
                                 '2004 : Facebook : Google' + Lf() + '2005 : YouTube' + Lf() + '     : Twitch' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-timeline"');
        AssertContains(Svg, '>History of Social Media</tspan>');
        AssertContains(Svg, 'class="pele-node pele-period" data-id="2004"');
        AssertContains(Svg, '>2004</text>');
        AssertContains(Svg, 'class="pele-node pele-event"');
        AssertContains(Svg, '>Facebook</text>');
        AssertContains(Svg, '>Google</text>');
        AssertContains(Svg, '>Twitch</text>');
        AssertContains(Svg, 'class="pele-axis"');
        AssertContains(Svg, 'class="pele-marker"');
        AssertContains(Svg, 'class="pele-dot"');
        // Without sections each period takes the next series colour.
        AssertContains(Svg, 'fill="var(--pele-series-3,#54a24b)"');
    end;

    [Test]
    procedure TimelineSectionsDirectionAndErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        Svg := MermaidSvg.Render('timeline TD' + Lf() + 'section Stone Age' + Lf() + '7600 BC : Oldest known house' + Lf() +
                                 'section Bronze Age' + Lf() + '2300 BC : People arrive' + Lf() + '        : Stonehenge is built' + Lf());
        AssertContains(Svg, 'class="pele-cluster pele-section" data-id="Stone Age"');
        AssertContains(Svg, '>Stone Age</tspan>');
        AssertContains(Svg, 'class="pele-node pele-period" data-id="2300 BC"');
        AssertContains(Svg, '>Stonehenge is built</text>');
        // Running down, the axis ends in an arrow that points down.
        AssertContains(Svg, 'class="pele-axis" d="M');
        AssertNotContains(Svg, 'var(--pele-series-3,');

        if MermaidSvg.TryRender('timeline' + Lf() + ': an event with no period' + Lf(), Svg, ErrorMessage) then
            Error('Expected an error.');
        AssertContains(ErrorMessage, 'An event needs a time period before it.');

        if MermaidSvg.TryRender('timeline' + Lf() + '2001 :x' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 2');
        AssertContains(ErrorMessage, 'got ''INVALID''');
    end;

    [Test]
    procedure GanttRendersTasksSectionsAndAxis()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('gantt' + Lf() + 'title Plan' + Lf() + 'dateFormat YYYY-MM-DD' + Lf() + 'section Design' + Lf() +
                                 'Draft :done, a1, 2024-01-01, 3d' + Lf() + 'Review :crit, a2, after a1, 2d' + Lf() + 'section Ship' + Lf() +
                                 'Launch :milestone, m1, after a2, 0d' + Lf());
        AssertContains(Svg, '<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-gantt" viewBox="0 0 800 167"');
        AssertContains(Svg, '>Plan</tspan>');
        AssertContains(Svg, '<rect class="pele-section pele-section-0" x="0" y="48" width="800" height="60" fill="var(--_s)"/>');
        AssertContains(Svg, 'class="pele-task pele-done" data-id="a1"');
        AssertContains(Svg, 'class="pele-task pele-crit" data-id="a2"');
        AssertContains(Svg, 'class="pele-task pele-milestone" data-id="m1"');
        AssertContains(Svg, 'fill="var(--pele-critical,#e45756)"');
        AssertContains(Svg, 'class="pele-section-label" data-id="Design"');
        AssertContains(Svg, '>2024-01-01</text>');
        AssertContains(Svg, '>2024-01-06</text>');
        AssertContains(Svg, '</svg>');
    end;

    [Test]
    procedure GanttExcludesWeekendsAndSanitizesLinks()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('gantt' + Lf() + 'dateFormat YYYY-MM-DD' + Lf() + 'excludes weekends' + Lf() + 'Work :w1, 2024-01-05, 2d' + Lf() +
                                 'click w1 href "javascript:alert(1)"' + Lf() + 'More :w2, after w1, 1d' + Lf() + 'click w2 href "https://Example.com"' + Lf());
        AssertContains(Svg, '<g class="pele-excluded" fill="var(--_a)"><rect ');
        AssertContains(Svg, 'class="pele-task pele-clickable" data-id="w1"><rect');
        AssertContains(Svg, '<a href="https://example.com/" rel="noopener">');
        AssertContains(Svg, '>2024-01-09</text>');
        AssertNotContains(Svg, 'javascript');
    end;

    [Test]
    procedure GanttReportsSyntaxErrors()
    var
        Svg: Text;
        ErrorMessage: Text;
    begin
        if MermaidSvg.TryRender('gantt' + Lf() + 'dateFormat YYYY-MM-DD' + Lf() + 'Task without data' + Lf(), Svg, ErrorMessage) then
            Error('Expected a syntax error.');
        AssertContains(ErrorMessage, 'Parse error on line 3');
        AssertContains(ErrorMessage, 'Expecting ''taskData'', got ''NL''');
    end;

    // ---------------------------------------------------------------- click callbacks for the viewer's ElementClicked event

    [Test]
    procedure FlowchartKeepsClickCallbacks()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('flowchart LR' + Lf() + 'A --> B' + Lf() + 'click A call openCustomer("10000") "Open customer"' + Lf() + 'click B callbackOnly' + Lf());
        AssertContains(Svg, 'class="pele-node pele-shape-rect clickable" data-id="A" data-callback="openCustomer" data-args="&quot;10000&quot;"');
        AssertContains(Svg, 'data-id="B" data-callback="callbackOnly" transform=');
        AssertContains(Svg, '<title>Open customer</title>');
        AssertNotContains(Svg, 'onclick');
    end;

    [Test]
    procedure ClassDiagramKeepsClickCallbacks()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('classDiagram' + Lf() + 'class Customer' + Lf() + 'click Customer call openCustomer("10000")' + Lf());
        AssertContains(Svg, 'data-callback="openCustomer" data-args="&quot;10000&quot;"');
        AssertContains(Svg, 'clickable');
    end;

    [Test]
    procedure GanttKeepsClickCallbacks()
    var
        Svg: Text;
    begin
        Svg := MermaidSvg.Render('gantt' + Lf() + 'dateFormat YYYY-MM-DD' + Lf() + 'Task one :t1, 2026-01-05, 3d' + Lf() + 'click t1 call openJob("J1")' + Lf());
        AssertContains(Svg, 'pele-clickable');
        AssertContains(Svg, 'data-id="t1" data-callback="openJob" data-args="&quot;J1&quot;"');
    end;
}
