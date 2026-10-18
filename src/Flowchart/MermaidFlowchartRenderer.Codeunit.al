/// <summary>
/// Port of pele's diagrams/flowchart/graph.ts and render.ts: resolves class styles, measures labels and shapes,
/// lays the graph out with codeunit "Mermaid Compound Layout" (each subgraph on its own, in its own direction),
/// then draws clusters, edges with markers, edge labels and nodes.
/// </summary>
codeunit 68907 "Mermaid Flowchart Renderer"
{
    Access = Internal;

    var
        TempNode: Record "Mermaid Flow Node" temporary;
        TempEdge: Record "Mermaid Flow Edge" temporary;
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Shapes: Codeunit "Mermaid Shapes";
        Layout: Codeunit "Mermaid Compound Layout";
        // Nodes, by index in declaration order, which is also their index in the layout
        NodeEntry: List of [Integer];
        IndexOfId: Dictionary of [Text, Integer];
        VShape: List of [Text];
        VShapeAttr: List of [Text];
        VLineAttr: List of [Text];
        VTextAttr: List of [Text];
        VTextStyle: List of [Integer];
        VFontSize: List of [Decimal];
        VW: List of [Decimal];
        VH: List of [Decimal];
        VDy: List of [Decimal];
        VIsGroup: List of [Boolean];
        // Edges, by index in the layout
        DEntry: List of [Integer];
        DLabelW: List of [Decimal];
        DLabelH: List of [Decimal];
        EdgeSize: Decimal;
        WrapWidth: Decimal;
        GroupPad: Decimal;
        LoopBase: Decimal;

    local procedure NumberOption(var Config: Dictionary of [Text, Text]; Path: Text; Fallback: Decimal): Decimal
    var
        Value: Decimal;
    begin
        if MText.ConfigNumber(Config, Path, Value) then
            if Value > 0 then begin
                if Value > 2000 then
                    exit(2000);
                exit(Value);
            end;
        exit(Fallback);
    end;

    local procedure SplitStyles(Joined: Text): List of [Text]
    var
        Result: List of [Text];
        Part: Text;
    begin
        foreach Part in Joined.Split(';') do
            if MText.TrimWs(Part) <> '' then
                Result.Add(MText.TrimWs(Part));
        exit(Result);
    end;

    // ---------------------------------------------------------------- render

    procedure Render(var Parser: Codeunit "Mermaid Flowchart Parser"; var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Size: Decimal;
        Pad: Decimal;
        Curve: Text;
        TitleHeight: Decimal;
        Inner: Decimal;
        Width: Integer;
        Height: Integer;
        Content: Text;
        Clusters: Text;
        EdgesOut: Text;
        LabelsOut: Text;
        NodesOut: Text;
    begin
        Parser.GetNodes(TempNode);
        Parser.GetEdges(TempEdge);
        Size := MText.FontSize();
        EdgeSize := Round(Size * 0.875, 1);
        Pad := 8;
        GroupPad := 20;
        LoopBase := 26;
        WrapWidth := NumberOption(Config, 'flowchart.wrappingWidth', 200);
        Curve := MText.ConfigText(Config, 'flowchart.curve', '');
        Layout.Init(Parser.GetDirection(), NumberOption(Config, 'flowchart.nodeSpacing', 40), 16, NumberOption(Config, 'flowchart.rankSpacing', 48), Builder.MarkerTrim('arrow_point'));

        BuildNodes(Parser, Size);
        BuildEdges();
        Layout.Execute();

        TitleLbl.Layout(Parser.GetTitle(), false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 12;
        Inner := MText.MaxDec(Layout.GetWidth(), TitleLbl.GetWidth());
        Layout.Shift(Pad + (Inner - Layout.GetWidth()) / 2, Pad + TitleHeight);
        Width := MText.Ceil(Inner + 2 * Pad);
        Height := MText.Ceil(Layout.GetHeight() + TitleHeight + 2 * Pad);

        Clusters := DrawClusters();
        NodesOut := DrawNodes();
        DrawEdges(Parser, Curve, EdgesOut, LabelsOut);

        Content := Builder.TitleSvg(TitleLbl, Width / 2, Pad + TitleLbl.GetHeight() / 2);
        if Clusters <> '' then
            Content += '<g class="pele-clusters">' + Clusters + '</g>';
        if EdgesOut <> '' then
            Content += '<g class="pele-edges" fill="none" stroke="var(--_l)" stroke-linecap="round">' + EdgesOut + '</g>';
        if LabelsOut <> '' then
            Content += '<g class="pele-edge-labels" font-size="' + MText.Num(EdgeSize) + '">' + LabelsOut + '</g>';
        Content += '<g class="pele-nodes">' + NodesOut + '</g>';
        exit(Builder.Document('flowchart', Width, Height, Size, Parser.GetAccTitle(), Parser.GetAccDescr(), Content));
    end;

    // ---------------------------------------------------------------- nodes

    local procedure BuildNodes(var Parser: Codeunit "Mermaid Flowchart Parser"; Size: Decimal)
    var
        Lbl: Codeunit "Mermaid Label";
        Styles: List of [Text];
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleSize: Decimal;
        FontSize: Decimal;
        TextStyle: Integer;
        Shape: Text;
        Compiled: Text;
        W: Decimal;
        H: Decimal;
        Dy: Decimal;
        Index: Integer;
        Parent: Integer;
        I: Integer;
    begin
        TempNode.Reset();
        TempNode.SetCurrentKey("Entry No.");
        if TempNode.FindSet() then
            repeat
                Index += 1;
                NodeEntry.Add(TempNode."Entry No.");
                IndexOfId.Add(TempNode.Id, Index);
                if TempNode."Is Group" then
                    Compiled := Parser.CompiledStyles(TempNode.Classes)
                else
                    Compiled := Parser.CompiledStyles('default node ' + TempNode.Classes);
                if TempNode.Styles <> '' then
                    if Compiled = '' then
                        Compiled := TempNode.Styles
                    else
                        Compiled := Compiled + ';' + TempNode.Styles;
                Styles := SplitStyles(Compiled);
                Builder.ResolveStyle(Styles, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
                TextStyle := 0;
                if IsBold then
                    TextStyle += MText.StyleBold();
                if IsItalic then
                    TextStyle += MText.StyleItalic();
                FontSize := Size;
                if StyleSize > 0 then
                    FontSize := StyleSize;
                VShapeAttr.Add(ShapeAttr);
                VLineAttr.Add(LineAttr);
                VTextAttr.Add(TextAttr);
                VTextStyle.Add(TextStyle);
                VFontSize.Add(FontSize);
                VIsGroup.Add(TempNode."Is Group");
                if TempNode."Is Group" then begin
                    Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', FontSize, 4000, TextStyle);
                    VShape.Add('group');
                    VW.Add(0);
                    VH.Add(0);
                    VDy.Add(0);
                    Layout.AddNode(0, 0, 0);
                    if Lbl.GetHeight() > 0 then
                        Layout.SetGroup(Index, GroupPad, Lbl.GetHeight() + 16, GroupPad, Lbl.GetWidth() + 2 * GroupPad - 12, TempNode.Direction)
                    else
                        Layout.SetGroup(Index, GroupPad, GroupPad, GroupPad, Lbl.GetWidth() + 2 * GroupPad - 12, TempNode.Direction);
                end else begin
                    Shape := Shapes.Canonical(TempNode.Shape);
                    if Shapes.HasLabel(Shape) then
                        Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', FontSize, WrapWidth, TextStyle)
                    else
                        Lbl.Reset();
                    Shapes.GetSize(Shape, Lbl.GetWidth(), Lbl.GetHeight(), W, H, Dy);
                    VShape.Add(Shape);
                    VW.Add(W);
                    VH.Add(H);
                    VDy.Add(Dy);
                    Layout.AddNode(W, H, 0);
                end;
            until TempNode.Next() = 0;

        for I := 1 to NodeEntry.Count() do begin
            TempNode.Get(NodeEntry.Get(I));
            if TempNode."Parent Id" <> '' then
                if IndexOfId.Get(TempNode."Parent Id", Parent) then
                    Layout.SetParent(I, Parent);
        end;
        // The edges on one side of a node spread along it, as far as its shape allows.
        for I := 1 to NodeEntry.Count() do
            if not VIsGroup.Get(I) then
                Layout.SetSpan(I, Shapes.Span(VShape.Get(I), VW.Get(I), VH.Get(I), Layout.FlowsSideways(I)));
    end;

    local procedure NodeLabel(I: Integer; var Lbl: Codeunit "Mermaid Label")
    begin
        TempNode.Get(NodeEntry.Get(I));
        if VIsGroup.Get(I) then
            Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', VFontSize.Get(I), 4000, VTextStyle.Get(I))
        else
            if Shapes.HasLabel(VShape.Get(I)) then
                Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', VFontSize.Get(I), WrapWidth, VTextStyle.Get(I))
            else
                Lbl.Reset();
    end;

    // ---------------------------------------------------------------- edges

    local procedure BuildEdges()
    var
        Lbl: Codeunit "Mermaid Label";
        Src: Integer;
        Dst: Integer;
        LabelW: Decimal;
        LabelH: Decimal;
        MinLen: Integer;
    begin
        TempEdge.Reset();
        if TempEdge.FindSet() then
            repeat
                if IndexOfId.Get(TempEdge."Start Id", Src) and IndexOfId.Get(TempEdge."End Id", Dst) then begin
                    Lbl.Layout(TempEdge.Label, TempEdge."Label Type" = 'markdown', EdgeSize, WrapWidth, 0);
                    LabelW := 0;
                    LabelH := 0;
                    if Lbl.GetWidth() > 0 then
                        LabelW := Lbl.GetWidth() + 12;
                    if Lbl.GetHeight() > 0 then
                        LabelH := Lbl.GetHeight() + 4;
                    if Src = Dst then
                        // A self-loop sits beside the node, across the flow, and the node's box grows to hold it.
                        if Layout.FlowsSideways(Src) then begin
                            if Lbl.GetHeight() > 0 then
                                Layout.SetSize(Src, Layout.NodeW(Src), Layout.NodeH(Src) + 2 * (LoopBase + Lbl.GetHeight() + 8))
                            else
                                Layout.SetSize(Src, Layout.NodeW(Src), Layout.NodeH(Src) + 2 * LoopBase);
                        end else
                            if Lbl.GetWidth() > 0 then
                                Layout.SetSize(Src, Layout.NodeW(Src) + 2 * (LoopBase + Lbl.GetWidth() + 12), Layout.NodeH(Src))
                            else
                                Layout.SetSize(Src, Layout.NodeW(Src) + 2 * LoopBase, Layout.NodeH(Src));
                    MinLen := TempEdge.Length;
                    if MinLen < 1 then
                        MinLen := 1;
                    Layout.AddEdge(Src, Dst, MinLen, LabelW, LabelH);
                    DEntry.Add(TempEdge."Entry No.");
                    DLabelW.Add(LabelW);
                    DLabelH.Add(LabelH);
                end;
            until TempEdge.Next() = 0;
    end;

    // ---------------------------------------------------------------- drawing

    local procedure NodeClasses(I: Integer): Text
    begin
        TempNode.Get(NodeEntry.Get(I));
        exit(Builder.ClassNames(TempNode.Classes));
    end;

    local procedure DrawClusters(): Text
    var
        Lbl: Codeunit "Mermaid Label";
        Out: TextBuilder;
        Depth: Integer;
        I: Integer;
        TitleX: Decimal;
        TitleY: Decimal;
        X: Decimal;
        Y: Decimal;
        W: Decimal;
        H: Decimal;
    begin
        // Outer groups first, so the inner ones are drawn on top.
        for Depth := 0 to Layout.MaxDepth() do
            for I := 1 to NodeEntry.Count() do
                if VIsGroup.Get(I) then
                    if Layout.NodeDepth(I) = Depth then begin
                        NodeLabel(I, Lbl);
                        X := Layout.NodeX(I);
                        Y := Layout.NodeY(I);
                        W := Layout.NodeW(I);
                        H := Layout.NodeH(I);
                        TitleX := Layout.ClusterTitleX(I, Lbl.GetWidth(), GroupPad);
                        TitleY := Y - H / 2 + 8 + Lbl.GetHeight() / 2;
                        Out.Append('<g class="pele-cluster' + NodeClasses(I) + '" data-id="' + MText.EscText(TempNode.Id) + '">' +
                                   '<rect x="' + MText.Num(X - W / 2) + '" y="' + MText.Num(Y - H / 2) + '" width="' + MText.Num(W) +
                                   '" height="' + MText.Num(H) + '" rx="' + Builder.Radius() + '" fill="var(--_a)" fill-opacity="0.5" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>' +
                                   Lbl.ToSvg(TitleX, TitleY, ' class="pele-cluster-label" fill="var(--_m)"' + VTextAttr.Get(I)) + '</g>');
                    end;
        exit(Out.ToText());
    end;

    procedure IsSafeLink(Url: Text): Boolean
    var
        Lower: Text;
        Colon: Integer;
        Slash: Integer;
    begin
        if (Url = '') or (Url = 'about:blank') then
            exit(false);
        Lower := LowerCase(Url);
        Colon := StrPos(Lower, ':');
        Slash := StrPos(Lower, '/');
        if (Colon = 0) or ((Slash > 0) and (Slash < Colon)) then
            exit(true);
        exit(Lower.StartsWith('http:') or Lower.StartsWith('https:') or Lower.StartsWith('mailto:') or Lower.StartsWith('tel:'));
    end;

    local procedure DrawNodes(): Text
    var
        Lbl: Codeunit "Mermaid Label";
        Out: TextBuilder;
        I: Integer;
        Body: Text;
        Target: Text;
        ShapeAttrs: Text;
    begin
        for I := 1 to NodeEntry.Count() do
            if not VIsGroup.Get(I) then begin
                NodeLabel(I, Lbl);
                ShapeAttrs := ' fill="var(--_s)" stroke="var(--_b)"' + VShapeAttr.Get(I);
                Body := Shapes.Draw(VShape.Get(I), VW.Get(I), VH.Get(I), ShapeAttrs, ' stroke="var(--_b)"' + VLineAttr.Get(I)) +
                        Lbl.ToSvg(0, VDy.Get(I), ' class="pele-label"' + VTextAttr.Get(I));
                if TempNode.Tooltip <> '' then
                    Body := '<title>' + MText.EscText(TempNode.Tooltip) + '</title>' + Body;
                if IsSafeLink(TempNode.Link) then begin
                    Target := '';
                    if TempNode."Link Target" <> '' then
                        Target := ' target="' + MText.Esc(TempNode."Link Target") + '"';
                    Body := '<a href="' + MText.Esc(TempNode.Link) + '" rel="noopener"' + Target + '>' + Body + '</a>';
                end;
                Out.Append('<g class="pele-node pele-shape-' + VShape.Get(I) + NodeClasses(I) + '" data-id="' + MText.EscText(TempNode.Id) + '"' +
                           Builder.CallbackAttrs(TempNode.Callback, TempNode."Callback Args") + ' transform="translate(' + Builder.P(Layout.NodeX(I), Layout.NodeY(I)) + ')">' + Body + '</g>');
            end;
        exit(Out.ToText());
    end;

    local procedure ArrowTypes(ArrowType: Text; Stroke: Text; var StartType: Text; var EndType: Text)
    begin
        StartType := 'none';
        EndType := 'arrow_point';
        case ArrowType of
            'arrow_point', 'arrow_circle', 'arrow_cross':
                EndType := ArrowType;
            'double_arrow_point', 'double_arrow_circle', 'double_arrow_cross':
                begin
                    StartType := CopyStr(ArrowType, 8);
                    EndType := StartType;
                end;
        end;
        if (Stroke = 'invisible') or (ArrowType = 'arrow_open') then begin
            StartType := 'none';
            EndType := 'none';
        end;
    end;

    /// <summary>Moves a route end from a node's layout box onto the outline of the shape drawn in it.</summary>
    local procedure InsetEnd(var Route: List of [Decimal]; At: Integer; I: Integer)
    var
        Side: Integer;
        Amount: Decimal;
    begin
        if VIsGroup.Get(I) then
            exit;
        Side := Layout.SideOf(I, Route.Get(At), Route.Get(At + 1));
        if (Side = 0) or (Side = 2) then begin
            Amount := Shapes.Inset(VShape.Get(I), VW.Get(I), VH.Get(I), Side, Route.Get(At) - Layout.NodeX(I)) + (Layout.NodeH(I) - VH.Get(I)) / 2;
            if Side = 0 then
                Route.Set(At + 1, Route.Get(At + 1) + Amount)
            else
                Route.Set(At + 1, Route.Get(At + 1) - Amount);
        end else
            if Side >= 0 then begin
                Amount := Shapes.Inset(VShape.Get(I), VW.Get(I), VH.Get(I), Side, Route.Get(At + 1) - Layout.NodeY(I)) + (Layout.NodeW(I) - VW.Get(I)) / 2;
                if Side = 3 then
                    Route.Set(At, Route.Get(At) + Amount)
                else
                    Route.Set(At, Route.Get(At) - Amount);
            end;
    end;

    local procedure DrawEdges(var Parser: Codeunit "Mermaid Flowchart Parser"; DefaultCurve: Text; var EdgesOut: Text; var LabelsOut: Text)
    var
        Lbl: Codeunit "Mermaid Label";
        Route: List of [Decimal];
        Styles: List of [Text];
        LoopSeen: Dictionary of [Integer, Integer];
        EdgesBuilder: TextBuilder;
        LabelsBuilder: TextBuilder;
        E: Integer;
        K: Integer;
        Src: Integer;
        Dst: Integer;
        StyleText: Text;
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleSize: Decimal;
        StartType: Text;
        EndType: Text;
        Curve: Text;
        D: Text;
        Sx: Decimal;
        Sy: Decimal;
        Sdx: Decimal;
        Sdy: Decimal;
        Ex: Decimal;
        Ey: Decimal;
        Edx: Decimal;
        Edy: Decimal;
        LabelX: Decimal;
        LabelY: Decimal;
        Color: Text;
        Attrs: Text;
        Markers: Text;
    begin
        for E := 1 to DEntry.Count() do
            if Layout.EdgeHasRoute(E) or Layout.EdgeIsLoop(E) then begin
                TempEdge.Get(DEntry.Get(E));
                StyleText := Parser.CompiledStyles(TempEdge.Classes);
                if Parser.GetDefaultEdgeStyle() <> '' then
                    if StyleText = '' then
                        StyleText := Parser.GetDefaultEdgeStyle()
                    else
                        StyleText := StyleText + ';' + Parser.GetDefaultEdgeStyle();
                if TempEdge.Styles <> '' then
                    if StyleText = '' then
                        StyleText := TempEdge.Styles
                    else
                        StyleText := StyleText + ';' + TempEdge.Styles;
                ShapeAttr := '';
                LineAttr := '';
                TextAttr := '';
                Stroke := '';
                if StyleText <> '' then begin
                    Styles := SplitStyles(StyleText);
                    Builder.ResolveStyle(Styles, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
                end;
                Lbl.Layout(TempEdge.Label, TempEdge."Label Type" = 'markdown', EdgeSize, WrapWidth, 0);
                LabelX := Layout.EdgeLabelX(E);
                LabelY := Layout.EdgeLabelY(E);
                Src := IndexOfId.Get(TempEdge."Start Id");
                Dst := IndexOfId.Get(TempEdge."End Id");
                if TempEdge.Stroke <> 'invisible' then begin
                    ArrowTypes(TempEdge."Arrow Type", TempEdge.Stroke, StartType, EndType);
                    Markers := '';
                    D := '';
                    Color := 'var(--_l)';
                    if Stroke <> '' then
                        Color := MText.Esc(Stroke);
                    if Src = Dst then begin
                        if not LoopSeen.Get(Src, K) then
                            K := 0;
                        if LoopSeen.ContainsKey(Src) then
                            LoopSeen.Set(Src, K + 1)
                        else
                            LoopSeen.Add(Src, K + 1);
                        Builder.LoopPath(Layout.NodeX(Src), Layout.NodeY(Src), VW.Get(Src), VH.Get(Src), K, Layout.FlowsSideways(Src), LoopBase, Builder.MarkerTrim(EndType),
                                         DLabelW.Get(E), DLabelH.Get(E), LabelX, LabelY, D, Ex, Ey, Edx, Edy);
                        Markers := Builder.Marker(EndType, Ex, Ey, Edx, Edy, Color);
                    end else begin
                        Layout.EdgeRoute(E, Route);
                        if Route.Count() >= 6 then begin
                            InsetEnd(Route, 1, Src);
                            InsetEnd(Route, Route.Count() - 2, Dst);
                            Curve := TempEdge.Interpolate;
                            if Curve = '' then
                                Curve := Parser.GetDefaultInterpolate();
                            if Curve = '' then
                                Curve := DefaultCurve;
                            Builder.RoutePath(Route, Curve, Builder.MarkerTrim(StartType), Builder.MarkerTrim(EndType), D, Sx, Sy, Sdx, Sdy, Ex, Ey, Edx, Edy);
                            Markers := Builder.Marker(StartType, Sx, Sy, Sdx, Sdy, Color) + Builder.Marker(EndType, Ex, Ey, Edx, Edy, Color);
                        end;
                    end;
                    if D <> '' then begin
                        Attrs := '';
                        if TempEdge.Stroke = 'thick' then
                            Attrs := ' stroke-width="2.5"'
                        else
                            if TempEdge.Stroke = 'dotted' then
                                Attrs := ' stroke-dasharray="3 4"';
                        EdgesBuilder.Append('<g class="pele-edge" data-id="' + MText.EscText(TempEdge."Edge Id") + '"' + LineAttr + '>' +
                                            '<path d="' + D + '"' + Attrs + '/>' + Markers + '</g>');
                    end;
                end;
                if Lbl.GetWidth() > 0 then
                    LabelsBuilder.Append(Builder.EdgeLabelSvg(TempEdge."Edge Id", Lbl, LabelX, LabelY, TextAttr));
            end;
        EdgesOut := EdgesBuilder.ToText();
        LabelsOut := LabelsBuilder.ToText();
    end;
}
