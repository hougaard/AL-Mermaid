/// <summary>
/// Port of pele's diagrams/mindmap: the indented outline grammar of common/outline.ts (tokenizer and
/// parser, without kanban's shape data), db.ts (nodes, parents by indentation, sections) and render.ts
/// (branches spreading right and left of the root, shaped or plain nodes tinted by branch).
/// Icons (::icon(...)) are parsed and ignored, as pele does for an icon the host does not have.
/// pele's responsive outline layout (turnToFit) is left out: a map is always drawn across.
/// </summary>
codeunit 68918 "Mermaid Mindmap"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Shapes: Codeunit "Mermaid Shapes";
        Src: Text;
        // Tokens.
        TType: List of [Integer];
        TText: List of [Text];
        TStart: List of [Integer];
        // Nodes, in source order (depth first); the first is the root. Indices are 1-based.
        NId: List of [Text];
        NLevel: List of [Integer];
        NDescr: List of [Text];
        NType: List of [Integer];
        NSect: List of [Integer];
        NClass: List of [Text];
        NParent: List of [Integer];
        NChildCount: List of [Integer];
        ChildStart: List of [Integer];
        ChildFlat: List of [Integer];
        OpenChain: List of [Integer];
        BaseLevel: Integer;
        MapTitle: Text;
        // Layout.
        NodeW: List of [Decimal];
        NodeH: List of [Decimal];
        NodeDy: List of [Decimal];
        Anchor: List of [Decimal];
        Extent: List of [Decimal];
        Rel: List of [Decimal];
        Own: List of [Decimal];
        Kids: List of [Decimal];
        Stacked: Decimal;

    // ---------------------------------------------------------------- token types (outline.ts T)
    // 0 END, 1 ERROR, 2 SPACELINE, 3 NL, 4 EOF, 5 KEYWORD, 6 SPACELIST, 7 ICON, 8 CLASS,
    // 9 NODE_DSTART, 10 NODE_ID, 11 NODE_DESCR, 12 NODE_DEND.
    // Tokenizer states: 0 INITIAL, 1 CLASS, 2 ICON, 3 NODE, 4 NSTR, 5 NSTR2.

    local procedure TokenName(TokenType: Integer): Text
    begin
        case TokenType of
            0:
                exit('1');
            1:
                exit('INVALID');
            2:
                exit('SPACELINE');
            3:
                exit('NL');
            4:
                exit('EOF');
            5:
                exit('MINDMAP');
            6:
                exit('SPACELIST');
            7:
                exit('ICON');
            8:
                exit('CLASS');
            9:
                exit('NODE_DSTART');
            10:
                exit('NODE_ID');
            11:
                exit('NODE_DESCR');
            12:
                exit('NODE_DEND');
        end;
        exit('undefined');
    end;

    // ---------------------------------------------------------------- tokenizer

    /// <summary>Jison's case-insensitive flag folds ASCII letters only. Word is lower case.</summary>
    local procedure Letters(P: Integer; Word: Text): Boolean
    var
        K: Integer;
        C: Integer;
        Wc: Integer;
    begin
        for K := 1 to StrLen(Word) do begin
            C := MText.CharAt(Src, P + K - 1);
            Wc := Word[K];
            if (C <> Wc) and (C <> Wc - 32) then
                exit(false);
        end;
        exit(true);
    end;

    /// <summary>Where `.+` from P ends: at the next line terminator or the end.</summary>
    local procedure LineEndFrom(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        while (C <> -1) and not MText.IsLineEnd(C) do begin
            P += 1;
            C := MText.CharAt(Src, P);
        end;
        exit(P);
    end;

    local procedure UpTo(P: Integer; Ch: Text): Integer
    var
        E: Integer;
    begin
        E := MText.IndexOfFrom(Src, Ch, P);
        if E = 0 then
            exit(StrLen(Src) + 1);
        exit(E);
    end;

    local procedure IdEnd(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        while (C <> -1) and not (C in [40, 91, 10, 41, 123, 125]) do begin
            P += 1;
            C := MText.CharAt(Src, P);
        end;
        exit(P);
    end;

    local procedure DescrEnd(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        while (C <> -1) and not (C in [41, 93, 40, 125]) do begin
            P += 1;
            C := MText.CharAt(Src, P);
        end;
        exit(P);
    end;

    local procedure MdEnd(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        while (C <> -1) and (C <> 96) and (C <> 34) do begin
            P += 1;
            C := MText.CharAt(Src, P);
        end;
        exit(P);
    end;

    local procedure Put(TokenType: Integer; Value: Text; Start: Integer)
    begin
        TType.Add(TokenType);
        TText.Add(Value);
        TStart.Add(Start);
    end;

    local procedure Emit(TokenType: Integer; var P: Integer; EndPos: Integer; var State: Integer; NextState: Integer)
    begin
        Put(TokenType, MText.Substr(Src, P, EndPos), P);
        P := EndPos;
        State := NextState;
    end;

    local procedure Tokenize()
    var
        N: Integer;
        P: Integer;
        W: Integer;
        E: Integer;
        C: Integer;
        D: Integer;
        State: Integer;
        NextBreak: Integer;
        Stuck: Boolean;
    begin
        Clear(TType);
        Clear(TText);
        Clear(TStart);
        N := StrLen(Src);
        P := 1;
        State := 0;
        NextBreak := -1;
        while (P <= N) and not Stuck do begin
            C := MText.CharAt(Src, P);
            D := MText.CharAt(Src, P + 1);
            case State of
                0:
                    begin
                        W := P;
                        if (C <= 32) or (C >= 160) then
                            while MText.IsSpace(MText.CharAt(Src, W)) do
                                W += 1;
                        if (MText.CharAt(Src, W) = 37) and (MText.CharAt(Src, W + 1) = 37) then
                            Emit(2, P, LineEndFrom(W), State, 0)
                        else
                            if W > P then begin
                                if NextBreak < P then
                                    NextBreak := UpTo(P, MText.LF());
                                if NextBreak >= W then
                                    Emit(6, P, W, State, 0)
                                else begin
                                    E := W - 1;
                                    while (E > P) and (MText.CharAt(Src, E) <> 10) do
                                        E -= 1;
                                    if E > P then
                                        Emit(2, P, E + 1, State, 0)
                                    else
                                        Emit(3, P, P + 1, State, 0);
                                end;
                            end else
                                if Letters(P, 'mindmap') and not MText.IsWord(MText.CharAt(Src, P + 7)) then
                                    Emit(5, P, P + 7, State, 0)
                                else
                                    if (C = 58) and (D = 58) and (MText.CharAt(Src, P + 2) = 58) then begin
                                        P += 3;
                                        State := 1;
                                    end else
                                        if (C = 58) and (D = 58) and Letters(P + 2, 'icon') and (MText.CharAt(Src, P + 6) = 40) then begin
                                            P += 7;
                                            State := 2;
                                        end else
                                            if ((C = 45) and (D = 41)) or ((C = 40) and ((D = 45) or (D = 40))) or (((C = 41) or (C = 123)) and (D = C)) then
                                                Emit(9, P, P + 2, State, 3)
                                            else
                                                if C in [41, 40, 91] then
                                                    Emit(9, P, P + 1, State, 3)
                                                else begin
                                                    E := IdEnd(P);
                                                    if E > P then
                                                        Emit(10, P, E, State, 0)
                                                    else
                                                        Stuck := true;
                                                end;
                    end;
                3:
                    if C = 34 then begin
                        if D = 96 then begin
                            State := 5;
                            P += 2;
                        end else begin
                            State := 4;
                            P += 1;
                        end;
                    end else
                        if (C = 41) or (C = 40) then begin
                            if (D = C) or ((C = 40) and (D = 45)) then
                                Emit(12, P, P + 2, State, 0)
                            else
                                Emit(12, P, P + 1, State, 0);
                        end else
                            if C = 93 then
                                Emit(12, P, P + 1, State, 0)
                            else
                                if ((C = 125) and (D = 125)) or ((C = 45) and (D = 41)) then
                                    Emit(12, P, P + 2, State, 0)
                                else
                                    if C = 125 then
                                        // A lone closing brace takes the rest of its line as text.
                                        Emit(11, P, LineEndFrom(P), State, 3)
                                    else
                                        Emit(11, P, DescrEnd(P), State, 3);
                4:
                    if C = 34 then begin
                        P += 1;
                        State := 3;
                    end else
                        Emit(11, P, UpTo(P, '"'), State, 4);
                5:
                    if (C = 96) and (D = 34) then begin
                        P += 2;
                        State := 3;
                    end else begin
                        E := MdEnd(P);
                        if E > P then
                            Emit(11, P, E, State, 5)
                        else
                            Stuck := true;
                    end;
                1:
                    begin
                        E := LineEndFrom(P);
                        if E > P then
                            Emit(8, P, E, State, 0)
                        else
                            if C = 10 then begin
                                P += 1;
                                State := 0;
                            end else
                                Stuck := true;
                    end;
                2:
                    if C = 41 then begin
                        P += 1;
                        State := 0;
                    end else
                        Emit(7, P, UpTo(P, ')'), State, 2);
            end;
        end;

        if P <= N then
            Put(1, '', P)
        else begin
            if State = 0 then
                Put(4, '', N + 1);
            Put(0, '', N + 1);
        end;
    end;

    // ---------------------------------------------------------------- parser

    local procedure TypeAt(I: Integer): Integer
    begin
        if (I < 1) or (I > TType.Count()) then
            exit(-1);
        exit(TType.Get(I));
    end;

    local procedure IsStop(TokenType: Integer): Boolean
    begin
        exit(TokenType in [2, 3, 4]);
    end;

    local procedure IsStart(TokenType: Integer): Boolean
    begin
        exit(TokenType in [2, 6, 7, 8, 9, 10]);
    end;

    local procedure Fail(I: Integer; Expected: Text)
    var
        TokenType: Integer;
        Start: Integer;
    begin
        TokenType := TypeAt(I);
        Start := StrLen(Src) + 1;
        if (I >= 1) and (I <= TStart.Count()) then
            Start := TStart.Get(I);
        if TokenType = 1 then
            MText.SyntaxError('mindmap', Src, Start, '', true);
        MText.SyntaxError('mindmap', Src, Start, 'Expecting ' + Expected + ', got ''' + TokenName(TokenType) + '''', false);
    end;

    local procedure GetType(StartText: Text; EndText: Text): Integer
    begin
        case StartText of
            '[':
                exit(2);
            '(':
                begin
                    if EndText = ')' then
                        exit(1);
                    exit(4);
                end;
            '((':
                exit(3);
            ')':
                exit(4);
            '))':
                exit(5);
            '{{':
                exit(6);
        end;
        exit(0);
    end;

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    var
        StopNames: Text;
        First: Text;
        Id: Text;
        Descr: Text;
        StartText: Text;
        EndText: Text;
        Value: Text;
        I: Integer;
        T: Integer;
        Level: Integer;
        NodeType: Integer;
        Indented: Boolean;
        HasId: Boolean;
    begin
        Src := Source;
        MapTitle := FrontTitle;
        Clear(NId);
        Clear(NLevel);
        Clear(NDescr);
        Clear(NType);
        Clear(NSect);
        Clear(NClass);
        Clear(NParent);
        Clear(NChildCount);
        Clear(OpenChain);
        BaseLevel := 0;
        Tokenize();

        StopNames := '''SPACELINE'', ''NL'', ''EOF''';
        I := 1;
        if TypeAt(I) = 2 then begin
            I += 1;
            while TypeAt(I) in [2, 3] do
                I += 1;
            if TypeAt(I) <> 5 then
                Fail(I, '''SPACELINE'', ''NL'', ''MINDMAP''');
        end else
            if TypeAt(I) <> 5 then
                Fail(I, '''SPACELINE'', ''MINDMAP''');
        I += 1;
        First := '''SPACELINE'', ''NL'', ''SPACELIST'', ''ICON'', ''CLASS'', ''NODE_DSTART'', ''NODE_ID''';
        if TypeAt(I) = 3 then begin
            I += 1;
            First := '''SPACELINE'', ''SPACELIST'', ''ICON'', ''CLASS'', ''NODE_DSTART'', ''NODE_ID''';
        end;

        repeat
            T := TypeAt(I);
            Level := 0;
            Indented := T = 6;
            if Indented then begin
                Level := StrLen(TText.Get(I));
                I += 1;
                T := TypeAt(I);
            end;
            if T in [10, 9] then begin
                HasId := false;
                Id := '';
                NodeType := 0;
                if T = 10 then begin
                    Id := TText.Get(I);
                    HasId := true;
                    I += 1;
                end;
                if TypeAt(I) = 9 then begin
                    StartText := TText.Get(I);
                    I += 1;
                    if TypeAt(I) <> 11 then
                        Fail(I, '''NODE_DESCR''');
                    Descr := TText.Get(I);
                    I += 1;
                    if TypeAt(I) <> 12 then
                        Fail(I, '''NODE_DEND''');
                    EndText := TText.Get(I);
                    I += 1;
                    if not IsStop(TypeAt(I)) then
                        Fail(I, StopNames);
                    NodeType := GetType(StartText, EndText);
                end else begin
                    if not IsStop(TypeAt(I)) then
                        Fail(I, StopNames + ', ''NODE_DSTART''');
                    Descr := Id;
                end;
                if not HasId then
                    Id := Descr;
                AddNode(Level, Id, Descr, NodeType);
            end else
                if T in [7, 8] then begin
                    Value := TText.Get(I);
                    I += 1;
                    if not IsStop(TypeAt(I)) then
                        Fail(I, StopNames);
                    // Icons are not drawn; a class decorates the latest node.
                    if T = 8 then
                        if (Value <> '') and (NId.Count() > 0) then
                            NClass.Set(NId.Count(), Value);
                end else
                    if Indented then begin
                        if not IsStop(T) then
                            Fail(I, StopNames + ', ''ICON'', ''CLASS'', ''NODE_DSTART'', ''NODE_ID''');
                    end else
                        if T = 2 then begin
                            I += 1;
                            if not IsStop(TypeAt(I)) then
                                Fail(I, StopNames);
                        end else
                            Fail(I, First);

            I += 1;
            while TypeAt(I) in [3, 4] do
                I += 1;
            if TypeAt(I) = 0 then
                break;
            if not IsStart(TypeAt(I)) then
                Fail(I, StopNames + ', ''SPACELIST'', ''ICON'', ''CLASS'', ''NODE_DSTART'', ''NODE_ID''');
        until false;

        BuildChildren();
    end;

    /// <summary>Mermaid's parent is the last node with a smaller indentation, wherever it is in the tree.</summary>
    local procedure AddNode(Level: Integer; Id: Text; Descr: Text; NodeType: Integer)
    var
        IsRoot: Boolean;
        Depth: Integer;
        Parent: Integer;
        Sect: Integer;
        Idx: Integer;
    begin
        IsRoot := NId.Count() = 0;
        if IsRoot then
            BaseLevel := Level;
        Level -= BaseLevel;
        Depth := OpenChain.Count();
        while Depth > 0 do begin
            if NLevel.Get(OpenChain.Get(Depth)) < Level then
                break;
            Depth -= 1;
        end;
        Parent := 0;
        if Depth > 0 then
            Parent := OpenChain.Get(Depth);
        if (Parent = 0) and not IsRoot then
            MText.Fail('There can be only one root. No parent could be found for ("' + Descr + '")');
        Sect := -1;
        if Parent <> 0 then begin
            if Parent = 1 then
                Sect := NChildCount.Get(Parent) mod 11
            else
                Sect := NSect.Get(Parent);
            NChildCount.Set(Parent, NChildCount.Get(Parent) + 1);
        end;
        NId.Add(Id);
        NLevel.Add(Level);
        NDescr.Add(Descr);
        NType.Add(NodeType);
        NSect.Add(Sect);
        NClass.Add('');
        NParent.Add(Parent);
        NChildCount.Add(0);
        Idx := NId.Count();
        while OpenChain.Count() > Depth do
            OpenChain.RemoveAt(OpenChain.Count());
        OpenChain.Add(Idx);
    end;

    local procedure BuildChildren()
    var
        Fill: List of [Integer];
        I: Integer;
        At: Integer;
        P: Integer;
    begin
        Clear(ChildStart);
        Clear(ChildFlat);
        At := 1;
        for I := 1 to NId.Count() do begin
            ChildStart.Add(At);
            Fill.Add(At);
            At += NChildCount.Get(I);
        end;
        for I := 1 to At - 1 do
            ChildFlat.Add(0);
        for I := 2 to NId.Count() do begin
            P := NParent.Get(I);
            ChildFlat.Set(Fill.Get(P), I);
            Fill.Set(P, Fill.Get(P) + 1);
        end;
    end;

    /// <summary>The K-th child (0-based) of a node.</summary>
    local procedure ChildAt(Node: Integer; K: Integer): Integer
    begin
        exit(ChildFlat.Get(ChildStart.Get(Node) + K));
    end;

    // ---------------------------------------------------------------- rendering (render.ts)

    local procedure ShapeOf(NodeType: Integer): Text
    begin
        case NodeType of
            1:
                exit('rounded');
            2:
                exit('rect');
            3:
                exit('circle');
            4:
                exit('cloud');
            5:
                exit('bang');
            6:
                exit('hex');
        end;
        exit('');
    end;

    local procedure HasChildren(Node: Integer): Boolean
    begin
        exit(NChildCount.Get(Node) > 0);
    end;

    /// <summary>Stacks subtrees top to bottom and returns the height at which their parent's anchor belongs.</summary>
    local procedure Stack(Parent: Integer; FromK: Integer; ToK: Integer; Gap: Decimal): Decimal
    var
        Y: Decimal;
        Last: Decimal;
        K: Integer;
        C: Integer;
        A: Integer;
        B: Integer;
        Grouped: Boolean;
    begin
        Y := 0;
        Last := 0;
        for K := FromK to ToK - 1 do begin
            C := ChildAt(Parent, K);
            Rel.Set(C, Y);
            Grouped := HasChildren(C);
            if not Grouped then
                if K + 1 < ToK then
                    Grouped := HasChildren(ChildAt(Parent, K + 1));
            // GROUP_GAP is 18: between two subtrees of which at least one has children of its own.
            if Grouped then
                Last := MText.MaxDec(Gap, 18)
            else
                Last := Gap;
            Y += Extent.Get(C) + Last;
        end;
        Stacked := Y - Last;
        A := ChildAt(Parent, FromK);
        B := ChildAt(Parent, ToK - 1);
        exit((Rel.Get(A) + Own.Get(A) + Anchor.Get(A) + Rel.Get(B) + Own.Get(B) + Anchor.Get(B)) / 2);
    end;

    local procedure Zeros(var Values: List of [Decimal]; N: Integer)
    var
        I: Integer;
    begin
        Clear(Values);
        for I := 1 to N do
            Values.Add(0);
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        Lbl: Codeunit "Mermaid Label";
        TitleLbl: Codeunit "Mermaid Label";
        ShapeNames: List of [Text];
        X: List of [Decimal];
        Y: List of [Decimal];
        Band: List of [Decimal];
        Side: List of [Decimal];
        Out: TextBuilder;
        Edges: TextBuilder;
        Body: TextBuilder;
        Size: Decimal;
        Pad: Decimal;
        Wrap: Decimal;
        MaxNodeWidth: Decimal;
        Tw: Decimal;
        Th: Decimal;
        Sw: Decimal;
        Sh: Decimal;
        Sdy: Decimal;
        Top: Decimal;
        Low: Decimal;
        Total: Decimal;
        Best: Decimal;
        Right: Decimal;
        Diff: Decimal;
        Middle: Decimal;
        Dir: Decimal;
        Cx: Decimal;
        X1: Decimal;
        Y1: Decimal;
        X2: Decimal;
        Y2: Decimal;
        Near: Decimal;
        MinX: Decimal;
        MaxX: Decimal;
        MinY: Decimal;
        MaxY: Decimal;
        TitleHeight: Decimal;
        Width: Decimal;
        TotalWidth: Integer;
        TotalHeight: Integer;
        N: Integer;
        I: Integer;
        K: Integer;
        C: Integer;
        P: Integer;
        Idx: Integer;
        Count0: Integer;
        Split: Integer;
        FromK: Integer;
        ToK: Integer;
        FromSide: Integer;
        Shape: Text;
        Color: Text;
        Tint: Text;
        Inner: Text;
        ShapeClass: Text;
        RootClass: Text;
        Group: Text;
        Mid: Text;
        Content: Text;
        Pill: Boolean;
    begin
        Size := MText.FontSize();
        Pad := 8;
        Wrap := 200;
        if MText.ConfigNumber(Config, 'mindmap.maxNodeWidth', MaxNodeWidth) then
            if MaxNodeWidth > 0 then
                Wrap := MText.MinDec(MaxNodeWidth, 2000);

        N := NId.Count();
        Zeros(NodeW, N);
        Zeros(NodeH, N);
        Zeros(NodeDy, N);
        Zeros(Anchor, N);
        Zeros(Extent, N);
        Zeros(Rel, N);
        Zeros(Own, N);
        Zeros(Kids, N);
        Zeros(X, N);
        Zeros(Y, N);
        Zeros(Band, N);
        Zeros(Side, N);

        for I := 1 to N do begin
            Lbl.Layout(NDescr.Get(I), true, Size, Wrap, 0);
            Tw := Lbl.GetWidth();
            Th := MText.MaxDec(Lbl.GetHeight(), Round(Size * 1.5, 1));
            Shape := ShapeOf(NType.Get(I));
            if (Shape = '') and (I = 1) then
                Shape := 'stadium';
            ShapeNames.Add(Shape);
            if Shape = '' then begin
                // A node with no shape of its own is plain text when it ends a branch, and text in a
                // tinted pill when the branch goes on from it, which sets the levels apart.
                Pill := HasChildren(I);
                if Pill then begin
                    NodeW.Set(I, Tw + 2 * 12);
                    NodeH.Set(I, Th + 6);
                end else begin
                    NodeW.Set(I, Tw + 2 * 6);
                    NodeH.Set(I, Th);
                end;
                Anchor.Set(I, NodeH.Get(I) / 2);
            end else begin
                Shapes.GetSize(Shape, Tw, Th, Sw, Sh, Sdy);
                NodeW.Set(I, Sw);
                NodeH.Set(I, Sh);
                NodeDy.Set(I, Sdy);
                Anchor.Set(I, Sh / 2);
            end;
        end;

        // Nodes are in depth-first order, so going backwards visits children before their parent.
        for I := N downto 2 do
            if not HasChildren(I) then
                Extent.Set(I, NodeH.Get(I))
            else begin
                // GAP_Y is 8.
                Top := Stack(I, 0, NChildCount.Get(I), 8) - Anchor.Get(I);
                Low := MText.MinDec(0, Top);
                Extent.Set(I, MText.MaxDec(Stacked, Top + NodeH.Get(I)) - Low);
                Own.Set(I, Top - Low);
                Kids.Set(I, -Low);
            end;

        if N > 0 then begin
            // The first branches go right and the rest left, split where the two sides are closest in height.
            Count0 := NChildCount.Get(1);
            Total := 0;
            for K := 0 to Count0 - 1 do
                Total += Extent.Get(ChildAt(1, K));
            Split := Count0;
            Best := 0;
            Right := 0;
            for K := 1 to Count0 - 1 do begin
                Right += Extent.Get(ChildAt(1, K - 1));
                // BRANCH_GAP_Y is 28.
                Diff := Abs(2 * Right - Total + (2 * K - Count0) * 28);
                if (K = 1) or (Diff < Best) then begin
                    Best := Diff;
                    Split := K;
                end;
            end;
            FromK := 0;
            ToK := Split;
            Dir := 1;
            while FromK < Count0 do begin
                Middle := Stack(1, FromK, ToK, 28);
                for K := FromK to ToK - 1 do begin
                    C := ChildAt(1, K);
                    Band.Set(C, Rel.Get(C) - Middle);
                    Side.Set(C, Dir);
                end;
                FromK := ToK;
                ToK := Count0;
                Dir := -1;
            end;
            Y.Set(1, -NodeH.Get(1) / 2);
            for I := 1 to N do begin
                if I > 1 then
                    Y.Set(I, Band.Get(I) + Own.Get(I));
                for K := 0 to NChildCount.Get(I) - 1 do begin
                    C := ChildAt(I, K);
                    if I > 1 then begin
                        Side.Set(C, Side.Get(I));
                        Band.Set(C, Band.Get(I) + Kids.Get(I) + Rel.Get(C));
                    end;
                    // GAP_X is 36 and BRANCH_GAP_X 52.
                    if I > 1 then
                        X.Set(C, X.Get(I) + Side.Get(C) * (NodeW.Get(I) / 2 + 36 + NodeW.Get(C) / 2))
                    else
                        X.Set(C, X.Get(I) + Side.Get(C) * (NodeW.Get(I) / 2 + 52 + NodeW.Get(C) / 2));
                end;
            end;
        end;

        MinX := 0;
        MaxX := 0;
        MinY := 0;
        MaxY := 0;
        // The root is drawn last, on top of the links that leave it.
        for K := 1 to N do begin
            Idx := (K mod N) + 1;
            Shape := ShapeNames.Get(Idx);
            Cx := X.Get(Idx);
            Top := Y.Get(Idx);
            MinX := MText.MinDec(MinX, Cx - NodeW.Get(Idx) / 2);
            MaxX := MText.MaxDec(MaxX, Cx + NodeW.Get(Idx) / 2);
            MinY := MText.MinDec(MinY, Top);
            MaxY := MText.MaxDec(MaxY, Top + NodeH.Get(Idx));

            if (Idx = 1) or (NParent.Get(Idx) = 1) then
                Flush(Out, Edges, Body, NSect.Get(K), Color);
            if Idx > 1 then begin
                if NParent.Get(Idx) = 1 then
                    Color := Builder.SeriesColor(SectionOf(Idx));
                P := NParent.Get(Idx);
                Dir := Side.Get(Idx);
                if Dir > 0 then
                    FromSide := 1
                else
                    FromSide := 3;
                X1 := X.Get(P) + Dir * NodeW.Get(P) / 2;
                if ShapeNames.Get(P) <> '' then
                    X1 := X.Get(P) + Dir * (NodeW.Get(P) / 2 - Shapes.Inset(ShapeNames.Get(P), NodeW.Get(P), NodeH.Get(P), FromSide, 0));
                Y1 := Y.Get(P) + Anchor.Get(P);
                Near := Cx - (Dir * NodeW.Get(Idx)) / 2;
                X2 := Near;
                if Shape <> '' then
                    X2 := Near + Dir * Shapes.Inset(Shape, NodeW.Get(Idx), NodeH.Get(Idx), 4 - FromSide, 0);
                Y2 := Top + Anchor.Get(Idx);
                Mid := MText.Num((X1 + X2) / 2);
                Edges.Append('<path class="pele-edge" d="M' + MText.Num(X1) + ',' + MText.Num(Y1) + 'C' + Mid + ',' + MText.Num(Y1) + ' ' + Mid + ',' + MText.Num(Y2) + ' ' + MText.Num(X2) + ',' + MText.Num(Y2) + '"/>');
            end;

            Pill := (Shape = '') and HasChildren(Idx);
            // Every node off the root is filled with a tint of its branch's color and outlined in it,
            // whether its shape was given in the source or is the pill of a node that branches.
            // The root is neutral.
            Tint := ' fill="' + Color + '" fill-opacity="0.22" stroke="' + Color + '"';
            Inner := '';
            if Shape <> '' then begin
                if Idx > 1 then
                    Inner := Shapes.Draw(Shape, NodeW.Get(Idx), NodeH.Get(Idx), Tint, ' stroke="' + Color + '"')
                else
                    Inner := Shapes.Draw(Shape, NodeW.Get(Idx), NodeH.Get(Idx), ' fill="var(--_s)" stroke="var(--_b)"', ' stroke="var(--_b)"');
            end else
                if Pill then
                    Inner := '<rect x="' + MText.Num(-NodeW.Get(Idx) / 2) + '" y="' + MText.Num(-NodeH.Get(Idx) / 2) + '" width="' + MText.Num(NodeW.Get(Idx)) + '" height="' + MText.Num(NodeH.Get(Idx)) + '" rx="' + MText.Num(NodeH.Get(Idx) / 2) + '"' + Tint + '/>';
            ShapeClass := Shape;
            if ShapeClass = '' then
                if Pill then
                    ShapeClass := 'branch'
                else
                    ShapeClass := 'text';
            RootClass := '';
            if Idx = 1 then
                RootClass := ' pele-root';
            Lbl.Layout(NDescr.Get(Idx), true, Size, Wrap, 0);
            Group := '<g class="pele-node pele-shape-' + ShapeClass + RootClass + Builder.ClassNames(NClass.Get(Idx)) + '" data-id="' + MText.EscText(NId.Get(Idx)) +
                     '" transform="translate(' + MText.Num(Cx) + ',' + MText.Num(Top + NodeH.Get(Idx) / 2) + ')">' +
                     Inner + Lbl.ToSvg(0, NodeDy.Get(Idx), ' class="pele-label"') + '</g>';
            if Idx > 1 then
                Body.Append(Group)
            else
                Out.Append(Group);
        end;

        TitleLbl.Layout(MapTitle, false, Size, 4000, MText.StyleBold());
        TitleHeight := 0;
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 16;
        Width := MText.MaxDec(MaxX - MinX, TitleLbl.GetWidth());
        TotalWidth := MText.Ceil(Width + 2 * Pad);
        TotalHeight := MText.Ceil(MaxY - MinY + TitleHeight + 2 * Pad);
        Content := Builder.TitleSvg(TitleLbl, TotalWidth / 2, Pad + TitleLbl.GetHeight() / 2) +
                   '<g transform="translate(' + MText.Num(Pad - MinX + (Width - MaxX + MinX) / 2) + ',' + MText.Num(Pad + TitleHeight - MinY) + ')">' + Out.ToText() + '</g>';
        exit(Builder.Document('mindmap', TotalWidth, TotalHeight, Size, '', '', Content));
    end;

    local procedure SectionOf(Node: Integer): Integer
    begin
        if NSect.Get(Node) < 0 then
            exit(0);
        exit(NSect.Get(Node));
    end;

    /// <summary>Closes the group of one first-level branch: its links under its nodes.</summary>
    local procedure Flush(var Out: TextBuilder; var Edges: TextBuilder; var Body: TextBuilder; Sect: Integer; Color: Text)
    begin
        if Body.Length() = 0 then
            exit;
        if Sect < 0 then
            Sect := 0;
        Out.Append('<g class="pele-branch pele-section-' + MText.IntText(Sect) + '">' +
                   '<g class="pele-edges" fill="none" stroke="' + Color + '" stroke-width="1.5">' + Edges.ToText() + '</g>' + Body.ToText() + '</g>');
        Clear(Edges);
        Clear(Body);
    end;
}
