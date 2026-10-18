/// <summary>
/// Port of pele's diagrams/flowchart/graph.ts and render.ts with layout/compound.ts: resolves class styles,
/// measures labels and shapes, lays out each subgraph on its own in its own direction and places it in its
/// parent as one box, then draws clusters, edges with markers, edge labels and nodes.
/// </summary>
codeunit 68907 "Mermaid Flowchart Renderer"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Shapes: Codeunit "Mermaid Shapes";
        TempNode: Record "Mermaid Flow Node" temporary;
        TempEdge: Record "Mermaid Flow Edge" temporary;
        // Nodes, by index in declaration order
        NodeEntry: List of [Integer];
        IndexOfId: Dictionary of [Text, Integer];
        CW: List of [Decimal];
        CH: List of [Decimal];
        CParent: List of [Integer];
        CIsGroup: List of [Boolean];
        CDir: List of [Text];
        CPadX: List of [Decimal];
        CPadTop: List of [Decimal];
        CPadBottom: List of [Decimal];
        CMinW: List of [Decimal];
        CSeq: List of [Integer];
        CSpan: List of [Decimal];
        CX: List of [Decimal];
        CY: List of [Decimal];
        CDepth: List of [Integer];
        LX: List of [Decimal];
        LY: List of [Decimal];
        // Views
        VShape: List of [Text];
        VShapeAttr: List of [Text];
        VLineAttr: List of [Text];
        VTextAttr: List of [Text];
        VTextStyle: List of [Integer];
        VFontSize: List of [Decimal];
        VW: List of [Decimal];
        VH: List of [Decimal];
        VDy: List of [Decimal];
        VLoops: List of [Integer];
        // Drawn edges
        DEntry: List of [Integer];
        DSrc: List of [Integer];
        DDst: List of [Integer];
        DMinLen: List of [Integer];
        DLabelW: List of [Decimal];
        DLabelH: List of [Decimal];
        DLevel: List of [Integer];
        DItemA: List of [Integer];
        DItemB: List of [Integer];
        DRtStart: List of [Integer];
        DRtCount: List of [Integer];
        DLabelX: List of [Decimal];
        DLabelY: List of [Decimal];
        RtX: List of [Decimal];
        RtY: List of [Decimal];
        RtAxis: List of [Decimal];
        // Levels: 0 is the root, any other is the index of a group
        LevelOrder: List of [Integer];
        LevelDir: Dictionary of [Integer, Text];
        OriginX: Dictionary of [Integer, Decimal];
        OriginY: Dictionary of [Integer, Decimal];
        ContentOx: Dictionary of [Integer, Decimal];
        ContentOy: Dictionary of [Integer, Decimal];
        RootDir: Text;
        LayoutWidth: Decimal;
        LayoutHeight: Decimal;
        NodeSepV: Decimal;
        RankSepV: Decimal;
        EdgeSize: Decimal;
        WrapWidth: Decimal;
        GroupPad: Decimal;
        LoopBase: Decimal;

    local procedure DirectionOf(Dir: Text): Text
    begin
        if Dir in ['BT', 'LR', 'RL'] then
            exit(Dir);
        exit('TB');
    end;

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
        Ox: Decimal;
        Oy: Decimal;
        Width: Integer;
        Height: Integer;
        I: Integer;
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
        NodeSepV := NumberOption(Config, 'flowchart.nodeSpacing', 40);
        RankSepV := NumberOption(Config, 'flowchart.rankSpacing', 48);
        Curve := MText.ConfigText(Config, 'flowchart.curve', '');
        RootDir := DirectionOf(Parser.GetDirection());

        BuildNodes(Parser, Size);
        ResolveParents();
        BuildLevels();
        BuildEdges();
        LayoutLevels();
        PlaceAbsolute();
        BuildRoutes();

        TitleLbl.Layout(Parser.GetTitle(), false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 12;
        Inner := MText.MaxDec(LayoutWidth, TitleLbl.GetWidth());
        Ox := Pad + (Inner - LayoutWidth) / 2;
        Oy := Pad + TitleHeight;
        for I := 1 to CX.Count() do begin
            CX.Set(I, CX.Get(I) + Ox);
            CY.Set(I, CY.Get(I) + Oy);
        end;
        for I := 1 to RtX.Count() do begin
            RtX.Set(I, RtX.Get(I) + Ox);
            RtY.Set(I, RtY.Get(I) + Oy);
        end;
        for I := 1 to DLabelX.Count() do begin
            DLabelX.Set(I, DLabelX.Get(I) + Ox);
            DLabelY.Set(I, DLabelY.Get(I) + Oy);
        end;
        Width := MText.Ceil(Inner + 2 * Pad);
        Height := MText.Ceil(LayoutHeight + TitleHeight + 2 * Pad);

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
                VLoops.Add(0);
                CParent.Add(0);
                CDir.Add(TempNode.Direction);
                CSeq.Add(Index);
                CX.Add(0);
                CY.Add(0);
                LX.Add(0);
                LY.Add(0);
                CDepth.Add(0);
                CSpan.Add(0);
                if TempNode."Is Group" then begin
                    Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', FontSize, 4000, TextStyle);
                    VShape.Add('group');
                    VW.Add(0);
                    VH.Add(0);
                    VDy.Add(0);
                    CW.Add(0);
                    CH.Add(0);
                    CIsGroup.Add(true);
                    CPadX.Add(GroupPad);
                    if Lbl.GetHeight() > 0 then
                        CPadTop.Add(Lbl.GetHeight() + 16)
                    else
                        CPadTop.Add(GroupPad);
                    CPadBottom.Add(GroupPad);
                    CMinW.Add(Lbl.GetWidth() + 2 * GroupPad - 12);
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
                    CW.Add(W);
                    CH.Add(H);
                    CIsGroup.Add(false);
                    CPadX.Add(0);
                    CPadTop.Add(0);
                    CPadBottom.Add(0);
                    CMinW.Add(0);
                end;
            until TempNode.Next() = 0;
    end;

    local procedure NodeLabel(I: Integer; var Lbl: Codeunit "Mermaid Label")
    begin
        TempNode.Get(NodeEntry.Get(I));
        if CIsGroup.Get(I) then
            Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', VFontSize.Get(I), 4000, VTextStyle.Get(I))
        else
            if Shapes.HasLabel(VShape.Get(I)) then
                Lbl.Layout(TempNode.Label, TempNode."Label Type" = 'markdown', VFontSize.Get(I), WrapWidth, VTextStyle.Get(I))
            else
                Lbl.Reset();
    end;

    /// <summary>Each node's group, with groups that would contain each other lifted out to the root.</summary>
    local procedure ResolveParents()
    var
        I: Integer;
        P: Integer;
        Hops: Integer;
        Cycle: Boolean;
    begin
        for I := 1 to NodeEntry.Count() do begin
            TempNode.Get(NodeEntry.Get(I));
            P := 0;
            if TempNode."Parent Id" <> '' then
                if IndexOfId.Get(TempNode."Parent Id", P) then
                    if not CIsGroup.Get(P) then
                        P := 0;
            if P = I then
                P := 0;
            CParent.Set(I, P);
        end;
        for I := 1 to NodeEntry.Count() do begin
            P := CParent.Get(I);
            Hops := 0;
            Cycle := false;
            while (P <> 0) and not Cycle do begin
                if (P = I) or (Hops > NodeEntry.Count()) then
                    Cycle := true
                else begin
                    P := CParent.Get(P);
                    Hops += 1;
                end;
            end;
            if Cycle then
                CParent.Set(I, 0);
        end;
        for I := 1 to NodeEntry.Count() do begin
            P := CParent.Get(I);
            Hops := 0;
            while P <> 0 do begin
                Hops += 1;
                P := CParent.Get(P);
            end;
            CDepth.Set(I, Hops);
        end;
    end;

    /// <summary>The direction of a level: its group's own, or the one it inherits.</summary>
    local procedure DirOfLevel(L: Integer): Text
    var
        Dir: Text;
    begin
        if LevelDir.Get(L, Dir) then
            exit(Dir);
        exit(RootDir);
    end;

    local procedure FlowsSideways(I: Integer): Boolean
    var
        Dir: Text;
    begin
        Dir := DirOfLevel(CParent.Get(I));
        exit((Dir = 'LR') or (Dir = 'RL'));
    end;

    local procedure ItemsOf(L: Integer): List of [Integer]
    var
        Items: List of [Integer];
        I: Integer;
        J: Integer;
        Item: Integer;
        Moving: Boolean;
    begin
        for I := 1 to NodeEntry.Count() do
            if CParent.Get(I) = L then
                Items.Add(I);
        for I := 2 to Items.Count() do begin
            Item := Items.Get(I);
            J := I - 1;
            Moving := true;
            while Moving do
                if J < 1 then
                    Moving := false
                else
                    if CSeq.Get(Items.Get(J)) > CSeq.Get(Item) then begin
                        Items.Set(J + 1, Items.Get(J));
                        J -= 1;
                    end else
                        Moving := false;
            Items.Set(J + 1, Item);
        end;
        exit(Items);
    end;

    local procedure BuildLevels()
    var
        Q: Integer;
        L: Integer;
        Item: Integer;
        Items: List of [Integer];
        Dir: Text;
    begin
        LevelOrder.Add(0);
        LevelDir.Add(0, RootDir);
        Q := 1;
        while Q <= LevelOrder.Count() do begin
            L := LevelOrder.Get(Q);
            Items := ItemsOf(L);
            foreach Item in Items do
                if CIsGroup.Get(Item) then begin
                    LevelOrder.Add(Item);
                    if CDir.Get(Item) <> '' then
                        Dir := DirectionOf(CDir.Get(Item))
                    else
                        Dir := DirOfLevel(L);
                    LevelDir.Add(Item, Dir);
                end;
            Q += 1;
        end;
        // A group takes the smallest declaration order among its members.
        for Q := LevelOrder.Count() downto 2 do begin
            L := LevelOrder.Get(Q);
            Items := ItemsOf(L);
            foreach Item in Items do
                if CSeq.Get(Item) < CSeq.Get(L) then
                    CSeq.Set(L, CSeq.Get(Item));
        end;
        // Edges spread along the side of a node; a group lets them spread along all of it.
        for Item := 1 to NodeEntry.Count() do
            if CIsGroup.Get(Item) then
                CSpan.Set(Item, 100000)
            else
                CSpan.Set(Item, Shapes.Span(VShape.Get(Item), VW.Get(Item), VH.Get(Item), FlowsSideways(Item)));
    end;

    // ---------------------------------------------------------------- edges

    local procedure BuildEdges()
    var
        Lbl: Codeunit "Mermaid Label";
        Src: Integer;
        Dst: Integer;
        A: Integer;
        B: Integer;
        LabelW: Decimal;
        LabelH: Decimal;
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
                    A := Src;
                    B := Dst;
                    if Src = Dst then begin
                        // A self-loop sits beside the node, across the flow, and the node's box grows to hold it.
                        VLoops.Set(Src, VLoops.Get(Src) + 1);
                        if FlowsSideways(Src) then begin
                            if Lbl.GetHeight() > 0 then
                                CH.Set(Src, CH.Get(Src) + 2 * (LoopBase + Lbl.GetHeight() + 8))
                            else
                                CH.Set(Src, CH.Get(Src) + 2 * LoopBase);
                        end else
                            if Lbl.GetWidth() > 0 then
                                CW.Set(Src, CW.Get(Src) + 2 * (LoopBase + Lbl.GetWidth() + 12))
                            else
                                CW.Set(Src, CW.Get(Src) + 2 * LoopBase);
                        AddDrawnEdge(Src, Dst, LabelW, LabelH, -1, 0, 0);
                    end else begin
                        // The level whose items hold the two ends apart.
                        while CDepth.Get(A) > CDepth.Get(B) do
                            A := CParent.Get(A);
                        while CDepth.Get(B) > CDepth.Get(A) do
                            B := CParent.Get(B);
                        if A <> B then begin
                            while CParent.Get(A) <> CParent.Get(B) do begin
                                A := CParent.Get(A);
                                B := CParent.Get(B);
                            end;
                            AddDrawnEdge(Src, Dst, LabelW, LabelH, CParent.Get(A), A, B);
                        end;
                    end;
                end;
            until TempEdge.Next() = 0;
    end;

    local procedure AddDrawnEdge(Src: Integer; Dst: Integer; LabelW: Decimal; LabelH: Decimal; Level: Integer; ItemA: Integer; ItemB: Integer)
    var
        MinLen: Integer;
    begin
        DEntry.Add(TempEdge."Entry No.");
        DSrc.Add(Src);
        DDst.Add(Dst);
        MinLen := TempEdge.Length;
        if MinLen < 1 then
            MinLen := 1;
        DMinLen.Add(MinLen);
        DLabelW.Add(LabelW);
        DLabelH.Add(LabelH);
        DLevel.Add(Level);
        DItemA.Add(ItemA);
        DItemB.Add(ItemB);
        DRtStart.Add(0);
        DRtCount.Add(0);
        DLabelX.Add(0);
        DLabelY.Add(0);
    end;

    // ---------------------------------------------------------------- layout

    /// <summary>Bottom-up: lays out each level once the sizes of the groups in it are known.</summary>
    local procedure LayoutLevels()
    var
        Layout: Codeunit "Mermaid Layered Layout";
        Items: List of [Integer];
        LocalOf: Dictionary of [Integer, Integer];
        LevelEdges: List of [Integer];
        Q: Integer;
        L: Integer;
        K: Integer;
        Item: Integer;
        E: Integer;
        Dir: Text;
        Vertical: Boolean;
        W: Decimal;
        H: Decimal;
        Span: Decimal;
        Wc: Decimal;
        Hc: Decimal;
        X: Decimal;
        Y: Decimal;
        P: Integer;
        Axis: Decimal;
    begin
        for Q := LevelOrder.Count() downto 1 do begin
            L := LevelOrder.Get(Q);
            Dir := DirOfLevel(L);
            Vertical := (Dir = 'TB') or (Dir = 'BT');
            Axis := 1;
            if Vertical then
                Axis := 0;
            Items := ItemsOf(L);
            Clear(LocalOf);
            Clear(LevelEdges);
            Layout.Init(NodeSepV, 16, RankSepV, Builder.MarkerTrim('arrow_point'));
            foreach Item in Items do begin
                if Vertical then begin
                    W := CW.Get(Item);
                    H := CH.Get(Item);
                end else begin
                    W := CH.Get(Item);
                    H := CW.Get(Item);
                end;
                Span := CSpan.Get(Item);
                if CIsGroup.Get(Item) then
                    Span := MText.MinDec(Span, W - 2 * CPadX.Get(Item));
                LocalOf.Add(Item, Layout.AddNode(W, H, Span));
            end;
            for E := 1 to DSrc.Count() do
                if DLevel.Get(E) = L then begin
                    LevelEdges.Add(E);
                    if Vertical then
                        Layout.AddEdge(LocalOf.Get(DItemA.Get(E)), LocalOf.Get(DItemB.Get(E)), DMinLen.Get(E), DLabelW.Get(E), DLabelH.Get(E))
                    else
                        Layout.AddEdge(LocalOf.Get(DItemA.Get(E)), LocalOf.Get(DItemB.Get(E)), DMinLen.Get(E), DLabelH.Get(E), DLabelW.Get(E));
                end;
            Layout.Execute();
            if Vertical then begin
                Wc := Layout.GetWidth();
                Hc := Layout.GetHeight();
            end else begin
                Wc := Layout.GetHeight();
                Hc := Layout.GetWidth();
            end;
            foreach Item in Items do begin
                Orient(Layout.NodeX(LocalOf.Get(Item)), Layout.NodeY(LocalOf.Get(Item)), Dir, Wc, Hc, X, Y);
                LX.Set(Item, X);
                LY.Set(Item, Y);
            end;
            for K := 1 to LevelEdges.Count() do begin
                E := LevelEdges.Get(K);
                DRtStart.Set(E, RtX.Count() + 1);
                DRtCount.Set(E, Layout.EdgePointCount(K));
                for P := 1 to Layout.EdgePointCount(K) do begin
                    Orient(Layout.EdgePointX(K, P), Layout.EdgePointY(K, P), Dir, Wc, Hc, X, Y);
                    RtX.Add(X);
                    RtY.Add(Y);
                    RtAxis.Add(Axis);
                end;
                Orient(Layout.EdgeLabelX(K), Layout.EdgeLabelY(K), Dir, Wc, Hc, X, Y);
                DLabelX.Set(E, X);
                DLabelY.Set(E, Y);
            end;
            if L = 0 then begin
                LayoutWidth := Wc;
                LayoutHeight := Hc;
            end else begin
                CW.Set(L, MText.MaxDec(Wc + 2 * CPadX.Get(L), CMinW.Get(L)));
                CH.Set(L, Hc + CPadTop.Get(L) + CPadBottom.Get(L));
                ContentOx.Add(L, (CW.Get(L) - Wc) / 2);
                ContentOy.Add(L, CPadTop.Get(L));
            end;
        end;
    end;

    /// <summary>Turns a point of a top-to-bottom layout into the level's direction.</summary>
    local procedure Orient(Lx: Decimal; Ly: Decimal; Dir: Text; Wc: Decimal; Hc: Decimal; var X: Decimal; var Y: Decimal)
    begin
        if (Dir = 'TB') or (Dir = 'BT') then begin
            X := Lx;
            Y := Ly;
        end else begin
            X := Ly;
            Y := Lx;
        end;
        if Dir = 'BT' then
            Y := Hc - Y;
        if Dir = 'RL' then
            X := Wc - X;
    end;

    /// <summary>Top-down: every level's content is placed inside its group.</summary>
    local procedure PlaceAbsolute()
    var
        Items: List of [Integer];
        Q: Integer;
        L: Integer;
        Item: Integer;
        Ox: Decimal;
        Oy: Decimal;
    begin
        for Q := 1 to LevelOrder.Count() do begin
            L := LevelOrder.Get(Q);
            if L = 0 then begin
                Ox := 0;
                Oy := 0;
            end else begin
                Ox := CX.Get(L) - CW.Get(L) / 2 + ContentOx.Get(L);
                Oy := CY.Get(L) - CH.Get(L) / 2 + ContentOy.Get(L);
            end;
            OriginX.Add(L, Ox);
            OriginY.Add(L, Oy);
            Items := ItemsOf(L);
            foreach Item in Items do begin
                CX.Set(Item, Ox + LX.Get(Item));
                CY.Set(Item, Oy + LY.Get(Item));
            end;
        end;
    end;

    /// <summary>Which side of a box (0 top, 1 right, 2 bottom, 3 left) a point lies on, or -1.</summary>
    local procedure SideOf(I: Integer; X: Decimal; Y: Decimal): Integer
    var
        Dx: Decimal;
        Dy: Decimal;
    begin
        Dx := X - CX.Get(I);
        Dy := Y - CY.Get(I);
        if Abs(Abs(Dy) - CH.Get(I) / 2) < 0.5 then begin
            if Dy < 0 then
                exit(0);
            exit(2);
        end;
        if Abs(Abs(Dx) - CW.Get(I) / 2) < 0.5 then begin
            if Dx < 0 then
                exit(3);
            exit(1);
        end;
        exit(-1);
    end;

    local procedure SidePoint(I: Integer; Side: Integer; var X: Decimal; var Y: Decimal; var Axis: Decimal)
    begin
        X := CX.Get(I);
        Y := CY.Get(I);
        Axis := 0;
        case Side of
            0:
                Y := CY.Get(I) - CH.Get(I) / 2;
            1:
                begin
                    X := CX.Get(I) + CW.Get(I) / 2;
                    Axis := 1;
                end;
            3:
                begin
                    X := CX.Get(I) - CW.Get(I) / 2;
                    Axis := 1;
                end;
            else
                Y := CY.Get(I) + CH.Get(I) / 2;
        end;
    end;

    /// <summary>
    /// Moves every route into place. An edge whose end lies inside a group runs from the group's border,
    /// where the level above put it, to the node inside.
    /// </summary>
    local procedure BuildRoutes()
    var
        NewX: List of [Decimal];
        NewY: List of [Decimal];
        NewAxis: List of [Decimal];
        E: Integer;
        P: Integer;
        L: Integer;
        Start: Integer;
        Cnt: Integer;
        Side: Integer;
        X: Decimal;
        Y: Decimal;
        Axis: Decimal;
        Ox: Decimal;
        Oy: Decimal;
    begin
        for E := 1 to DSrc.Count() do begin
            L := DLevel.Get(E);
            if L >= 0 then begin
                Ox := OriginX.Get(L);
                Oy := OriginY.Get(L);
                Start := NewX.Count() + 1;
                Cnt := DRtCount.Get(E);
                if (Cnt > 0) and (DItemA.Get(E) <> DSrc.Get(E)) then begin
                    Side := SideOf(DItemA.Get(E), RtX.Get(DRtStart.Get(E)) + Ox, RtY.Get(DRtStart.Get(E)) + Oy);
                    SidePoint(DSrc.Get(E), Side, X, Y, Axis);
                    NewX.Add(X);
                    NewY.Add(Y);
                    NewAxis.Add(Axis);
                end;
                for P := 0 to Cnt - 1 do begin
                    NewX.Add(RtX.Get(DRtStart.Get(E) + P) + Ox);
                    NewY.Add(RtY.Get(DRtStart.Get(E) + P) + Oy);
                    NewAxis.Add(RtAxis.Get(DRtStart.Get(E) + P));
                end;
                if (Cnt > 0) and (DItemB.Get(E) <> DDst.Get(E)) then begin
                    Side := SideOf(DItemB.Get(E), RtX.Get(DRtStart.Get(E) + Cnt - 1) + Ox, RtY.Get(DRtStart.Get(E) + Cnt - 1) + Oy);
                    SidePoint(DDst.Get(E), Side, X, Y, Axis);
                    NewX.Add(X);
                    NewY.Add(Y);
                    NewAxis.Add(Axis);
                end;
                DRtStart.Set(E, Start);
                DRtCount.Set(E, NewX.Count() - Start + 1);
                DLabelX.Set(E, DLabelX.Get(E) + Ox);
                DLabelY.Set(E, DLabelY.Get(E) + Oy);
            end;
        end;
        RtX := NewX;
        RtY := NewY;
        RtAxis := NewAxis;
    end;

    // ---------------------------------------------------------------- drawing

    local procedure NodeClasses(I: Integer): Text
    begin
        TempNode.Get(NodeEntry.Get(I));
        exit(Builder.ClassNames(TempNode.Classes));
    end;

    /// <summary>Where a cluster's title goes: at the left, unless an edge enters its top there.</summary>
    local procedure ClusterTitleX(I: Integer; TitleWidth: Decimal): Decimal
    var
        Candidates: List of [Decimal];
        Top: Decimal;
        Left: Decimal;
        HalfW: Decimal;
        Candidate: Decimal;
        Gap: Decimal;
        Best: Decimal;
        BestGap: Decimal;
        K: Integer;
        Any: Boolean;
    begin
        if TitleWidth = 0 then
            exit(CX.Get(I));
        Top := CY.Get(I) - CH.Get(I) / 2;
        Left := CX.Get(I) - CW.Get(I) / 2;
        HalfW := TitleWidth / 2;
        Candidates.Add(Left + GroupPad - 6 + HalfW);
        Candidates.Add(CX.Get(I));
        Candidates.Add(Left + CW.Get(I) - GroupPad + 6 - HalfW);
        for K := 1 to RtY.Count() do
            if Abs(RtY.Get(K) - Top) < 0.5 then
                if (RtX.Get(K) > Left) and (RtX.Get(K) < Left + CW.Get(I)) then
                    Any := true;
        if not Any then
            exit(Candidates.Get(1));
        Best := Candidates.Get(1);
        BestGap := -1;
        foreach Candidate in Candidates do begin
            Gap := 1000000;
            for K := 1 to RtY.Count() do
                if Abs(RtY.Get(K) - Top) < 0.5 then
                    if (RtX.Get(K) > Left) and (RtX.Get(K) < Left + CW.Get(I)) then
                        Gap := MText.MinDec(Gap, Abs(RtX.Get(K) - Candidate) - HalfW);
            if Gap >= 6 then
                exit(Candidate);
            if Gap > BestGap + 0.5 then begin
                BestGap := Gap;
                Best := Candidate;
            end;
        end;
        exit(Best);
    end;

    local procedure DrawClusters(): Text
    var
        Lbl: Codeunit "Mermaid Label";
        Out: TextBuilder;
        Depth: Integer;
        MaxDepth: Integer;
        I: Integer;
        TitleX: Decimal;
        TitleY: Decimal;
    begin
        for I := 1 to NodeEntry.Count() do
            if CDepth.Get(I) > MaxDepth then
                MaxDepth := CDepth.Get(I);
        // Outer groups first, so the inner ones are drawn on top.
        for Depth := 0 to MaxDepth do
            for I := 1 to NodeEntry.Count() do
                if CIsGroup.Get(I) and (CDepth.Get(I) = Depth) then begin
                    NodeLabel(I, Lbl);
                    TitleX := ClusterTitleX(I, Lbl.GetWidth());
                    TitleY := CY.Get(I) - CH.Get(I) / 2 + 8 + Lbl.GetHeight() / 2;
                    Out.Append('<g class="pele-cluster' + NodeClasses(I) + '" data-id="' + MText.EscText(TempNode.Id) + '">' +
                               '<rect x="' + MText.Num(CX.Get(I) - CW.Get(I) / 2) + '" y="' + MText.Num(CY.Get(I) - CH.Get(I) / 2) + '" width="' + MText.Num(CW.Get(I)) +
                               '" height="' + MText.Num(CH.Get(I)) + '" rx="' + Builder.Radius() + '" fill="var(--_a)" fill-opacity="0.5" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>' +
                               Lbl.ToSvg(TitleX, TitleY, ' class="pele-cluster-label" fill="var(--_m)"' + VTextAttr.Get(I)) + '</g>');
                end;
        exit(Out.ToText());
    end;

    local procedure IsSafeLink(Url: Text): Boolean
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
            if not CIsGroup.Get(I) then begin
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
                Out.Append('<g class="pele-node pele-shape-' + VShape.Get(I) + NodeClasses(I) + '" data-id="' + MText.EscText(TempNode.Id) +
                           '" transform="translate(' + Builder.P(CX.Get(I), CY.Get(I)) + ')">' + Body + '</g>');
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
        if CIsGroup.Get(I) then
            exit;
        Side := SideOf(I, Route.Get(At), Route.Get(At + 1));
        if (Side = 0) or (Side = 2) then begin
            Amount := Shapes.Inset(VShape.Get(I), VW.Get(I), VH.Get(I), Side, Route.Get(At) - CX.Get(I)) + (CH.Get(I) - VH.Get(I)) / 2;
            if Side = 0 then
                Route.Set(At + 1, Route.Get(At + 1) + Amount)
            else
                Route.Set(At + 1, Route.Get(At + 1) - Amount);
        end else
            if Side >= 0 then begin
                Amount := Shapes.Inset(VShape.Get(I), VW.Get(I), VH.Get(I), Side, Route.Get(At + 1) - CY.Get(I)) + (CW.Get(I) - VW.Get(I)) / 2;
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
        P: Integer;
        K: Integer;
        Src: Integer;
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
        HasStyle: Boolean;
    begin
        for E := 1 to DSrc.Count() do begin
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
            HasStyle := StyleText <> '';
            ShapeAttr := '';
            LineAttr := '';
            TextAttr := '';
            Stroke := '';
            if HasStyle then begin
                Styles := SplitStyles(StyleText);
                Builder.ResolveStyle(Styles, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
            end;
            Lbl.Layout(TempEdge.Label, TempEdge."Label Type" = 'markdown', EdgeSize, WrapWidth, 0);
            LabelX := DLabelX.Get(E);
            LabelY := DLabelY.Get(E);
            if TempEdge.Stroke <> 'invisible' then begin
                ArrowTypes(TempEdge."Arrow Type", TempEdge.Stroke, StartType, EndType);
                Src := DSrc.Get(E);
                Markers := '';
                Color := 'var(--_l)';
                if Stroke <> '' then
                    Color := MText.Esc(Stroke);
                if Src = DDst.Get(E) then begin
                    if not LoopSeen.Get(Src, K) then
                        K := 0;
                    if LoopSeen.ContainsKey(Src) then
                        LoopSeen.Set(Src, K + 1)
                    else
                        LoopSeen.Add(Src, K + 1);
                    Builder.LoopPath(CX.Get(Src), CY.Get(Src), VW.Get(Src), VH.Get(Src), K, FlowsSideways(Src), LoopBase, Builder.MarkerTrim(EndType),
                                     DLabelW.Get(E), DLabelH.Get(E), LabelX, LabelY, D, Ex, Ey, Edx, Edy);
                    Markers := Builder.Marker(EndType, Ex, Ey, Edx, Edy, Color);
                end else begin
                    Clear(Route);
                    for P := 0 to DRtCount.Get(E) - 1 do begin
                        Route.Add(RtX.Get(DRtStart.Get(E) + P));
                        Route.Add(RtY.Get(DRtStart.Get(E) + P));
                        Route.Add(RtAxis.Get(DRtStart.Get(E) + P));
                    end;
                    D := '';
                    if Route.Count() >= 6 then begin
                        InsetEnd(Route, 1, Src);
                        InsetEnd(Route, Route.Count() - 2, DDst.Get(E));
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
