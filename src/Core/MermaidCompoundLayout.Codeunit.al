/// <summary>
/// Port of pele's layout/compound.ts: lays out a graph whose nodes may be nested in groups. Each group is laid
/// out on its own, in its own direction, with codeunit "Mermaid Layered Layout", and then placed in its parent
/// as a single box. An edge that crosses a group's border runs from the border, where the level above put it,
/// to the node inside.
///
/// Usage: Init, AddNode for every node (groups too), SetGroup / SetParent / SetSeq as needed, AddEdge for every
/// edge, Execute, then read NodeX/NodeY/NodeW/NodeH (centres and sizes) and the edge routes. A route is a list of
/// points with an axis each: 0 where the edge runs vertically into the point, 1 where it runs horizontally, as
/// "Mermaid SVG Builder".RoutePath expects. Self-loops get no route; draw them with LoopPath.
/// </summary>
codeunit 68912 "Mermaid Compound Layout"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
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
        ESrc: List of [Integer];
        EDst: List of [Integer];
        EMinLen: List of [Integer];
        ELabelW: List of [Decimal];
        ELabelH: List of [Decimal];
        ELevel: List of [Integer];
        EItemA: List of [Integer];
        EItemB: List of [Integer];
        ERtStart: List of [Integer];
        ERtCount: List of [Integer];
        ELabelX: List of [Decimal];
        ELabelY: List of [Decimal];
        RtX: List of [Decimal];
        RtY: List of [Decimal];
        RtAxis: List of [Decimal];
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
        EdgeSepV: Decimal;
        RankSepV: Decimal;
        HeadRoomV: Decimal;
        Resolved: Boolean;

    /// <summary>The direction a diagram names, or top to bottom for anything else.</summary>
    procedure DirectionOf(Dir: Text): Text
    begin
        if Dir in ['BT', 'LR', 'RL'] then
            exit(Dir);
        exit('TB');
    end;

    // ---------------------------------------------------------------- building

    procedure Init(NewRootDir: Text; NodeSep: Decimal; EdgeSep: Decimal; RankSep: Decimal; HeadRoom: Decimal)
    begin
        ClearAll();
        RootDir := DirectionOf(NewRootDir);
        NodeSepV := NodeSep;
        EdgeSepV := EdgeSep;
        RankSepV := RankSep;
        HeadRoomV := HeadRoom;
    end;

    /// <summary>Adds a node W by H. Span is how much of a side its edges may spread along (0 keeps them at its middle).</summary>
    procedure AddNode(W: Decimal; H: Decimal; Span: Decimal): Integer
    begin
        CW.Add(W);
        CH.Add(H);
        CParent.Add(0);
        CIsGroup.Add(false);
        CDir.Add('');
        CPadX.Add(0);
        CPadTop.Add(0);
        CPadBottom.Add(0);
        CMinW.Add(0);
        CSeq.Add(CW.Count());
        CSpan.Add(Span);
        CX.Add(0);
        CY.Add(0);
        CDepth.Add(0);
        LX.Add(0);
        LY.Add(0);
        Resolved := false;
        exit(CW.Count());
    end;

    /// <summary>Makes a node a group: its size comes from its members plus the padding. Dir is its own direction, or empty to inherit.</summary>
    procedure SetGroup(I: Integer; PadX: Decimal; PadTop: Decimal; PadBottom: Decimal; MinW: Decimal; Dir: Text)
    begin
        CIsGroup.Set(I, true);
        CPadX.Set(I, PadX);
        CPadTop.Set(I, PadTop);
        CPadBottom.Set(I, PadBottom);
        CMinW.Set(I, MinW);
        CDir.Set(I, Dir);
        CSpan.Set(I, 100000);
        Resolved := false;
    end;

    procedure SetParent(I: Integer; Parent: Integer)
    begin
        CParent.Set(I, Parent);
        Resolved := false;
    end;

    /// <summary>The order a node keeps where nothing else decides; by default the order it was added in.</summary>
    procedure SetSeq(I: Integer; Seq: Integer)
    begin
        CSeq.Set(I, Seq);
    end;

    procedure SetSize(I: Integer; W: Decimal; H: Decimal)
    begin
        CW.Set(I, W);
        CH.Set(I, H);
    end;

    procedure SetSpan(I: Integer; Span: Decimal)
    begin
        CSpan.Set(I, Span);
    end;

    procedure AddEdge(Src: Integer; Dst: Integer; MinLen: Integer; LabelW: Decimal; LabelH: Decimal): Integer
    begin
        ESrc.Add(Src);
        EDst.Add(Dst);
        if MinLen < 1 then
            MinLen := 1;
        EMinLen.Add(MinLen);
        ELabelW.Add(LabelW);
        ELabelH.Add(LabelH);
        ELevel.Add(-2);
        EItemA.Add(0);
        EItemB.Add(0);
        ERtStart.Add(0);
        ERtCount.Add(0);
        ELabelX.Add(0);
        ELabelY.Add(0);
        exit(ESrc.Count());
    end;

    procedure NodeCount(): Integer
    begin
        exit(CW.Count());
    end;

    procedure EdgeCount(): Integer
    begin
        exit(ESrc.Count());
    end;

    // ---------------------------------------------------------------- results

    procedure GetWidth(): Decimal
    begin
        exit(LayoutWidth);
    end;

    procedure GetHeight(): Decimal
    begin
        exit(LayoutHeight);
    end;

    procedure NodeX(I: Integer): Decimal
    begin
        exit(CX.Get(I));
    end;

    procedure NodeY(I: Integer): Decimal
    begin
        exit(CY.Get(I));
    end;

    procedure NodeW(I: Integer): Decimal
    begin
        exit(CW.Get(I));
    end;

    procedure NodeH(I: Integer): Decimal
    begin
        exit(CH.Get(I));
    end;

    procedure IsGroup(I: Integer): Boolean
    begin
        exit(CIsGroup.Get(I));
    end;

    procedure NodeParent(I: Integer): Integer
    begin
        ResolveParents();
        exit(CParent.Get(I));
    end;

    procedure NodeDepth(I: Integer): Integer
    begin
        ResolveParents();
        exit(CDepth.Get(I));
    end;

    procedure MaxDepth(): Integer
    var
        I: Integer;
        Result: Integer;
    begin
        Result := 0;
        ResolveParents();
        for I := 1 to CW.Count() do
            if CDepth.Get(I) > Result then
                Result := CDepth.Get(I);
        exit(Result);
    end;

    /// <summary>The direction of the level a node is laid out in: its nearest group's own, or the root's.</summary>
    procedure FlowDir(I: Integer): Text
    var
        P: Integer;
        Hops: Integer;
    begin
        Hops := 0;
        ResolveParents();
        P := CParent.Get(I);
        while (P <> 0) and (Hops <= CW.Count()) do begin
            if CDir.Get(P) <> '' then
                exit(DirectionOf(CDir.Get(P)));
            P := CParent.Get(P);
            Hops += 1;
        end;
        exit(RootDir);
    end;

    procedure FlowsSideways(I: Integer): Boolean
    begin
        exit(FlowDir(I) in ['LR', 'RL']);
    end;

    /// <summary>Whether an edge was laid out: false for a self-loop and for an edge between a group and something inside it.</summary>
    procedure EdgeHasRoute(E: Integer): Boolean
    begin
        exit(ELevel.Get(E) >= 0);
    end;

    procedure EdgeIsLoop(E: Integer): Boolean
    begin
        exit(ESrc.Get(E) = EDst.Get(E));
    end;

    procedure EdgePointCount(E: Integer): Integer
    begin
        if ELevel.Get(E) < 0 then
            exit(0);
        exit(ERtCount.Get(E));
    end;

    procedure EdgePointX(E: Integer; K: Integer): Decimal
    begin
        exit(RtX.Get(ERtStart.Get(E) + K - 1));
    end;

    procedure EdgePointY(E: Integer; K: Integer): Decimal
    begin
        exit(RtY.Get(ERtStart.Get(E) + K - 1));
    end;

    procedure EdgePointAxis(E: Integer; K: Integer): Decimal
    begin
        exit(RtAxis.Get(ERtStart.Get(E) + K - 1));
    end;

    /// <summary>The route as x, y, axis triples, ready for RoutePath.</summary>
    procedure EdgeRoute(E: Integer; var Route: List of [Decimal])
    var
        K: Integer;
    begin
        Clear(Route);
        for K := 1 to EdgePointCount(E) do begin
            Route.Add(EdgePointX(E, K));
            Route.Add(EdgePointY(E, K));
            Route.Add(EdgePointAxis(E, K));
        end;
    end;

    procedure EdgeLabelX(E: Integer): Decimal
    begin
        exit(ELabelX.Get(E));
    end;

    procedure EdgeLabelY(E: Integer): Decimal
    begin
        exit(ELabelY.Get(E));
    end;

    /// <summary>Moves everything by (Ox, Oy).</summary>
    procedure Shift(Ox: Decimal; Oy: Decimal)
    var
        I: Integer;
    begin
        for I := 1 to CX.Count() do begin
            CX.Set(I, CX.Get(I) + Ox);
            CY.Set(I, CY.Get(I) + Oy);
        end;
        for I := 1 to RtX.Count() do begin
            RtX.Set(I, RtX.Get(I) + Ox);
            RtY.Set(I, RtY.Get(I) + Oy);
        end;
        for I := 1 to ELabelX.Count() do begin
            ELabelX.Set(I, ELabelX.Get(I) + Ox);
            ELabelY.Set(I, ELabelY.Get(I) + Oy);
        end;
    end;

    /// <summary>Which side of a node's box (0 top, 1 right, 2 bottom, 3 left) a point lies on, or -1.</summary>
    procedure SideOf(I: Integer; X: Decimal; Y: Decimal): Integer
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

    /// <summary>The x positions where routes cross the top border of a group, for placing its title clear of them.</summary>
    procedure TopCrossings(I: Integer; var Xs: List of [Decimal])
    var
        K: Integer;
        Top: Decimal;
        Left: Decimal;
    begin
        Clear(Xs);
        Top := CY.Get(I) - CH.Get(I) / 2;
        Left := CX.Get(I) - CW.Get(I) / 2;
        for K := 1 to RtY.Count() do
            if Abs(RtY.Get(K) - Top) < 0.5 then
                if (RtX.Get(K) > Left) and (RtX.Get(K) < Left + CW.Get(I)) then
                    Xs.Add(RtX.Get(K));
    end;

    /// <summary>Where a group's title goes, Pad in from its left: at the left, unless an edge enters its top there.</summary>
    procedure ClusterTitleX(I: Integer; TitleWidth: Decimal; Pad: Decimal): Decimal
    var
        Crossing: List of [Decimal];
        Candidates: List of [Decimal];
        Left: Decimal;
        HalfW: Decimal;
        Candidate: Decimal;
        Gap: Decimal;
        Best: Decimal;
        BestGap: Decimal;
        X: Decimal;
    begin
        if TitleWidth = 0 then
            exit(CX.Get(I));
        Left := CX.Get(I) - CW.Get(I) / 2;
        HalfW := TitleWidth / 2;
        Candidates.Add(Left + Pad - 6 + HalfW);
        Candidates.Add(CX.Get(I));
        Candidates.Add(Left + CW.Get(I) - Pad + 6 - HalfW);
        TopCrossings(I, Crossing);
        if Crossing.Count() = 0 then
            exit(Candidates.Get(1));
        Best := Candidates.Get(1);
        BestGap := -1;
        foreach Candidate in Candidates do begin
            Gap := 1000000;
            foreach X in Crossing do
                Gap := MText.MinDec(Gap, Abs(X - Candidate) - HalfW);
            if Gap >= 6 then
                exit(Candidate);
            if Gap > BestGap + 0.5 then begin
                BestGap := Gap;
                Best := Candidate;
            end;
        end;
        exit(Best);
    end;

    // ---------------------------------------------------------------- run

    procedure Execute()
    begin
        ResolveParents();
        BuildLevels();
        AssignEdges();
        LayoutLevels();
        PlaceAbsolute();
        BuildRoutes();
    end;

    /// <summary>Each node's group, with groups that would contain each other lifted out to the root.</summary>
    local procedure ResolveParents()
    var
        I: Integer;
        P: Integer;
        Hops: Integer;
        Cycle: Boolean;
    begin
        if Resolved then
            exit;
        for I := 1 to CW.Count() do begin
            P := CParent.Get(I);
            if (P < 0) or (P > CW.Count()) or (P = I) then
                P := 0;
            if P <> 0 then
                if not CIsGroup.Get(P) then
                    P := 0;
            CParent.Set(I, P);
        end;
        for I := 1 to CW.Count() do begin
            P := CParent.Get(I);
            Hops := 0;
            Cycle := false;
            while (P <> 0) and not Cycle do
                if (P = I) or (Hops > CW.Count()) then
                    Cycle := true
                else begin
                    P := CParent.Get(P);
                    Hops += 1;
                end;
            if Cycle then
                CParent.Set(I, 0);
        end;
        for I := 1 to CW.Count() do begin
            P := CParent.Get(I);
            Hops := 0;
            while P <> 0 do begin
                Hops += 1;
                P := CParent.Get(P);
            end;
            CDepth.Set(I, Hops);
        end;
        Resolved := true;
    end;

    local procedure DirOfLevel(L: Integer): Text
    var
        Dir: Text;
    begin
        if LevelDir.Get(L, Dir) then
            exit(Dir);
        exit(RootDir);
    end;

    local procedure ItemsOf(L: Integer): List of [Integer]
    var
        Items: List of [Integer];
        I: Integer;
        J: Integer;
        Item: Integer;
        Moving: Boolean;
    begin
        for I := 1 to CW.Count() do
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
        Items: List of [Integer];
        Q: Integer;
        L: Integer;
        Item: Integer;
        Dir: Text;
    begin
        Clear(LevelOrder);
        Clear(LevelDir);
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
    end;

    /// <summary>For every edge, the level whose items hold its two ends apart.</summary>
    local procedure AssignEdges()
    var
        E: Integer;
        A: Integer;
        B: Integer;
    begin
        for E := 1 to ESrc.Count() do begin
            A := ESrc.Get(E);
            B := EDst.Get(E);
            ELevel.Set(E, -1);
            if A <> B then begin
                while CDepth.Get(A) > CDepth.Get(B) do
                    A := CParent.Get(A);
                while CDepth.Get(B) > CDepth.Get(A) do
                    B := CParent.Get(B);
                if A <> B then begin
                    while CParent.Get(A) <> CParent.Get(B) do begin
                        A := CParent.Get(A);
                        B := CParent.Get(B);
                    end;
                    ELevel.Set(E, CParent.Get(A));
                    EItemA.Set(E, A);
                    EItemB.Set(E, B);
                end;
            end;
        end;
    end;

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
        P: Integer;
        Dir: Text;
        Vertical: Boolean;
        W: Decimal;
        H: Decimal;
        Span: Decimal;
        Wc: Decimal;
        Hc: Decimal;
        X: Decimal;
        Y: Decimal;
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
            Layout.Init(NodeSepV, EdgeSepV, RankSepV, HeadRoomV);
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
            for E := 1 to ESrc.Count() do
                if ELevel.Get(E) = L then begin
                    LevelEdges.Add(E);
                    if Vertical then
                        Layout.AddEdge(LocalOf.Get(EItemA.Get(E)), LocalOf.Get(EItemB.Get(E)), EMinLen.Get(E), ELabelW.Get(E), ELabelH.Get(E))
                    else
                        Layout.AddEdge(LocalOf.Get(EItemA.Get(E)), LocalOf.Get(EItemB.Get(E)), EMinLen.Get(E), ELabelH.Get(E), ELabelW.Get(E));
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
                ERtStart.Set(E, RtX.Count() + 1);
                ERtCount.Set(E, Layout.EdgePointCount(K));
                for P := 1 to Layout.EdgePointCount(K) do begin
                    Orient(Layout.EdgePointX(K, P), Layout.EdgePointY(K, P), Dir, Wc, Hc, X, Y);
                    RtX.Add(X);
                    RtY.Add(Y);
                    RtAxis.Add(Axis);
                end;
                Orient(Layout.EdgeLabelX(K), Layout.EdgeLabelY(K), Dir, Wc, Hc, X, Y);
                ELabelX.Set(E, X);
                ELabelY.Set(E, Y);
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
    local procedure Orient(LocalX: Decimal; LocalY: Decimal; Dir: Text; Wc: Decimal; Hc: Decimal; var X: Decimal; var Y: Decimal)
    begin
        if (Dir = 'TB') or (Dir = 'BT') then begin
            X := LocalX;
            Y := LocalY;
        end else begin
            X := LocalY;
            Y := LocalX;
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
        for E := 1 to ESrc.Count() do begin
            L := ELevel.Get(E);
            if L >= 0 then begin
                Ox := OriginX.Get(L);
                Oy := OriginY.Get(L);
                Start := NewX.Count() + 1;
                Cnt := ERtCount.Get(E);
                if Cnt > 0 then
                    if EItemA.Get(E) <> ESrc.Get(E) then begin
                        Side := SideOf(EItemA.Get(E), RtX.Get(ERtStart.Get(E)) + Ox, RtY.Get(ERtStart.Get(E)) + Oy);
                        SidePoint(ESrc.Get(E), Side, X, Y, Axis);
                        NewX.Add(X);
                        NewY.Add(Y);
                        NewAxis.Add(Axis);
                    end;
                for P := 0 to Cnt - 1 do begin
                    NewX.Add(RtX.Get(ERtStart.Get(E) + P) + Ox);
                    NewY.Add(RtY.Get(ERtStart.Get(E) + P) + Oy);
                    NewAxis.Add(RtAxis.Get(ERtStart.Get(E) + P));
                end;
                if Cnt > 0 then
                    if EItemB.Get(E) <> EDst.Get(E) then begin
                        Side := SideOf(EItemB.Get(E), RtX.Get(ERtStart.Get(E) + Cnt - 1) + Ox, RtY.Get(ERtStart.Get(E) + Cnt - 1) + Oy);
                        SidePoint(EDst.Get(E), Side, X, Y, Axis);
                        NewX.Add(X);
                        NewY.Add(Y);
                        NewAxis.Add(Axis);
                    end;
                ERtStart.Set(E, Start);
                ERtCount.Set(E, NewX.Count() - Start + 1);
                ELabelX.Set(E, ELabelX.Get(E) + Ox);
                ELabelY.Set(E, ELabelY.Get(E) + Oy);
            end;
        end;
        RtX := NewX;
        RtY := NewY;
        RtAxis := NewAxis;
    end;
}
