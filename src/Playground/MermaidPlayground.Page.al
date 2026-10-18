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

                field(SampleField; Sample)
                {
                    ApplicationArea = All;
                    Caption = 'Load sample';
                    ToolTip = 'Specifies a sample diagram to load into the editor. Choosing one replaces the current text.';

                    trigger OnValidate()
                    begin
                        if Sample <> Sample::None then
                            SetSource(SampleText(Sample));
                    end;
                }
                field(MermaidSourceField; MermaidSource)
                {
                    ApplicationArea = All;
                    Caption = 'Mermaid source';
                    ShowCaption = false;
                    MultiLine = true;
                    ToolTip = 'Specifies the Mermaid text to render. Type or paste a flowchart, sequence, class, state, ER, gantt, pie, git graph, mindmap, journey or timeline diagram, then leave the field or choose Render.';

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
                        ApplyClickSettings();
                        RenderDiagram();
                    end;

                    trigger ElementClicked(Kind: Text; Id: Text; Callback: Text; Arguments: Text; Href: Text; Classes: Text)
                    begin
                        LastClickText := DescribeClick(Kind, Id, Callback, Arguments, Href);
                        CurrPage.Update(false);
                    end;
                }
            }
            group(ClicksGroup)
            {
                Caption = 'Clicks';

                field(ClickModeField; ClickMode)
                {
                    ApplicationArea = All;
                    Caption = 'Click events';
                    OptionCaption = 'All elements,Clickable elements only,Off';
                    ToolTip = 'Specifies which elements of the diagram raise a click event: every element with an id, only the elements a click statement makes clickable, or none.';

                    trigger OnValidate()
                    begin
                        ApplyClickSettings();
                    end;
                }
                field(LinksInALField; LinksInAL)
                {
                    ApplicationArea = All;
                    Caption = 'Handle links in AL';
                    ToolTip = 'Specifies whether a link in the diagram (click A href "...") only raises the click event, instead of also opening in a new browser tab.';

                    trigger OnValidate()
                    begin
                        ApplyClickSettings();
                    end;
                }
                field(LastClickField; LastClickText)
                {
                    ApplicationArea = All;
                    Caption = 'Last click';
                    Editable = false;
                    MultiLine = true;
                    ToolTip = 'Specifies what the ElementClicked event reported for the last element you clicked in the preview.';
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
                    Sample := Sample::None;
                    SetSource('');
                end;
            }
            action(NextSampleAction)
            {
                ApplicationArea = All;
                Caption = 'Next Sample';
                Image = NextRecord;
                ToolTip = 'Load the next sample diagram, to step through every supported diagram type.';

                trigger OnAction()
                begin
                    if Sample.AsInteger() >= 12 then
                        Sample := Enum::"Mermaid Sample".FromInteger(1)
                    else
                        Sample := Enum::"Mermaid Sample".FromInteger(Sample.AsInteger() + 1);
                    SetSource(SampleText(Sample));
                end;
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
            actionref(NextSamplePromoted; NextSampleAction)
            {
            }
        }
    }

    trigger OnOpenPage()
    begin
        if MermaidSource = '' then begin
            Sample := Sample::Flowchart;
            MermaidSource := SampleText(Sample);
        end;
    end;

    var
        MermaidSvg: Codeunit "Mermaid SVG";
        Sample: Enum "Mermaid Sample";
        MermaidSource: Text;
        SvgText: Text;
        DiagramType: Text;
        StatusText: Text;
        StatusStyle: Text;
        CallStackText: Text;
        LastClickText: Text;
        ClickMode: Option All,Clickable,None;
        LinksInAL: Boolean;
        ViewerReady: Boolean;
        ShowSvgSource: Boolean;
        EmptyMsg: Label 'Type or paste Mermaid text above.';
        CallStackLbl: Label 'AL call stack:';
        ClickedMsg: Label '%1 "%2"', Comment = '%1 = the kind of element, such as node, %2 = its id';
        CallbackMsg: Label 'Callback: %1(%2)', Comment = '%1 = the callback name, %2 = its arguments';
        LinkMsg: Label 'Link: %1', Comment = '%1 = the link target';
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
        CallStackText := '';
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
            CallStackText := MermaidSvg.GetLastCallStack();
            StatusText := ErrorMessage;
            if CallStackText <> '' then
                StatusText := ErrorMessage + LineBreak() + LineBreak() + CallStackLbl + LineBreak() + CallStackText;
            StatusStyle := 'Unfavorable';
            if ViewerReady then
                CurrPage.Viewer.ShowError(StatusText);
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

    local procedure ApplyClickSettings()
    begin
        if not ViewerReady then
            exit;
        case ClickMode of
            ClickMode::All:
                CurrPage.Viewer.SetClickMode('all');
            ClickMode::Clickable:
                CurrPage.Viewer.SetClickMode('clickable');
            ClickMode::None:
                CurrPage.Viewer.SetClickMode('none');
        end;
        CurrPage.Viewer.SetLinkHandling(LinksInAL);
    end;

    /// <summary>
    /// What a click reported. In your own page, this is where you would act on it, for example open the record
    /// whose key is the node id, or run the procedure named by the callback with its arguments.
    /// </summary>
    local procedure DescribeClick(Kind: Text; Id: Text; Callback: Text; Arguments: Text; Href: Text): Text
    var
        Result: Text;
    begin
        Result := StrSubstNo(ClickedMsg, Kind, Id);
        if Callback <> '' then
            Result += LineBreak() + StrSubstNo(CallbackMsg, Callback, Arguments);
        if Href <> '' then
            Result += LineBreak() + StrSubstNo(LinkMsg, Href);
        exit(Result);
    end;

    local procedure LineBreak(): Text
    var
        Lf: Text[1];
    begin
        Lf[1] := 10;
        exit(Lf);
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

    local procedure SampleText(Which: Enum "Mermaid Sample"): Text
    begin
        case Which of
            Which::Flowchart:
                exit(SampleFlowchart());
            Which::FlowchartSubgraphs:
                exit(SampleSubgraphs());
            Which::Sequence:
                exit(SampleSequence());
            Which::ClassDiagram:
                exit(SampleClass());
            Which::StateDiagram:
                exit(SampleState());
            Which::ERDiagram:
                exit(SampleER());
            Which::Gantt:
                exit(SampleGantt());
            Which::Pie:
                exit(SamplePie());
            Which::GitGraph:
                exit(SampleGitGraph());
            Which::Mindmap:
                exit(SampleMindmap());
            Which::Journey:
                exit(SampleJourney());
            Which::Timeline:
                exit(SampleTimeline());
        end;
        exit('');
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
        Parts.Add('    click paid call openInvoice("103001") "Open the posted invoice"');
        Parts.Add('    click po call openPurchaseOrder("106001")');
        Parts.Add('    click start href "https://learn.microsoft.com/dynamics365/business-central/" "Business Central documentation"');
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

    local procedure SampleClass(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('classDiagram');
        Parts.Add('    direction LR');
        Parts.Add('    class Customer {');
        Parts.Add('        +Code No');
        Parts.Add('        +Text Name');
        Parts.Add('        +Decimal BalanceLCY');
        Parts.Add('        +CheckCreditLimit() Boolean');
        Parts.Add('    }');
        Parts.Add('    class SalesHeader {');
        Parts.Add('        <<Table>>');
        Parts.Add('        +Code DocumentNo');
        Parts.Add('        +Date PostingDate');
        Parts.Add('        +Post()');
        Parts.Add('    }');
        Parts.Add('    class SalesLine {');
        Parts.Add('        +Integer LineNo');
        Parts.Add('        +Decimal Quantity');
        Parts.Add('        +Decimal Amount');
        Parts.Add('    }');
        Parts.Add('    class Posting~T~ {');
        Parts.Add('        <<interface>>');
        Parts.Add('        +Run(T record)$');
        Parts.Add('    }');
        Parts.Add('    Customer "1" --> "*" SalesHeader : places');
        Parts.Add('    SalesHeader *-- "1..*" SalesLine : contains');
        Parts.Add('    Posting <|.. SalesHeader');
        Parts.Add('    note for Customer "Master data"');
        Parts.Add('    click Customer call openCustomer("10000") "Open the customer card"');
        exit(Lines(Parts));
    end;

    local procedure SampleState(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('stateDiagram-v2');
        Parts.Add('    accTitle: Order lifecycle');
        Parts.Add('    [*] --> Draft');
        Parts.Add('    Draft --> Review : submit');
        Parts.Add('    state Review {');
        Parts.Add('        [*] --> Checking');
        Parts.Add('        Checking --> Approved : ok');
        Parts.Add('        Checking --> Rejected : issues');
        Parts.Add('        --');
        Parts.Add('        [*] --> Pricing');
        Parts.Add('        Pricing --> Priced');
        Parts.Add('    }');
        Parts.Add('    state decision <<choice>>');
        Parts.Add('    Review --> decision');
        Parts.Add('    decision --> Shipped : approved');
        Parts.Add('    decision --> Draft : rework');
        Parts.Add('    Shipped --> [*]');
        Parts.Add('    note right of Draft');
        Parts.Add('        Drafts can be edited');
        Parts.Add('        until they are submitted');
        Parts.Add('    end note');
        Parts.Add('    note left of Shipped : Tracked by carrier');
        Parts.Add('    classDef done fill:#d4f7d4,stroke:#2e7d32');
        Parts.Add('    class Shipped done');
        exit(Lines(Parts));
    end;

    local procedure SampleER(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('erDiagram');
        Parts.Add('    CUSTOMER ||--o{ ORDER : places');
        Parts.Add('    ORDER ||--|{ LINE-ITEM : contains');
        Parts.Add('    PRODUCT ||--o{ LINE-ITEM : "ordered in"');
        Parts.Add('    CUSTOMER }|..|{ DELIVERY-ADDRESS : uses');
        Parts.Add('    CUSTOMER {');
        Parts.Add('        string id PK "Customer No."');
        Parts.Add('        string name');
        Parts.Add('        string email UK');
        Parts.Add('    }');
        Parts.Add('    ORDER {');
        Parts.Add('        int orderNumber PK');
        Parts.Add('        string customerId FK');
        Parts.Add('        date orderDate');
        Parts.Add('        decimal total "incl. VAT"');
        Parts.Add('    }');
        Parts.Add('    LINE-ITEM {');
        Parts.Add('        int orderNumber PK, FK');
        Parts.Add('        int lineNo PK');
        Parts.Add('        string productCode FK');
        Parts.Add('        int quantity');
        Parts.Add('        decimal unitPrice');
        Parts.Add('    }');
        Parts.Add('    PRODUCT {');
        Parts.Add('        string code PK');
        Parts.Add('        string description');
        Parts.Add('        List~string~ tags');
        Parts.Add('    }');
        Parts.Add('    DELIVERY-ADDRESS["Delivery address"] {');
        Parts.Add('        string street');
        Parts.Add('        string city');
        Parts.Add('    }');
        Parts.Add('    classDef master fill:#e8f0fe,stroke:#5b7bd5');
        Parts.Add('    class CUSTOMER,PRODUCT master');
        exit(Lines(Parts));
    end;

    local procedure SampleGantt(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('gantt');
        Parts.Add('    title Release plan');
        Parts.Add('    dateFormat YYYY-MM-DD');
        Parts.Add('    axisFormat %d %b');
        Parts.Add('    excludes weekends');
        Parts.Add('    section Design');
        Parts.Add('        Requirements      :done, req, 2026-01-05, 5d');
        Parts.Add('        Architecture      :active, arch, after req, 4d');
        Parts.Add('    section Build');
        Parts.Add('        Backend           :crit, be, after arch, 10d');
        Parts.Add('        Frontend          :fe, after arch, 8d');
        Parts.Add('        Testing           :test, after be, 5d');
        Parts.Add('    section Release');
        Parts.Add('        Go-live           :milestone, golive, after test, 0d');
        Parts.Add('    click be call openJob("JOB-0001")');
        exit(Lines(Parts));
    end;

    local procedure SampleGitGraph(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('---');
        Parts.Add('title: Release flow');
        Parts.Add('---');
        Parts.Add('gitGraph');
        Parts.Add('    commit id: "init"');
        Parts.Add('    commit tag: "v0.1"');
        Parts.Add('    branch develop');
        Parts.Add('    checkout develop');
        Parts.Add('    commit');
        Parts.Add('    branch feature/login order: 3');
        Parts.Add('    checkout feature/login');
        Parts.Add('    commit msg: "login form"');
        Parts.Add('    commit type: HIGHLIGHT');
        Parts.Add('    checkout develop');
        Parts.Add('    merge feature/login');
        Parts.Add('    commit type: REVERSE');
        Parts.Add('    checkout main');
        Parts.Add('    merge develop id: "release" tag: "v1.0"');
        Parts.Add('    branch hotfix');
        Parts.Add('    commit id: "fix"');
        Parts.Add('    checkout develop');
        Parts.Add('    cherry-pick id: "fix"');
        Parts.Add('    checkout main');
        Parts.Add('    merge hotfix tag: "v1.0.1"');
        exit(Lines(Parts));
    end;

    local procedure SampleMindmap(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('mindmap');
        Parts.Add('  root((Mind maps))');
        Parts.Add('    Origins');
        Parts.Add('      Long history');
        Parts.Add('      Popularisation');
        Parts.Add('        British popular psychology author Tony Buzan');
        Parts.Add('    Research');
        Parts.Add('      On effectiveness<br/>and features');
        Parts.Add('      On automatic creation');
        Parts.Add('        Uses');
        Parts.Add('            Creative techniques');
        Parts.Add('            Strategic planning');
        Parts.Add('            Argument mapping');
        Parts.Add('    Tools');
        Parts.Add('      Pen and paper');
        Parts.Add('      Mermaid');
        Parts.Add('      [Square]');
        Parts.Add('      (Rounded)');
        Parts.Add('      {{Hexagon}}');
        Parts.Add('      ))Bang((');
        Parts.Add('      )Cloud(');
        Parts.Add('      md["`**Markdown** and *emphasis*`"]');
        exit(Lines(Parts));
    end;

    local procedure SampleJourney(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('journey');
        Parts.Add('    title My working day');
        Parts.Add('    accTitle: A working day');
        Parts.Add('    section Go to work');
        Parts.Add('      Make tea: 5: Me');
        Parts.Add('      Go upstairs: 3: Me');
        Parts.Add('      Do work: 1: Me, Cat');
        Parts.Add('    section Go home');
        Parts.Add('      Go downstairs: 5: Me');
        Parts.Add('      Sit down: 4: Me, Cat');
        exit(Lines(Parts));
    end;

    local procedure SampleTimeline(): Text
    var
        Parts: List of [Text];
    begin
        Parts.Add('timeline');
        Parts.Add('    title History of Social Media Platforms');
        Parts.Add('    section Early days');
        Parts.Add('      2002 : LinkedIn');
        Parts.Add('      2004 : Facebook : Google');
        Parts.Add('    section Video and more');
        Parts.Add('      2005 : YouTube');
        Parts.Add('      2006 : Twitter');
        Parts.Add('           : Spotify');
        exit(Lines(Parts));
    end;
}
