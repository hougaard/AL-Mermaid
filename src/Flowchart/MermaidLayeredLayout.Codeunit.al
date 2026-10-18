/// <summary>
/// Layered (Sugiyama-style) layout of one flat graph, after pele's layout/layered.ts. Ranks run down the
/// y axis; callers rotate the result for other directions.
///
/// Steps, as in pele: edges that close a cycle are reversed (orient), nodes get ranks by longest path and
/// a balancing pass (rank), long edges are cut into rank-to-rank segments through dummy nodes, with an
/// edge's label in a dummy of its own, the order in each rank is improved by barycenter sweeps that keep
/// the order with the fewest crossings, the ends of edges on one side of a node are spread along it, and
/// x positions come from repeated weighted isotonic fits that pull each node towards its neighbours while
/// keeping the order and the room between neighbours. Ranks are then stacked into bands.
///
/// This port keeps pele's structure and constants but replaces its track and level routing with plain
/// curves through the bends that remain.
/// </summary>
codeunit 68906 "Mermaid Layered Layout"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        // Options
        NodeSep: Decimal;
        EdgeSep: Decimal;
        RankSep: Decimal;
        HeadRoom: Decimal;
        // Real nodes, then dummies
        NodeW: List of [Decimal];
        NodeH: List of [Decimal];
        NodeSpan: List of [Decimal];
        Kind: List of [Integer];
        RankOf: List of [Integer];
        XPos: List of [Decimal];
        YPos: List of [Decimal];
        RealCount: Integer;
        // Edges
        ETail: List of [Integer];
        EHead: List of [Integer];
        EMinLen: List of [Integer];
        ELabelW: List of [Decimal];
        ELabelH: List of [Decimal];
        EReversed: List of [Boolean];
        EFirstSeg: List of [Integer];
        ELastSeg: List of [Integer];
        ELabelNode: List of [Integer];
        ELabelX: List of [Decimal];
        ELabelY: List of [Decimal];
        EPtStart: List of [Integer];
        EPtCount: List of [Integer];
        PtX: List of [Decimal];
        PtY: List of [Decimal];
        // Segments
        SegFrom: List of [Integer];
        SegTo: List of [Integer];
        SegFromDx: List of [Decimal];
        SegToDx: List of [Decimal];
        // Adjacency (compressed): segments leaving and reaching each node
        SuccStart: List of [Integer];
        SuccSeg: List of [Integer];
        PredStart: List of [Integer];
        PredSeg: List of [Integer];
        // Layers
        MaxRank: Integer;
        LayerStart: List of [Integer];
        Order: List of [Integer];
        PosOf: List of [Integer];
        BandTop: List of [Decimal];
        BandBottom: List of [Decimal];
        RankStep: Integer;
        ResultWidth: Decimal;
        ResultHeight: Decimal;

    // ---------------------------------------------------------------- building

    procedure Init(NewNodeSep: Decimal; NewEdgeSep: Decimal; NewRankSep: Decimal; NewHeadRoom: Decimal)
    begin
        ClearAll();
        NodeSep := NewNodeSep;
        EdgeSep := NewEdgeSep;
        RankSep := NewRankSep;
        HeadRoom := NewHeadRoom;
    end;

    procedure AddNode(W: Decimal; H: Decimal; Span: Decimal): Integer
    begin
        NodeW.Add(W);
        NodeH.Add(H);
        NodeSpan.Add(Span);
        Kind.Add(0);
        RealCount += 1;
        exit(RealCount);
    end;

    procedure AddEdge(Tail: Integer; Head: Integer; MinLen: Integer; LabelW: Decimal; LabelH: Decimal): Integer
    begin
        ETail.Add(Tail);
        EHead.Add(Head);
        if MinLen < 1 then
            MinLen := 1;
        EMinLen.Add(MinLen);
        ELabelW.Add(LabelW);
        ELabelH.Add(LabelH);
        EReversed.Add(false);
        exit(ETail.Count());
    end;

    // ---------------------------------------------------------------- results

    procedure GetWidth(): Decimal
    begin
        exit(ResultWidth);
    end;

    procedure GetHeight(): Decimal
    begin
        exit(ResultHeight);
    end;

    procedure NodeX(I: Integer): Decimal
    begin
        exit(XPos.Get(I));
    end;

    procedure NodeY(I: Integer): Decimal
    begin
        exit(YPos.Get(I));
    end;

    procedure EdgePointCount(E: Integer): Integer
    begin
        exit(EPtCount.Get(E));
    end;

    procedure EdgePointX(E: Integer; K: Integer): Decimal
    begin
        exit(PtX.Get(EPtStart.Get(E) + K - 1));
    end;

    procedure EdgePointY(E: Integer; K: Integer): Decimal
    begin
        exit(PtY.Get(EPtStart.Get(E) + K - 1));
    end;

    procedure EdgeLabelX(E: Integer): Decimal
    begin
        exit(ELabelX.Get(E));
    end;

    procedure EdgeLabelY(E: Integer): Decimal
    begin
        exit(ELabelY.Get(E));
    end;

    procedure EdgeReversed(E: Integer): Boolean
    begin
        exit(EReversed.Get(E));
    end;

    // ---------------------------------------------------------------- run

    procedure Execute()
    begin
        ResultWidth := 0;
        ResultHeight := 0;
        if RealCount = 0 then
            exit;
        RankStep := ChooseStep();
        Orient();
        AssignRanks();
        BuildSegments();
        BuildAdjacency();
        BuildLayers();
        InitialOrder();
        if (SegFrom.Count() > 0) and (MaxRank > 0) then
            ReduceCrossings();
        Spread();
        AssignX();
        Normalize();
        AssignY();
        BuildRoutes();
    end;

    /// <summary>Every edge gets a middle rank of its own when labels or parallel edges need the room.</summary>
    local procedure ChooseStep(): Integer
    var
        Seen: Dictionary of [Text, Boolean];
        E: Integer;
        A: Integer;
        B: Integer;
        PairKey: Text;
    begin
        for E := 1 to ETail.Count() do begin
            A := ETail.Get(E);
            B := EHead.Get(E);
            if A > B then begin
                A := EHead.Get(E);
                B := ETail.Get(E);
            end;
            PairKey := MText.IntText(A) + ',' + MText.IntText(B);
            if (ELabelW.Get(E) > 0) or Seen.ContainsKey(PairKey) then
                exit(2);
            Seen.Add(PairKey, true);
        end;
        exit(1);
    end;

    local procedure Upper(E: Integer): Integer
    begin
        if EReversed.Get(E) then
            exit(EHead.Get(E));
        exit(ETail.Get(E));
    end;

    local procedure Lower(E: Integer): Integer
    begin
        if EReversed.Get(E) then
            exit(ETail.Get(E));
        exit(EHead.Get(E));
    end;

    /// <summary>Reverses the edges that close a cycle, found by depth-first search in declaration order.</summary>
    local procedure Orient()
    var
        OutStart: List of [Integer];
        OutEdge: List of [Integer];
        Fill: List of [Integer];
        State: List of [Integer];
        Cursor: List of [Integer];
        Stack: List of [Integer];
        I: Integer;
        E: Integer;
        V: Integer;
        W: Integer;
        Root: Integer;
        M: Integer;
    begin
        M := ETail.Count();
        for I := 1 to RealCount + 1 do
            OutStart.Add(0);
        for E := 1 to M do
            OutStart.Set(ETail.Get(E) + 1, OutStart.Get(ETail.Get(E) + 1) + 1);
        for I := 2 to RealCount + 1 do
            OutStart.Set(I, OutStart.Get(I) + OutStart.Get(I - 1));
        // OutStart[v] is now the count before node v's run (0-based offset).
        for E := 1 to M do
            OutEdge.Add(0);
        for I := 1 to RealCount do
            Fill.Add(OutStart.Get(I));
        for E := 1 to M do begin
            V := ETail.Get(E);
            Fill.Set(V, Fill.Get(V) + 1);
            OutEdge.Set(Fill.Get(V), E);
        end;
        for I := 1 to RealCount do begin
            State.Add(0);
            Cursor.Add(OutStart.Get(I));
        end;
        for Root := 1 to RealCount do
            if State.Get(Root) = 0 then begin
                Stack.Add(Root);
                State.Set(Root, 1);
                while Stack.Count() > 0 do begin
                    V := Stack.Get(Stack.Count());
                    if Cursor.Get(V) < OutStart.Get(V + 1) then begin
                        Cursor.Set(V, Cursor.Get(V) + 1);
                        E := OutEdge.Get(Cursor.Get(V));
                        W := EHead.Get(E);
                        if State.Get(W) = 1 then
                            EReversed.Set(E, true)
                        else
                            if State.Get(W) = 0 then begin
                                State.Set(W, 1);
                                Stack.Add(W);
                            end;
                    end else begin
                        State.Set(V, 2);
                        Stack.RemoveAt(Stack.Count());
                    end;
                end;
            end;
    end;

    /// <summary>Longest-path ranking, then each node moves toward the side that has more edges.</summary>
    local procedure AssignRanks()
    var
        R: List of [Integer];
        InDeg: List of [Integer];
        Topo: List of [Integer];
        OutCnt: List of [Integer];
        InCnt: List of [Integer];
        I: Integer;
        E: Integer;
        V: Integer;
        Q: Integer;
        Pass: Integer;
        Len: Integer;
        Lo: Integer;
        Hi: Integer;
        NextRank: Integer;
        HasLo: Boolean;
        HasHi: Boolean;
        Changed: Boolean;
        MinR: Integer;
        Processed: Integer;
        M: Integer;
    begin
        M := ETail.Count();
        for I := 1 to RealCount do begin
            R.Add(0);
            InDeg.Add(0);
            OutCnt.Add(0);
            InCnt.Add(0);
        end;
        for E := 1 to M do begin
            InDeg.Set(Lower(E), InDeg.Get(Lower(E)) + 1);
            InCnt.Set(Lower(E), InCnt.Get(Lower(E)) + 1);
            OutCnt.Set(Upper(E), OutCnt.Get(Upper(E)) + 1);
        end;
        for I := 1 to RealCount do
            if InDeg.Get(I) = 0 then
                Topo.Add(I);
        Q := 1;
        while Q <= Topo.Count() do begin
            V := Topo.Get(Q);
            for E := 1 to M do
                if Upper(E) = V then begin
                    Len := EMinLen.Get(E) * RankStep;
                    if R.Get(V) + Len > R.Get(Lower(E)) then
                        R.Set(Lower(E), R.Get(V) + Len);
                    InDeg.Set(Lower(E), InDeg.Get(Lower(E)) - 1);
                    if InDeg.Get(Lower(E)) = 0 then
                        Topo.Add(Lower(E));
                end;
            Q += 1;
        end;
        Processed := Topo.Count();

        for Pass := 1 to 8 do begin
            Changed := false;
            for Q := Processed downto 1 do begin
                V := Topo.Get(Q);
                if (InCnt.Get(V) > 0) or (OutCnt.Get(V) > 0) then begin
                    HasLo := false;
                    HasHi := false;
                    Lo := 0;
                    Hi := 0;
                    for E := 1 to M do begin
                        Len := EMinLen.Get(E) * RankStep;
                        if Lower(E) = V then
                            if (not HasLo) or (R.Get(Upper(E)) + Len > Lo) then begin
                                Lo := R.Get(Upper(E)) + Len;
                                HasLo := true;
                            end;
                        if Upper(E) = V then
                            if (not HasHi) or (R.Get(Lower(E)) - Len < Hi) then begin
                                Hi := R.Get(Lower(E)) - Len;
                                HasHi := true;
                            end;
                    end;
                    NextRank := R.Get(V);
                    if (OutCnt.Get(V) > InCnt.Get(V)) and HasHi then
                        NextRank := Hi
                    else
                        if (InCnt.Get(V) > OutCnt.Get(V)) and HasLo then
                            NextRank := Lo;
                    if NextRank <> R.Get(V) then begin
                        R.Set(V, NextRank);
                        Changed := true;
                    end;
                end;
            end;
            if not Changed then
                break;
        end;

        MinR := R.Get(1);
        for I := 1 to RealCount do
            if R.Get(I) < MinR then
                MinR := R.Get(I);
        for I := 1 to RealCount do
            RankOf.Add(R.Get(I) - MinR);
    end;

    /// <summary>Cuts every edge into rank-to-rank segments, with a dummy node in each rank it passes and its label in one of them.</summary>
    local procedure BuildSegments()
    var
        E: Integer;
        A: Integer;
        B: Integer;
        Ra: Integer;
        Rb: Integer;
        LabelRank: Integer;
        R: Integer;
        Prev: Integer;
        D: Integer;
    begin
        MaxRank := 0;
        for A := 1 to RealCount do
            if RankOf.Get(A) > MaxRank then
                MaxRank := RankOf.Get(A);
        for E := 1 to ETail.Count() do begin
            A := Upper(E);
            B := Lower(E);
            Ra := RankOf.Get(A);
            Rb := RankOf.Get(B);
            LabelRank := -1;
            if ELabelW.Get(E) > 0 then begin
                // The label goes halfway along, in a rank between ranks of nodes where there is one.
                LabelRank := Ra + ((Rb - Ra) div 2);
                if (RankStep = 2) and (Rb - Ra >= 4) then begin
                    if LabelRank mod 2 = 1 then
                        if EReversed.Get(E) then
                            LabelRank += 1
                        else
                            LabelRank -= 1;
                end else
                    if (RankStep = 2) and (LabelRank mod 2 = 0) then
                        if EReversed.Get(E) then
                            LabelRank += 1
                        else
                            LabelRank -= 1;
            end;
            ELabelNode.Add(0);
            EFirstSeg.Add(SegFrom.Count() + 1);
            Prev := A;
            for R := Ra + 1 to Rb - 1 do begin
                if R = LabelRank then begin
                    NodeW.Add(ELabelW.Get(E));
                    NodeH.Add(ELabelH.Get(E));
                    Kind.Add(2);
                end else begin
                    NodeW.Add(0);
                    NodeH.Add(0);
                    Kind.Add(1);
                end;
                NodeSpan.Add(0);
                RankOf.Add(R);
                D := NodeW.Count();
                if R = LabelRank then
                    ELabelNode.Set(E, D);
                AddSegment(Prev, D);
                Prev := D;
            end;
            AddSegment(Prev, B);
            ELastSeg.Add(SegFrom.Count());
        end;
    end;

    local procedure AddSegment(FromNode: Integer; ToNode: Integer)
    begin
        SegFrom.Add(FromNode);
        SegTo.Add(ToNode);
        SegFromDx.Add(0);
        SegToDx.Add(0);
    end;

    local procedure NodeCount(): Integer
    begin
        exit(NodeW.Count());
    end;

    local procedure BuildAdjacency()
    var
        N: Integer;
        I: Integer;
        S: Integer;
        SFill: List of [Integer];
        PFill: List of [Integer];
    begin
        N := NodeCount();
        for I := 1 to N + 1 do begin
            SuccStart.Add(0);
            PredStart.Add(0);
        end;
        for S := 1 to SegFrom.Count() do begin
            SuccStart.Set(SegFrom.Get(S) + 1, SuccStart.Get(SegFrom.Get(S) + 1) + 1);
            PredStart.Set(SegTo.Get(S) + 1, PredStart.Get(SegTo.Get(S) + 1) + 1);
        end;
        for I := 2 to N + 1 do begin
            SuccStart.Set(I, SuccStart.Get(I) + SuccStart.Get(I - 1));
            PredStart.Set(I, PredStart.Get(I) + PredStart.Get(I - 1));
        end;
        for S := 1 to SegFrom.Count() do begin
            SuccSeg.Add(0);
            PredSeg.Add(0);
        end;
        for I := 1 to N do begin
            SFill.Add(SuccStart.Get(I));
            PFill.Add(PredStart.Get(I));
        end;
        for S := 1 to SegFrom.Count() do begin
            SFill.Set(SegFrom.Get(S), SFill.Get(SegFrom.Get(S)) + 1);
            SuccSeg.Set(SFill.Get(SegFrom.Get(S)), S);
            PFill.Set(SegTo.Get(S), PFill.Get(SegTo.Get(S)) + 1);
            PredSeg.Set(PFill.Get(SegTo.Get(S)), S);
        end;
    end;

    local procedure BuildLayers()
    var
        I: Integer;
        R: Integer;
    begin
        for R := 0 to MaxRank + 1 do
            LayerStart.Add(0);
        // LayerStart[r + 1] is the 0-based offset of rank r in Order.
        for I := 1 to NodeCount() do
            LayerStart.Set(RankOf.Get(I) + 2, LayerStart.Get(RankOf.Get(I) + 2) + 1);
        for R := 2 to MaxRank + 2 do
            LayerStart.Set(R, LayerStart.Get(R) + LayerStart.Get(R - 1));
        for I := 1 to NodeCount() do begin
            Order.Add(0);
            PosOf.Add(0);
            XPos.Add(0);
            YPos.Add(0);
        end;
    end;

    local procedure LayerFirst(R: Integer): Integer
    begin
        exit(LayerStart.Get(R + 1) + 1);
    end;

    local procedure LayerLast(R: Integer): Integer
    begin
        exit(LayerStart.Get(R + 2));
    end;

    local procedure SetPositions()
    var
        R: Integer;
        I: Integer;
    begin
        for R := 0 to MaxRank do
            for I := LayerFirst(R) to LayerLast(R) do
                PosOf.Set(Order.Get(I), I - LayerFirst(R));
    end;

    /// <summary>Initial order: depth-first from the top so that subtrees start out contiguous.</summary>
    local procedure InitialOrder()
    var
        ByRank: List of [Integer];
        Fill: List of [Integer];
        Visited: List of [Boolean];
        Stack: List of [Integer];
        I: Integer;
        K: Integer;
        V: Integer;
        W: Integer;
        J: Integer;
        R: Integer;
    begin
        for R := 0 to MaxRank do
            Fill.Add(LayerStart.Get(R + 1));
        for I := 1 to NodeCount() do
            ByRank.Add(0);
        for I := 1 to NodeCount() do begin
            R := RankOf.Get(I);
            Fill.Set(R + 1, Fill.Get(R + 1) + 1);
            ByRank.Set(Fill.Get(R + 1), I);
        end;
        for R := 0 to MaxRank do
            Fill.Set(R + 1, LayerStart.Get(R + 1));
        for I := 1 to NodeCount() do
            Visited.Add(false);
        for K := 1 to NodeCount() do
            if not Visited.Get(ByRank.Get(K)) then begin
                Stack.Add(ByRank.Get(K));
                while Stack.Count() > 0 do begin
                    V := Stack.Get(Stack.Count());
                    Stack.RemoveAt(Stack.Count());
                    if not Visited.Get(V) then begin
                        Visited.Set(V, true);
                        R := RankOf.Get(V);
                        Fill.Set(R + 1, Fill.Get(R + 1) + 1);
                        Order.Set(Fill.Get(R + 1), V);
                        for J := SuccStart.Get(V + 1) downto SuccStart.Get(V) + 1 do begin
                            W := SegTo.Get(SuccSeg.Get(J));
                            if not Visited.Get(W) then
                                Stack.Add(W);
                        end;
                    end;
                end;
            end;
        SetPositions();
    end;

    local procedure CountCrossings(): Integer
    var
        Total: Integer;
        R: Integer;
        I: Integer;
        J: Integer;
        S1: Integer;
        S2: Integer;
        Segs: List of [Integer];
        V: Integer;
        K: Integer;
    begin
        for R := 0 to MaxRank - 1 do begin
            Clear(Segs);
            for I := LayerFirst(R) to LayerLast(R) do begin
                V := Order.Get(I);
                for K := SuccStart.Get(V) + 1 to SuccStart.Get(V + 1) do
                    Segs.Add(SuccSeg.Get(K));
            end;
            for I := 1 to Segs.Count() do
                for J := I + 1 to Segs.Count() do begin
                    S1 := Segs.Get(I);
                    S2 := Segs.Get(J);
                    if (PosOf.Get(SegFrom.Get(S1)) - PosOf.Get(SegFrom.Get(S2))) * (PosOf.Get(SegTo.Get(S1)) - PosOf.Get(SegTo.Get(S2))) < 0 then
                        Total += 1;
                end;
        end;
        exit(Total);
    end;

    /// <summary>Barycenter sweeps, down and up in turn, keeping the order with the fewest crossings.</summary>
    local procedure ReduceCrossings()
    var
        Best: List of [Integer];
        Keys: List of [Decimal];
        BestCount: Integer;
        Current: Integer;
        Sweep: Integer;
        R: Integer;
        I: Integer;
        V: Integer;
        K: Integer;
        Sum: Decimal;
        Cnt: Integer;
        Down: Boolean;
        RFrom: Integer;
        RTo: Integer;
        RStep: Integer;
    begin
        Best := CopyIntList(Order);
        BestCount := CountCrossings();
        if BestCount = 0 then
            exit;
        for I := 1 to NodeCount() do
            Keys.Add(0);
        for Sweep := 1 to 24 do begin
            Down := Sweep mod 2 = 1;
            if Down then begin
                RFrom := 1;
                RTo := MaxRank;
                RStep := 1;
            end else begin
                RFrom := MaxRank - 1;
                RTo := 0;
                RStep := -1;
            end;
            R := RFrom;
            while ((RStep = 1) and (R <= RTo)) or ((RStep = -1) and (R >= RTo)) do begin
                for I := LayerFirst(R) to LayerLast(R) do begin
                    V := Order.Get(I);
                    Sum := 0;
                    Cnt := 0;
                    if Down then
                        for K := PredStart.Get(V) + 1 to PredStart.Get(V + 1) do begin
                            Sum += PosOf.Get(SegFrom.Get(PredSeg.Get(K)));
                            Cnt += 1;
                        end
                    else
                        for K := SuccStart.Get(V) + 1 to SuccStart.Get(V + 1) do begin
                            Sum += PosOf.Get(SegTo.Get(SuccSeg.Get(K)));
                            Cnt += 1;
                        end;
                    if Cnt > 0 then
                        Keys.Set(V, Sum / Cnt)
                    else
                        Keys.Set(V, PosOf.Get(V));
                end;
                SortLayer(R, Keys);
                R += RStep;
            end;
            Current := CountCrossings();
            if Current < BestCount then begin
                BestCount := Current;
                Best := CopyIntList(Order);
            end;
            if BestCount = 0 then
                break;
        end;
        Order := CopyIntList(Best);
        SetPositions();
    end;

    local procedure CopyIntList(var Source: List of [Integer]): List of [Integer]
    var
        Result: List of [Integer];
        V: Integer;
    begin
        foreach V in Source do
            Result.Add(V);
        exit(Result);
    end;

    /// <summary>A stable insertion sort of one layer by key, ties kept in their current order.</summary>
    local procedure SortLayer(R: Integer; var Keys: List of [Decimal])
    var
        I: Integer;
        J: Integer;
        Item: Integer;
        K: Decimal;
        First: Integer;
        Moving: Boolean;
    begin
        First := LayerFirst(R);
        for I := First + 1 to LayerLast(R) do begin
            Item := Order.Get(I);
            K := Keys.Get(Item);
            J := I - 1;
            Moving := true;
            while Moving do begin
                if J < First then
                    Moving := false
                else
                    if Keys.Get(Order.Get(J)) > K then begin
                        Order.Set(J + 1, Order.Get(J));
                        J -= 1;
                    end else
                        Moving := false;
            end;
            Order.Set(J + 1, Item);
        end;
        for I := First to LayerLast(R) do
            PosOf.Set(Order.Get(I), I - First);
    end;

    /// <summary>Gives the edges that meet one side of a node places of their own along it, around its middle.</summary>
    local procedure Spread()
    var
        Ids: List of [Integer];
        V: Integer;
        Side: Integer;
        K: Integer;
        Span: Decimal;
        Pitch: Decimal;
        Cnt: Integer;
    begin
        for V := 1 to RealCount do begin
            Span := MText.MinDec(NodeSpan.Get(V), NodeW.Get(V));
            if Span > 0 then
                for Side := 0 to 1 do begin
                    Clear(Ids);
                    if Side = 0 then begin
                        for K := PredStart.Get(V) + 1 to PredStart.Get(V + 1) do
                            Ids.Add(PredSeg.Get(K));
                        SortSegsByPos(Ids, true);
                    end else begin
                        for K := SuccStart.Get(V) + 1 to SuccStart.Get(V + 1) do
                            Ids.Add(SuccSeg.Get(K));
                        SortSegsByPos(Ids, false);
                    end;
                    Cnt := Ids.Count();
                    if Cnt >= 2 then begin
                        Pitch := MText.MinDec(16, Span / (Cnt - 1));
                        for K := 1 to Cnt do
                            if Side = 0 then
                                SegToDx.Set(Ids.Get(K), (K - 1 - (Cnt - 1) / 2) * Pitch)
                            else
                                SegFromDx.Set(Ids.Get(K), (K - 1 - (Cnt - 1) / 2) * Pitch);
                    end;
                end;
        end;
    end;

    local procedure SortSegsByPos(var Ids: List of [Integer]; ByFrom: Boolean)
    var
        I: Integer;
        J: Integer;
        Item: Integer;
        Moving: Boolean;
    begin
        for I := 2 to Ids.Count() do begin
            Item := Ids.Get(I);
            J := I - 1;
            Moving := true;
            while Moving do begin
                if J < 1 then
                    Moving := false
                else
                    if OtherPos(Ids.Get(J), ByFrom) > OtherPos(Item, ByFrom) then begin
                        Ids.Set(J + 1, Ids.Get(J));
                        J -= 1;
                    end else
                        Moving := false;
            end;
            Ids.Set(J + 1, Item);
        end;
    end;

    local procedure OtherPos(S: Integer; ByFrom: Boolean): Integer
    begin
        if ByFrom then
            exit(PosOf.Get(SegFrom.Get(S)));
        exit(PosOf.Get(SegTo.Get(S)));
    end;

    local procedure IsDummyKind(V: Integer): Boolean
    begin
        exit(Kind.Get(V) <> 0);
    end;

    /// <summary>The least distance between the centres of two neighbours in a rank.</summary>
    local procedure MinGap(U: Integer; V: Integer): Decimal
    var
        Sep: Decimal;
    begin
        if (Kind.Get(U) = 0) and (Kind.Get(V) = 0) then
            Sep := NodeSep
        else
            if (Kind.Get(U) = 1) and (Kind.Get(V) = 1) then
                Sep := EdgeSep
            else
                Sep := (NodeSep + EdgeSep) / 2;
        exit((NodeW.Get(U) + NodeW.Get(V)) / 2 + Sep);
    end;

    local procedure SegWeight(S: Integer): Decimal
    var
        A: Boolean;
        B: Boolean;
    begin
        A := IsDummyKind(SegFrom.Get(S));
        B := IsDummyKind(SegTo.Get(S));
        if A and B then
            exit(8);
        if A or B then
            exit(2);
        exit(1);
    end;

    /// <summary>
    /// X positions: each rank is packed, then fitted again and again to where its neighbours above, below,
    /// or both pull it, keeping the order and the least gaps (a weighted isotonic fit by pooling neighbours).
    /// </summary>
    local procedure AssignX()
    var
        R: Integer;
        I: Integer;
        Iter: Integer;
        X: Decimal;
        Prev: Integer;
    begin
        for R := 0 to MaxRank do begin
            X := 0;
            Prev := 0;
            for I := LayerFirst(R) to LayerLast(R) do begin
                if Prev <> 0 then
                    X += MinGap(Prev, Order.Get(I))
                else
                    X := NodeW.Get(Order.Get(I)) / 2;
                XPos.Set(Order.Get(I), X);
                Prev := Order.Get(I);
            end;
        end;
        if MaxRank = 0 then
            exit;
        for Iter := 1 to 8 do begin
            for R := 1 to MaxRank do
                FitLayer(R, true, false);
            for R := MaxRank - 1 downto 0 do
                FitLayer(R, false, true);
        end;
        for Iter := 1 to 3 do begin
            for R := 0 to MaxRank do
                FitLayer(R, true, true);
            for R := MaxRank downto 0 do
                FitLayer(R, true, true);
        end;
    end;

    local procedure FitLayer(R: Integer; UsePreds: Boolean; UseSuccs: Boolean)
    var
        Target: List of [Decimal];
        Weight: List of [Decimal];
        Offset: List of [Decimal];
        BlockSum: List of [Decimal];
        BlockWeight: List of [Decimal];
        BlockCount: List of [Integer];
        First: Integer;
        Last: Integer;
        I: Integer;
        K: Integer;
        V: Integer;
        S: Integer;
        Sum: Decimal;
        Wsum: Decimal;
        Wt: Decimal;
        Off: Decimal;
        Level: Decimal;
        B: Integer;
        C: Integer;
        Top: Integer;
        Merging: Boolean;
    begin
        First := LayerFirst(R);
        Last := LayerLast(R);
        if Last < First then
            exit;
        Off := 0;
        for I := First to Last do begin
            V := Order.Get(I);
            if I > First then
                Off += MinGap(Order.Get(I - 1), V);
            Offset.Add(Off);
            Sum := 0;
            Wsum := 0;
            if UsePreds then
                for K := PredStart.Get(V) + 1 to PredStart.Get(V + 1) do begin
                    S := PredSeg.Get(K);
                    Wt := SegWeight(S);
                    Sum += Wt * (XPos.Get(SegFrom.Get(S)) + SegFromDx.Get(S) - SegToDx.Get(S));
                    Wsum += Wt;
                end;
            if UseSuccs then
                for K := SuccStart.Get(V) + 1 to SuccStart.Get(V + 1) do begin
                    S := SuccSeg.Get(K);
                    Wt := SegWeight(S);
                    Sum += Wt * (XPos.Get(SegTo.Get(S)) + SegToDx.Get(S) - SegFromDx.Get(S));
                    Wsum += Wt;
                end;
            if Wsum > 0 then begin
                Target.Add(Sum / Wsum - Off);
                Weight.Add(Wsum);
            end else begin
                Target.Add(XPos.Get(V) - Off);
                Weight.Add(0.01);
            end;
        end;
        // Pool adjacent violators: blocks whose means would fall out of order are merged.
        for I := 1 to Target.Count() do begin
            BlockSum.Add(Target.Get(I) * Weight.Get(I));
            BlockWeight.Add(Weight.Get(I));
            BlockCount.Add(1);
            Merging := true;
            while Merging do begin
                Top := BlockSum.Count();
                if Top < 2 then
                    Merging := false
                else
                    if BlockSum.Get(Top - 1) / BlockWeight.Get(Top - 1) > BlockSum.Get(Top) / BlockWeight.Get(Top) then begin
                        BlockSum.Set(Top - 1, BlockSum.Get(Top - 1) + BlockSum.Get(Top));
                        BlockWeight.Set(Top - 1, BlockWeight.Get(Top - 1) + BlockWeight.Get(Top));
                        BlockCount.Set(Top - 1, BlockCount.Get(Top - 1) + BlockCount.Get(Top));
                        BlockSum.RemoveAt(Top);
                        BlockWeight.RemoveAt(Top);
                        BlockCount.RemoveAt(Top);
                    end else
                        Merging := false;
            end;
        end;
        I := 0;
        for B := 1 to BlockSum.Count() do begin
            Level := BlockSum.Get(B) / BlockWeight.Get(B);
            for C := 1 to BlockCount.Get(B) do begin
                I += 1;
                XPos.Set(Order.Get(First + I - 1), Level + Offset.Get(I));
            end;
        end;
    end;

    local procedure Normalize()
    var
        I: Integer;
        MinX: Decimal;
        MaxX: Decimal;
    begin
        MinX := XPos.Get(1) - NodeW.Get(1) / 2;
        MaxX := XPos.Get(1) + NodeW.Get(1) / 2;
        for I := 1 to NodeCount() do begin
            if XPos.Get(I) - NodeW.Get(I) / 2 < MinX then
                MinX := XPos.Get(I) - NodeW.Get(I) / 2;
            if XPos.Get(I) + NodeW.Get(I) / 2 > MaxX then
                MaxX := XPos.Get(I) + NodeW.Get(I) / 2;
        end;
        for I := 1 to NodeCount() do
            XPos.Set(I, XPos.Get(I) - MinX);
        ResultWidth := MaxX - MinX;
    end;

    /// <summary>Stacks the ranks into bands. A gap grows to keep edges that run far across it at a clear slope.</summary>
    local procedure AssignY()
    var
        GapUnder: List of [Decimal];
        RunAcross: List of [Decimal];
        Heads: List of [Integer];
        Between: List of [Boolean];
        Arrives: List of [Boolean];
        Leaves: List of [Boolean];
        R: Integer;
        I: Integer;
        S: Integer;
        E: Integer;
        V: Integer;
        Across: Decimal;
        Usual: Decimal;
        Y: Decimal;
        H: Decimal;
        Shift: Decimal;
    begin
        for R := 0 to MaxRank do begin
            GapUnder.Add(0);
            RunAcross.Add(0);
            Heads.Add(0);
            Between.Add(true);
            Arrives.Add(false);
            Leaves.Add(false);
            BandTop.Add(0);
            BandBottom.Add(0);
        end;
        for S := 1 to SegFrom.Count() do begin
            Across := Abs(XPos.Get(SegFrom.Get(S)) + SegFromDx.Get(S) - XPos.Get(SegTo.Get(S)) - SegToDx.Get(S));
            R := RankOf.Get(SegFrom.Get(S));
            if Across > RunAcross.Get(R + 1) then
                RunAcross.Set(R + 1, Across);
        end;
        for E := 1 to ETail.Count() do
            if ELabelNode.Get(E) > 0 then begin
                R := RankOf.Get(ELabelNode.Get(E));
                if EReversed.Get(E) then begin
                    if Heads.Get(R + 1) mod 4 < 2 then
                        Heads.Set(R + 1, Heads.Get(R + 1) + 2);
                end else
                    if Heads.Get(R + 1) mod 2 = 0 then
                        Heads.Set(R + 1, Heads.Get(R + 1) + 1);
            end;
        for I := 1 to RealCount do
            Between.Set(RankOf.Get(I) + 1, false);
        Usual := RankSep / RankStep;
        for R := 0 to MaxRank - 1 do
            GapUnder.Set(R + 1, MText.MaxDec(Usual, MText.MinDec(3 * RankSep / RankStep, RunAcross.Get(R + 1) * 0.125)));
        // A rank of labels whose edges all head the same way sits half the arrowhead nearer their tails.
        for R := 1 to MaxRank - 1 do
            if Between.Get(R + 1) and ((Heads.Get(R + 1) = 1) or (Heads.Get(R + 1) = 2)) then begin
                if Heads.Get(R + 1) = 1 then
                    Shift := MText.MinDec(HeadRoom / 2, GapUnder.Get(R) / 2)
                else
                    Shift := MText.MinDec(HeadRoom / 2, GapUnder.Get(R + 1) / 2);
                if Heads.Get(R + 1) = 1 then begin
                    GapUnder.Set(R, GapUnder.Get(R) - Shift);
                    GapUnder.Set(R + 1, GapUnder.Get(R + 1) + Shift);
                end else begin
                    GapUnder.Set(R, GapUnder.Get(R) + Shift);
                    GapUnder.Set(R + 1, GapUnder.Get(R + 1) - Shift);
                end;
            end;
        Y := 0;
        for R := 0 to MaxRank do begin
            H := 0;
            for I := LayerFirst(R) to LayerLast(R) do
                if NodeH.Get(Order.Get(I)) > H then
                    H := NodeH.Get(Order.Get(I));
            BandTop.Set(R + 1, Y);
            BandBottom.Set(R + 1, Y + H);
            Y += H + GapUnder.Get(R + 1);
        end;
        ResultHeight := Y;
        // A rank whose nodes only send edges on stands on one line, one whose nodes only receive hangs from one.
        for V := 1 to RealCount do begin
            if PredStart.Get(V + 1) > PredStart.Get(V) then
                Arrives.Set(RankOf.Get(V) + 1, true);
            if SuccStart.Get(V + 1) > SuccStart.Get(V) then
                Leaves.Set(RankOf.Get(V) + 1, true);
        end;
        for V := 1 to NodeCount() do begin
            R := RankOf.Get(V) + 1;
            if (V <= RealCount) and Leaves.Get(R) and not Arrives.Get(R) then
                YPos.Set(V, BandBottom.Get(R) - NodeH.Get(V) / 2)
            else
                if (V <= RealCount) and Arrives.Get(R) and not Leaves.Get(R) then
                    YPos.Set(V, BandTop.Get(R) + NodeH.Get(V) / 2)
                else
                    YPos.Set(V, (BandTop.Get(R) + BandBottom.Get(R)) / 2);
        end;
    end;

    /// <summary>A rank that holds nothing but the bends of edges.</summary>
    local procedure IsEmptyRank(R: Integer): Boolean
    var
        I: Integer;
    begin
        for I := LayerFirst(R) to LayerLast(R) do
            if Kind.Get(Order.Get(I)) <> 1 then
                exit(false);
        exit(true);
    end;

    local procedure BuildRoutes()
    var
        Xs: List of [Decimal];
        Ys: List of [Decimal];
        EmptyRank: List of [Boolean];
        BetweenRank: List of [Boolean];
        E: Integer;
        S: Integer;
        D: Integer;
        R: Integer;
        A: Integer;
        B: Integer;
        I: Integer;
        J: Integer;
        Top: Decimal;
        Bottom: Decimal;
        Inset: Decimal;
        T: Decimal;
    begin
        for R := 0 to MaxRank do begin
            EmptyRank.Add(IsEmptyRank(R));
            BetweenRank.Add(true);
        end;
        for I := 1 to RealCount do
            BetweenRank.Set(RankOf.Get(I) + 1, false);
        for E := 1 to ETail.Count() do begin
            Clear(Xs);
            Clear(Ys);
            A := Upper(E);
            B := Lower(E);
            Xs.Add(XPos.Get(A) + SegFromDx.Get(EFirstSeg.Get(E)));
            Ys.Add(YPos.Get(A) + NodeH.Get(A) / 2);
            for S := EFirstSeg.Get(E) to ELastSeg.Get(E) - 1 do begin
                D := SegTo.Get(S);
                R := RankOf.Get(D);
                if not EmptyRank.Get(R + 1) then begin
                    Top := BandTop.Get(R + 1);
                    Bottom := BandBottom.Get(R + 1);
                    Inset := 0;
                    if (Kind.Get(D) = 1) and BetweenRank.Get(R + 1) then
                        Inset := (Bottom - Top) / 4;
                    Xs.Add(XPos.Get(D));
                    Ys.Add(Top + Inset);
                    if Bottom > Top then begin
                        Xs.Add(XPos.Get(D));
                        Ys.Add(Bottom - Inset);
                    end;
                end;
            end;
            Xs.Add(XPos.Get(B) + SegToDx.Get(ELastSeg.Get(E)));
            Ys.Add(YPos.Get(B) - NodeH.Get(B) / 2);
            if EReversed.Get(E) then begin
                I := 1;
                J := Xs.Count();
                while I < J do begin
                    T := Xs.Get(I);
                    Xs.Set(I, Xs.Get(J));
                    Xs.Set(J, T);
                    T := Ys.Get(I);
                    Ys.Set(I, Ys.Get(J));
                    Ys.Set(J, T);
                    I += 1;
                    J -= 1;
                end;
            end;
            EPtStart.Add(PtX.Count() + 1);
            EPtCount.Add(Xs.Count());
            for I := 1 to Xs.Count() do begin
                PtX.Add(Xs.Get(I));
                PtY.Add(Ys.Get(I));
            end;
            D := ELabelNode.Get(E);
            if D > 0 then begin
                ELabelX.Add(XPos.Get(D));
                R := RankOf.Get(D);
                ELabelY.Add((BandTop.Get(R + 1) + BandBottom.Get(R + 1)) / 2);
            end else begin
                ELabelX.Add((Xs.Get(1) + Xs.Get(Xs.Count())) / 2);
                ELabelY.Add((Ys.Get(1) + Ys.Get(Ys.Count())) / 2);
            end;
        end;
    end;
}
