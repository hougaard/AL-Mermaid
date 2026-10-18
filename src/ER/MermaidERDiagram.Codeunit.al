/// <summary>
/// Port of pele's diagrams/er: lexer.ts, parser.ts, db.ts, graph.ts, markers.ts and render.ts, with the
/// generic type helper from diagrams/common/generics.ts. Entities are drawn as boxes with an attribute table
/// (type, name, keys, comment), relationships as lines with crow's foot markers, solid when identifying and
/// dashed when not. Subgraphs, classDef / class / style and the ::: shorthand are supported. The layout is
/// codeunit "Mermaid Compound Layout".
/// </summary>
codeunit 68915 "Mermaid ER Diagram"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Layout: Codeunit "Mermaid Compound Layout";
        Src: Text;
        LowerSrc: Text;
        // ------------------------------------------------ tokens (type names as Mermaid's grammar has them)
        TokType: List of [Text];
        TokText: List of [Text];
        TokStart: List of [Integer];
        Tk: Integer;
        // ------------------------------------------------ lexer state
        LexPos: Integer;
        LexLen: Integer;
        LexState: Integer;
        LexError: Boolean;
        DirNext: Integer;
        DirFailed: Integer;
        LineEndPos: Integer;
        TildeNext: Integer;
        TildeLine: Integer;
        TildeLast: Integer;
        WsNext: Integer;
        // ------------------------------------------------ model (pele's ErDb)
        DiagramDir: Text;
        DiagramTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        EntName: List of [Text];
        EntId: List of [Text];
        EntAlias: List of [Text];
        EntClasses: List of [Text];
        EntStyles: List of [Text];
        EntIndex: Dictionary of [Text, Integer];
        AttrEnt: List of [Integer];
        AttrType: List of [Text];
        AttrName: List of [Text];
        AttrKeys: List of [Text];
        AttrComment: List of [Text];
        RelA: List of [Text];
        RelRole: List of [Text];
        RelB: List of [Text];
        RelCardA: List of [Text];
        RelCardB: List of [Text];
        RelIdentifying: List of [Boolean];
        ClassStyles: Dictionary of [Text, Text];
        ClassTextStyles: Dictionary of [Text, Text];
        SgId: List of [Text];
        SgTitle: List of [Text];
        SgClasses: List of [Text];
        SgStyles: List of [Text];
        SgDir: List of [Text];
        SgNodeOwner: List of [Integer];
        SgNodeName: List of [Text];
        SgLookup: Dictionary of [Text, Integer];
        Claimed: Dictionary of [Text, Boolean];
        // ------------------------------------------------ subgraph frames while parsing
        FrameId: List of [Text];
        FrameTitle: List of [Text];
        ItemDepth: List of [Integer];
        ItemText: List of [Text];
        ItemIsDir: List of [Boolean];
        // ------------------------------------------------ graph (pele's buildErGraph)
        NId: List of [Text];
        NLabel: List of [Text];
        NAlias: List of [Text];
        NIsGroup: List of [Boolean];
        NParentId: List of [Text];
        NHasParent: List of [Boolean];
        NParent: List of [Integer];
        NStyles: List of [Text];
        NClasses: List of [Text];
        NDir: List of [Text];
        NEnt: List of [Integer];
        NodeIndex: Dictionary of [Text, Integer];
        GEdgeId: List of [Text];
        GStart: List of [Text];
        GEnd: List of [Text];
        GLabel: List of [Text];
        GArrowStart: List of [Text];
        GArrowEnd: List of [Text];
        GDashed: List of [Boolean];
        // ------------------------------------------------ views, by node index (the layout's index too)
        VW: List of [Decimal];
        VH: List of [Decimal];
        VHeadH: List of [Decimal];
        VNameSize: List of [Decimal];
        VRowSize: List of [Decimal];
        VKeySize: List of [Decimal];
        VBase: List of [Integer];
        VShapeAttr: List of [Text];
        VLineAttr: List of [Text];
        VTextAttr: List of [Text];
        VStroke: List of [Text];
        VBelow: List of [Boolean];
        VCols: List of [Decimal];
        VRowFirst: List of [Integer];
        VRowCount: List of [Integer];
        RowAttr: List of [Integer];
        RowH: List of [Decimal];
        // ------------------------------------------------ drawn edges, by layout edge index
        DGraph: List of [Integer];
        DSrc: List of [Integer];
        DDst: List of [Integer];
        DLoop: List of [Boolean];
        DBand: List of [Decimal];
        DAt: List of [Decimal];
        DLabelW: List of [Decimal];
        DLabelH: List of [Decimal];
        DRtStart: List of [Integer];
        DRtLen: List of [Integer];
        RtVals: List of [Decimal];
        SmallSize: Decimal;

    // ================================================================ public contract

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    begin
        ClearAll();
        Src := Source;
        DiagramDir := 'TB';
        DiagramTitle := FrontTitle;
        Tokenize();
        ParseDocument();
    end;

    // ================================================================ lexer

    local procedure Ch(Pos: Integer): Integer
    begin
        exit(MText.CharAt(Src, Pos));
    end;

    local procedure LowerC(C: Integer): Integer
    begin
        if (C >= 65) and (C <= 90) then
            exit(C + 32);
        exit(C);
    end;

    /// <summary>Whether a lower-case word stands at Pos, ignoring the case of ASCII letters.</summary>
    local procedure MatchCI(Pos: Integer; Word: Text): Boolean
    begin
        exit(MText.StartsWithAt(LowerSrc, Word, Pos));
    end;

    local procedure Kw(Word: Text): Boolean
    begin
        exit(MatchCI(LexPos, Word));
    end;

    local procedure Kwb(Word: Text): Boolean
    begin
        if not MatchCI(LexPos, Word) then
            exit(false);
        exit(not MText.IsWord(Ch(LexPos + StrLen(Word))));
    end;

    local procedure Push(TypeName: Text; Value: Text; StartPos: Integer)
    begin
        TokType.Add(TypeName);
        TokText.Add(Value);
        TokStart.Add(StartPos);
    end;

    local procedure Emit(TypeName: Text; S: Integer; E: Integer)
    begin
        Push(TypeName, MText.Substr(Src, S, E), S);
        LexPos := E;
    end;

    local procedure NextLineEnd(Q: Integer): Integer
    begin
        while Q <= LexLen do begin
            if MText.IsLineEnd(Ch(Q)) then
                exit(Q);
            Q += 1;
        end;
        exit(LexLen + 1);
    end;

    local procedure Digits(Q: Integer): Integer
    begin
        while MText.IsDigit(Ch(Q)) do
            Q += 1;
        exit(Q);
    end;

    /// <summary>pele's character classes: 1 text, 2 style text, 4 attribute start, 8 attribute rest (ASCII only).</summary>
    local procedure HasClass(C: Integer; Kind: Integer): Boolean
    var
        IsWordChar: Boolean;
    begin
        if (C < 0) or (C >= 128) then
            exit(false);
        IsWordChar := MText.IsWord(C);
        case Kind of
            1:
                exit(IsWordChar or (C in [45, 42, 46]));
            2:
                exit(IsWordChar or (C in [45, 42]));
            4:
                exit((IsWordChar and not MText.IsDigit(C)) or (C = 42));
            8:
                exit(IsWordChar or (C in [45, 42, 46, 91, 93, 40, 41, 44]));
        end;
        exit(false);
    end;

    local procedure IsTextChar(C: Integer): Boolean
    begin
        exit((C >= 128) or HasClass(C, 1));
    end;

    local procedure IsStyleChar(C: Integer): Boolean
    begin
        exit((C >= 128) or HasClass(C, 2));
    end;

    // Mermaid's attribute pattern is case-insensitive, which lets the micro sign into its À-￿ range.
    local procedure IsAttr(C: Integer; Kind: Integer): Boolean
    begin
        if C < 0 then
            exit(false);
        if C < 128 then
            exit(HasClass(C, Kind));
        exit((C >= 192) or (C = 181));
    end;

    local procedure BuildLowerSrc()
    var
        Lower: TextBuilder;
        I: Integer;
        C: Integer;
    begin
        for I := 1 to LexLen do begin
            C := Src[I];
            if (C >= 65) and (C <= 90) then
                Lower.Append(MText.FromCode(C + 32))
            else
                Lower.Append(CopyStr(Src, I, 1));
        end;
        LowerSrc := Lower.ToText();
    end;

    local procedure Tokenize()
    var
        C: Integer;
        E: Integer;
    begin
        LexLen := StrLen(Src);
        BuildLowerSrc();
        LexPos := 1;
        LexState := 0;
        LexError := false;
        DirNext := -2;
        DirFailed := 0;
        LineEndPos := -1;
        TildeNext := -2;
        TildeLine := -1;
        TildeLast := -1;
        WsNext := -1;
        while (LexPos <= LexLen) and not LexError do begin
            C := Ch(LexPos);
            case LexState of
                0:
                    LexInitial(C);
                1:
                    LexBlock(C);
                2:
                    if C = 96 then begin
                        LexState := 1;
                        LexPos += 1;
                    end else begin
                        E := MText.IndexOfFrom(Src, '`', LexPos);
                        if E = 0 then
                            E := LexLen + 1;
                        Emit('ATTRIBUTE_WORD', LexPos, E);
                    end;
                3, 4:
                    begin
                        E := MText.IndexOfFrom(Src, MText.LF(), LexPos);
                        if E = 0 then
                            E := LexLen + 1;
                        if LexState = 3 then
                            Emit('acc_title_value', LexPos, E)
                        else
                            Emit('acc_descr_value', LexPos, E);
                        LexState := 0;
                    end;
                5:
                    if C = 125 then begin
                        LexState := 0;
                        LexPos += 1;
                    end else begin
                        E := MText.IndexOfFrom(Src, '}', LexPos);
                        if E = 0 then
                            E := LexLen + 1;
                        Emit('acc_descr_multiline_value', LexPos, E);
                    end;
                6:
                    LexStyle(C);
            end;
        end;
        if LexError then
            exit;
        // At the end of input Jison's INITIAL state yields EOF, the title and description states yield
        // an empty value, and the block and style states yield nothing.
        case LexState of
            0:
                Push('EOF', '', LexLen + 1);
            3:
                Push('acc_title_value', '', LexLen + 1);
            4:
                Push('acc_descr_value', '', LexLen + 1);
            5:
                Push('acc_descr_multiline_value', '', LexLen + 1);
        end;
        Push('$end', '', LexLen + 1);
    end;

    /// <summary>/word\s*delim\s*/iy at the lexer's position: the end of the match, or -1.</summary>
    local procedure AccMatch(Word: Text; Delim: Integer): Integer
    var
        Q: Integer;
    begin
        if not Kw(Word) then
            exit(-1);
        Q := LexPos + StrLen(Word);
        while MText.IsSpace(Ch(Q)) do
            Q += 1;
        if Ch(Q) <> Delim then
            exit(-1);
        Q += 1;
        while MText.IsSpace(Ch(Q)) do
            Q += 1;
        exit(Q);
    end;

    /// <summary>/.*direction\s+XX[^\n]*/iy at the lexer's position: the end of the match, or -1.</summary>
    local procedure DirMatch(DirWord: Text): Integer
    var
        LineStop: Integer;
        Q: Integer;
        R: Integer;
        E: Integer;
    begin
        LineStop := NextLineEnd(LexPos);
        // The greedy .* takes the last place on the line that matches.
        for Q := LineStop - 1 downto LexPos do
            if MatchCI(Q, 'direction') then begin
                R := Q + 9;
                if MText.IsSpace(Ch(R)) then begin
                    while MText.IsSpace(Ch(R)) do
                        R += 1;
                    if MatchCI(R, DirWord) then begin
                        E := R + 2;
                        while (E <= LexLen) and (Ch(E) <> 10) do
                            E += 1;
                        exit(E);
                    end;
                end;
            end;
        exit(-1);
    end;

    // A direction statement swallows its whole line, from wherever the lexer stands on it.
    local procedure Direction(): Boolean
    var
        Words: List of [Text];
        Types: List of [Text];
        I: Integer;
        E: Integer;
    begin
        if DirNext = -1 then
            exit(false);
        if DirNext < LexPos then begin
            DirNext := MText.IndexOfFrom(LowerSrc, 'direction', LexPos);
            if DirNext = 0 then begin
                DirNext := -1;
                exit(false);
            end;
        end;
        if LexPos < DirFailed then
            exit(false);
        if LineEndPos < LexPos then
            LineEndPos := NextLineEnd(LexPos);
        if DirNext >= LineEndPos then
            exit(false);
        Words.Add('tb');
        Words.Add('bt');
        Words.Add('rl');
        Words.Add('lr');
        Types.Add('direction_tb');
        Types.Add('direction_bt');
        Types.Add('direction_rl');
        Types.Add('direction_lr');
        for I := 1 to 4 do begin
            E := DirMatch(Words.Get(I));
            if E >= 0 then begin
                Emit(Types.Get(I), LexPos, E);
                exit(true);
            end;
        end;
        DirFailed := LineEndPos;
        exit(false);
    end;

    local procedure Quoted()
    var
        E: Integer;
        Q: Integer;
        IsNameToken: Boolean;
    begin
        E := MText.IndexOfFrom(Src, '"', LexPos + 1);
        if E = 0 then begin
            Emit('CHAR', LexPos, LexPos + 1);
            exit;
        end;
        IsNameToken := E > LexPos + 1;
        for Q := LexPos + 1 to E - 1 do
            if Ch(Q) in [37, 92, 13, 10, 11, 8] then
                IsNameToken := false;
        if IsNameToken then
            Emit('ENTITY_NAME', LexPos, E + 1)
        else
            Emit('WORD', LexPos, E + 1);
    end;

    local procedure Number(C: Integer)
    var
        D: Integer;
        Q: Integer;
        R: Integer;
        F: Integer;
    begin
        D := Ch(LexPos + 1);
        if (D = 43) and ((C = 49) or (C = 48)) then begin
            if C = 49 then
                Emit('ONE_OR_MORE', LexPos, LexPos + 2)
            else
                Emit('ZERO_OR_MORE', LexPos, LexPos + 2);
            exit;
        end;
        Q := Digits(LexPos + 1);
        if (Ch(Q) = 46) and MText.IsDigit(Ch(Q + 1)) then begin
            Emit('DECIMAL_NUM', LexPos, Digits(Q + 2));
            exit;
        end;
        if C = 49 then begin
            if MText.IsSpace(D) then begin
                R := LexPos + 2;
                while MText.IsSpace(Ch(R)) do
                    R += 1;
                F := Ch(R);
                if MText.IsWord(F) or (F = 34) or (F = 39) then begin
                    Emit('ONLY_ONE', LexPos, LexPos + 1);
                    exit;
                end;
            end else
                if (D = 45) or (D = 46) then begin
                    F := Ch(LexPos + 2);
                    if (F = 45) or (F = 46) then begin
                        Emit('ONLY_ONE', LexPos, LexPos + 1);
                        exit;
                    end;
                end;
            if not MText.IsWord(D) then begin
                Emit('ENTITY_ONE', LexPos, LexPos + 1);
                exit;
            end;
        end;
        Emit('NUM', LexPos, Q);
    end;

    local procedure Keyword(Lc: Integer): Boolean
    var
        D: Integer;
        E: Integer;
    begin
        D := Ch(LexPos + 1);
        case Lc of
            101:
                begin
                    if Kwb('erdiagram') then
                        Emit('ER_DIAGRAM', LexPos, LexPos + 9)
                    else
                        if Kwb('end') then begin
                            E := LexPos + 3;
                            while MText.IsSpace(Ch(E)) do
                                E += 1;
                            Emit('END', LexPos, E);
                        end else
                            exit(false);
                    exit(true);
                end;
            115:
                begin
                    if Kwb('style') then begin
                        LexState := 6;
                        Emit('STYLE', LexPos, LexPos + 5);
                    end else
                        if Kwb('subgraph') then
                            Emit('SUBGRAPH', LexPos, LexPos + 8)
                        else
                            exit(false);
                    exit(true);
                end;
            99:
                begin
                    if Kwb('classdef') then begin
                        LexState := 6;
                        Emit('CLASSDEF', LexPos, LexPos + 8);
                    end else
                        if Kwb('class') then
                            Emit('CLASS', LexPos, LexPos + 5)
                        else
                            exit(false);
                    exit(true);
                end;
            111:
                begin
                    if Kwb('one or zero') then
                        Emit('ZERO_OR_ONE', LexPos, LexPos + 11)
                    else
                        if Kwb('one or more') or Kwb('one or many') then
                            Emit('ONE_OR_MORE', LexPos, LexPos + 11)
                        else
                            if Kwb('one') then
                                Emit('ONLY_ONE', LexPos, LexPos + 3)
                            else
                                if Kwb('only one') then
                                    Emit('ONLY_ONE', LexPos, LexPos + 8)
                                else
                                    if D = 124 then
                                        Emit('ZERO_OR_ONE', LexPos, LexPos + 2)
                                    else
                                        if D = 123 then
                                            Emit('ZERO_OR_MORE', LexPos, LexPos + 2)
                                        else
                                            if Kwb('optionally to') then
                                                Emit('NON_IDENTIFYING', LexPos, LexPos + 13)
                                            else
                                                exit(false);
                    exit(true);
                end;
            122:
                begin
                    if Kwb('zero or one') then
                        Emit('ZERO_OR_ONE', LexPos, LexPos + 11)
                    else
                        if Kwb('zero or more') or Kwb('zero or many') then
                            Emit('ZERO_OR_MORE', LexPos, LexPos + 12)
                        else
                            exit(false);
                    exit(true);
                end;
            109:
                begin
                    if Kw('many(0)') then
                        Emit('ZERO_OR_MORE', LexPos, LexPos + 7)
                    else
                        if Kw('many(1)') then
                            Emit('ONE_OR_MORE', LexPos, LexPos + 7)
                        else
                            if Kwb('many') then
                                Emit('ZERO_OR_MORE', LexPos, LexPos + 4)
                            else
                                exit(false);
                    exit(true);
                end;
            116:
                begin
                    if not Kwb('to') then
                        exit(false);
                    Emit('IDENTIFYING', LexPos, LexPos + 2);
                    exit(true);
                end;
            117:
                begin
                    if not (D in [46, 45, 124]) then
                        exit(false);
                    Emit('MD_PARENT', LexPos, LexPos + 1);
                    exit(true);
                end;
            124:
                begin
                    if (LowerC(D) = 111) and not MText.IsWord(Ch(LexPos + 2)) then
                        Emit('ZERO_OR_ONE', LexPos, LexPos + 2)
                    else
                        if D = 124 then
                            Emit('ONLY_ONE', LexPos, LexPos + 2)
                        else
                            if D = 123 then
                                Emit('ONE_OR_MORE', LexPos, LexPos + 2)
                            else
                                exit(false);
                    exit(true);
                end;
            125:
                begin
                    if (LowerC(D) = 111) and not MText.IsWord(Ch(LexPos + 2)) then
                        Emit('ZERO_OR_MORE', LexPos, LexPos + 2)
                    else
                        if D = 124 then
                            Emit('ONE_OR_MORE', LexPos, LexPos + 2)
                        else
                            exit(false);
                    exit(true);
                end;
            46:
                begin
                    if (D <> 46) and (D <> 45) then
                        exit(false);
                    Emit('NON_IDENTIFYING', LexPos, LexPos + 2);
                    exit(true);
                end;
            45:
                begin
                    case D of
                        45:
                            Emit('IDENTIFYING', LexPos, LexPos + 2);
                        46:
                            Emit('NON_IDENTIFYING', LexPos, LexPos + 2);
                        else
                            exit(false);
                    end;
                    exit(true);
                end;
        end;
        exit(false);
    end;

    local procedure LexInitial(C: Integer)
    var
        E: Integer;
    begin
        if ((C = 97) or (C = 65)) and Kw('acc') then begin
            E := AccMatch('acctitle', 58);
            if E >= 0 then begin
                LexState := 3;
                Emit('acc_title', LexPos, E);
                exit;
            end;
            E := AccMatch('accdescr', 58);
            if E >= 0 then begin
                LexState := 4;
                Emit('acc_descr', LexPos, E);
                exit;
            end;
            E := AccMatch('accdescr', 123);
            if E >= 0 then begin
                LexState := 5;
                LexPos := E;
                exit;
            end;
        end;
        if Direction() then
            exit;

        case C of
            32, 9, 13:
                begin
                    E := LexPos + 1;
                    while Ch(E) in [32, 9, 13] do
                        E += 1;
                    LexPos := E;
                    exit;
                end;
            10:
                begin
                    E := LexPos + 1;
                    while Ch(E) = 10 do
                        E += 1;
                    Emit('NEWLINE', LexPos, E);
                    exit;
                end;
            34:
                begin
                    Quoted();
                    exit;
                end;
            123:
                begin
                    LexState := 1;
                    Emit('BLOCK_START', LexPos, LexPos + 1);
                    exit;
                end;
            35:
                begin
                    Emit('BRKT', LexPos, LexPos + 1);
                    exit;
                end;
            44:
                begin
                    Emit('COMMA', LexPos, LexPos + 1);
                    exit;
                end;
            58:
                begin
                    if (Ch(LexPos + 1) = 58) and (Ch(LexPos + 2) = 58) then
                        Emit('STYLE_SEPARATOR', LexPos, LexPos + 3)
                    else
                        Emit('COLON', LexPos, LexPos + 1);
                    exit;
                end;
            91:
                begin
                    Emit('SQS', LexPos, LexPos + 1);
                    exit;
                end;
            93:
                begin
                    Emit('SQE', LexPos, LexPos + 1);
                    exit;
                end;
        end;
        if MText.IsDigit(C) then begin
            Number(C);
            exit;
        end;
        if Keyword(LowerC(C)) then
            exit;
        if IsTextChar(C) then begin
            E := LexPos + 1;
            while IsTextChar(Ch(E)) do
                E += 1;
            Emit('UNICODE_TEXT', LexPos, E);
            exit;
        end;
        Emit('CHAR', LexPos, LexPos + 1);
    end;

    local procedure LastTildeBefore(Limit: Integer): Integer
    var
        Q: Integer;
    begin
        for Q := Limit - 1 downto 1 do
            if Ch(Q) = 126 then
                exit(Q);
        exit(0);
    end;

    // Mermaid's generic type rule: a run of non-space characters holding a `~`, through the last `~` on the line.
    local procedure Generic(): Boolean
    var
        Q: Integer;
        E: Integer;
    begin
        if TildeNext = -1 then
            exit(false);
        if TildeNext < LexPos then begin
            TildeNext := MText.IndexOfFrom(Src, '~', LexPos);
            if TildeNext = 0 then begin
                TildeNext := -1;
                exit(false);
            end;
        end;
        if WsNext < LexPos then begin
            Q := LexPos;
            while (Q <= LexLen) and not MText.IsSpace(Ch(Q)) do
                Q += 1;
            WsNext := Q;
        end;
        if TildeNext >= WsNext then
            exit(false);
        if TildeLine < LexPos then begin
            TildeLine := NextLineEnd(LexPos);
            TildeLast := LastTildeBefore(TildeLine);
        end;
        if TildeLast <= TildeNext then
            exit(false);
        E := TildeLast + 1;
        while (E <= LexLen) and not MText.IsSpace(Ch(E)) do
            E += 1;
        Emit('ATTRIBUTE_WORD', LexPos, E);
        exit(true);
    end;

    local procedure LexBlock(C: Integer)
    var
        E: Integer;
        Lc: Integer;
    begin
        if MText.IsSpace(C) then begin
            LexPos += 1;
            while MText.IsSpace(Ch(LexPos)) do
                LexPos += 1;
            exit;
        end;
        Lc := LowerC(C);
        if (Lc in [112, 102, 117]) and (LowerC(Ch(LexPos + 1)) = 107) and not MText.IsWord(Ch(LexPos + 2)) then begin
            Emit('ATTRIBUTE_KEY', LexPos, LexPos + 2);
            exit;
        end;
        if Generic() then
            exit;
        if IsAttr(C, 4) then begin
            E := LexPos + 1;
            while IsAttr(Ch(E), 8) do
                E += 1;
            Emit('ATTRIBUTE_WORD', LexPos, E);
            exit;
        end;
        if C = 96 then begin
            LexState := 2;
            LexPos += 1;
            exit;
        end;
        if C = 34 then begin
            E := MText.IndexOfFrom(Src, '"', LexPos + 1);
            if E > 0 then begin
                Emit('COMMENT', LexPos, E + 1);
                exit;
            end;
        end else
            if C = 125 then begin
                LexState := 0;
                Emit('BLOCK_STOP', LexPos, LexPos + 1);
                exit;
            end;
        Emit('CHAR', LexPos, LexPos + 1);
    end;

    local procedure LexStyle(C: Integer)
    var
        E: Integer;
    begin
        if C = 10 then begin
            E := LexPos + 1;
            while Ch(E) = 10 do
                E += 1;
            LexState := 0;
            Emit('NEWLINE', LexPos, E);
            exit;
        end;
        if MText.IsSpace(C) then begin
            LexPos += 1;
            while MText.IsSpace(Ch(LexPos)) do
                LexPos += 1;
            exit;
        end;
        case C of
            58:
                Emit('COLON', LexPos, LexPos + 1);
            44:
                Emit('COMMA', LexPos, LexPos + 1);
            35:
                Emit('BRKT', LexPos, LexPos + 1);
            59:
                Emit('SEMI', LexPos, LexPos + 1);
            else
                if IsStyleChar(C) then begin
                    E := LexPos + 1;
                    while IsStyleChar(Ch(E)) do
                        E += 1;
                    Emit('STYLE_TEXT', LexPos, E);
                end else begin
                    Push('INVALID', '', LexPos);
                    LexError := true;
                end;
        end;
    end;

    // ================================================================ parser

    local procedure TypeAt(I: Integer): Text
    begin
        if (I < 1) or (I > TokType.Count()) then
            exit('$end');
        exit(TokType.Get(I));
    end;

    local procedure TextAt(I: Integer): Text
    begin
        if (I < 1) or (I > TokText.Count()) then
            exit('');
        exit(TokText.Get(I));
    end;

    local procedure StartAt(I: Integer): Integer
    begin
        if (I < 1) or (I > TokStart.Count()) then
            exit(StrLen(Src) + 1);
        exit(TokStart.Get(I));
    end;

    local procedure ParseFail(Expected: Text)
    var
        T: Text;
        Got: Text;
    begin
        T := TypeAt(Tk);
        if T = 'INVALID' then
            MText.SyntaxError('er', Src, StartAt(Tk), '', true);
        if T = 'CHAR' then
            Got := TextAt(Tk)
        else
            Got := T;
        MText.SyntaxError('er', Src, StartAt(Tk), 'Expecting ' + Expected + ', got ''' + Got + '''', false);
    end;

    local procedure Expect(TypeName: Text): Text
    begin
        if TypeAt(Tk) <> TypeName then
            ParseFail('''' + TypeName + '''');
        Tk += 1;
        exit(TextAt(Tk - 1));
    end;

    local procedure Separator()
    var
        T: Text;
    begin
        T := TypeAt(Tk);
        if (T <> 'NEWLINE') and (T <> 'SEMI') and (T <> 'EOF') then
            ParseFail('''EOF'', ''NEWLINE'', ''SEMI''');
        Tk += 1;
    end;

    local procedure NameList(): Text
    begin
        exit('''UNICODE_TEXT'', ''NUM'', ''ENTITY_NAME'', ''DECIMAL_NUM'', ''ENTITY_ONE''');
    end;

    local procedure CardList(): Text
    begin
        exit('''ZERO_OR_ONE'', ''ZERO_OR_MORE'', ''ONE_OR_MORE'', ''ONLY_ONE'', ''MD_PARENT''');
    end;

    local procedure LineList(): Text
    begin
        exit('''EOF'', ''NEWLINE'', ''title'', ''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''SUBGRAPH'', ''direction_tb'', ' +
             '''direction_bt'', ''direction_rl'', ''direction_lr'', ''CLASSDEF'', ''CLASS'', ''STYLE'', ' + NameList());
    end;

    local procedure IsName(T: Text): Boolean
    begin
        exit(T in ['UNICODE_TEXT', 'ENTITY_NAME', 'NUM', 'DECIMAL_NUM', 'ENTITY_ONE']);
    end;

    local procedure IsCard(T: Text): Boolean
    begin
        exit(T in ['ZERO_OR_ONE', 'ZERO_OR_MORE', 'ONE_OR_MORE', 'ONLY_ONE', 'MD_PARENT']);
    end;

    local procedure StripQuotes(Value: Text): Text
    begin
        exit(MText.Substr(Value, 2, StrLen(Value)));
    end;

    local procedure EntityName(): Text
    var
        T: Text;
        Value: Text;
    begin
        T := TypeAt(Tk);
        if not IsName(T) then
            ParseFail(NameList());
        Value := TextAt(Tk);
        Tk += 1;
        if T = 'ENTITY_NAME' then
            exit(StripQuotes(Value));
        exit(Value);
    end;

    local procedure IdList(var Ids: List of [Text])
    var
        T: Text;
    begin
        Clear(Ids);
        repeat
            T := TypeAt(Tk);
            if (T <> 'UNICODE_TEXT') and (T <> 'STYLE_TEXT') then
                ParseFail('''UNICODE_TEXT'', ''STYLE_TEXT''');
            Ids.Add(TextAt(Tk));
            Tk += 1;
            if TypeAt(Tk) <> 'COMMA' then
                exit;
            Tk += 1;
        until false;
    end;

    local procedure IsStyleComponent(T: Text): Boolean
    begin
        exit(T in ['STYLE_TEXT', 'NUM', 'COLON', 'BRKT']);
    end;

    local procedure StylesOpt(var Styles: List of [Text])
    var
        Style: Text;
    begin
        Clear(Styles);
        repeat
            if not IsStyleComponent(TypeAt(Tk)) then
                ParseFail('''STYLE_TEXT'', ''COLON'', ''NUM'', ''BRKT''');
            Style := TextAt(Tk);
            Tk += 1;
            while IsStyleComponent(TypeAt(Tk)) do begin
                Style += TextAt(Tk);
                Tk += 1;
            end;
            Styles.Add(Style);
            if TypeAt(Tk) <> 'COMMA' then
                exit;
            Tk += 1;
        until false;
    end;

    local procedure RelSpec(var CardA: Text; var Identifying: Boolean; var CardB: Text)
    var
        R: Text;
    begin
        CardB := TypeAt(Tk);
        Tk += 1;
        R := TypeAt(Tk);
        if (R <> 'IDENTIFYING') and (R <> 'NON_IDENTIFYING') then
            ParseFail('''NON_IDENTIFYING'', ''IDENTIFYING''');
        Identifying := R = 'IDENTIFYING';
        Tk += 1;
        if not IsCard(TypeAt(Tk)) then
            ParseFail(CardList());
        CardA := TypeAt(Tk);
        Tk += 1;
    end;

    local procedure Role(): Text
    var
        T: Text;
        Value: Text;
    begin
        T := TypeAt(Tk);
        if (T <> 'WORD') and (T <> 'ENTITY_NAME') and (T <> 'UNICODE_TEXT') then
            ParseFail('''UNICODE_TEXT'', ''ENTITY_NAME'', ''WORD''');
        Value := TextAt(Tk);
        Tk += 1;
        if T = 'UNICODE_TEXT' then
            exit(Value);
        exit(StripQuotes(Value));
    end;

    local procedure IsChar(Value: Text): Boolean
    begin
        if TypeAt(Tk) <> 'CHAR' then
            exit(false);
        exit(TextAt(Tk) = Value);
    end;

    /// <summary>The attributes of a block, in the order written (the net effect of Mermaid's right-recursive rule and addAttributes).</summary>
    local procedure Attributes(var Types: List of [Text]; var Names: List of [Text]; var KeyTexts: List of [Text]; var Comments: List of [Text])
    var
        TypeText: Text;
        KeysText: Text;
        CommentText: Text;
    begin
        repeat
            TypeText := Expect('ATTRIBUTE_WORD');
            if IsChar('?') then begin
                TypeText += TextAt(Tk);
                Tk += 1;
            end;
            if TypeAt(Tk) <> 'ATTRIBUTE_WORD' then
                if TypeText.EndsWith('?') then
                    ParseFail('''ATTRIBUTE_WORD''')
                else
                    ParseFail('''ATTRIBUTE_WORD'', ''?''');
            Types.Add(TypeText);
            Names.Add(TextAt(Tk));
            Tk += 1;
            KeysText := '';
            if TypeAt(Tk) = 'ATTRIBUTE_KEY' then begin
                KeysText := TextAt(Tk);
                Tk += 1;
                while IsChar(',') do begin
                    Tk += 1;
                    KeysText += ', ' + Expect('ATTRIBUTE_KEY');
                end;
            end;
            CommentText := '';
            if TypeAt(Tk) = 'COMMENT' then begin
                CommentText := StripQuotes(TextAt(Tk));
                Tk += 1;
            end;
            KeyTexts.Add(KeysText);
            Comments.Add(CommentText);
        until TypeAt(Tk) = 'BLOCK_STOP';
    end;

    /// <summary>Parses an optional { ... } block; false when there is none or it is empty.</summary>
    local procedure ParseBlock(var Types: List of [Text]; var Names: List of [Text]; var KeyTexts: List of [Text]; var Comments: List of [Text]): Boolean
    begin
        if TypeAt(Tk) <> 'BLOCK_START' then
            exit(false);
        Tk += 1;
        if TypeAt(Tk) = 'BLOCK_STOP' then begin
            Tk += 1;
            exit(false);
        end;
        Attributes(Types, Names, KeyTexts, Comments);
        Tk += 1;
        exit(true);
    end;

    local procedure EntityStatement(var Names: List of [Text])
    var
        Classes: List of [Text];
        ClassesB: List of [Text];
        Types: List of [Text];
        AttrNames: List of [Text];
        KeyTexts: List of [Text];
        Comments: List of [Text];
        A: Text;
        B: Text;
        Alias: Text;
        T: Text;
        CardA: Text;
        CardB: Text;
        RoleText: Text;
        Identifying: Boolean;
        HasClasses: Boolean;
        HasClassesB: Boolean;
        HasAttrs: Boolean;
    begin
        Clear(Names);
        A := EntityName();
        T := TypeAt(Tk);
        if T = 'SQS' then begin
            Tk += 1;
            Alias := EntityName();
            Expect('SQE');
            if TypeAt(Tk) = 'STYLE_SEPARATOR' then begin
                Tk += 1;
                IdList(Classes);
                HasClasses := true;
            end;
            HasAttrs := ParseBlock(Types, AttrNames, KeyTexts, Comments);
            AddEntity(A, Alias);
            if HasAttrs then
                AddAttributes(A, Types, AttrNames, KeyTexts, Comments);
            if HasClasses then
                SetClassOn(A, Classes);
            Names.Add(A);
            exit;
        end;
        if T = 'STYLE_SEPARATOR' then begin
            Tk += 1;
            IdList(Classes);
            HasClasses := true;
            T := TypeAt(Tk);
        end;
        if IsCard(T) then begin
            RelSpec(CardA, Identifying, CardB);
            B := EntityName();
            if TypeAt(Tk) = 'STYLE_SEPARATOR' then begin
                Tk += 1;
                IdList(ClassesB);
                HasClassesB := true;
            end;
            Expect('COLON');
            RoleText := Role();
            AddEntity(A, '');
            AddEntity(B, '');
            AddRelationship(A, RoleText, B, CardA, Identifying, CardB);
            if HasClasses then
                SetClassOn(A, Classes);
            if HasClassesB then
                SetClassOn(B, ClassesB);
            Names.Add(A);
            Names.Add(B);
            exit;
        end;
        HasAttrs := ParseBlock(Types, AttrNames, KeyTexts, Comments);
        AddEntity(A, '');
        if HasAttrs then
            AddAttributes(A, Types, AttrNames, KeyTexts, Comments);
        if HasClasses then
            SetClassOn(A, Classes);
        Names.Add(A);
    end;

    local procedure AddItem(Value: Text; IsDir: Boolean)
    begin
        ItemDepth.Add(FrameId.Count());
        ItemText.Add(Value);
        ItemIsDir.Add(IsDir);
    end;

    local procedure ParseDocument()
    var
        Names: List of [Text];
        Ids: List of [Text];
        ClassList: List of [Text];
        Styles: List of [Text];
        T: Text;
        Value: Text;
        Id: Text;
        Title: Text;
        KeywordText: Text;
        Nested: Boolean;
        Done: Boolean;
        Depth: Integer;
    begin
        Tk := 1;
        Expect('ER_DIAGRAM');
        // Subgraphs nest on this stack rather than on the call stack; an empty stack is the diagram itself.
        repeat
            Nested := FrameId.Count() > 0;
            T := TypeAt(Tk);
            case T of
                'NEWLINE':
                    Tk += 1;
                'EOF':
                    begin
                        Tk += 1;
                        if Nested then
                            ParseFail('''END'', ' + LineList());
                        Done := true;
                    end;
                'END':
                    begin
                        if not Nested then
                            ParseFail(LineList());
                        Tk += 1;
                        Depth := FrameId.Count();
                        Id := AddSubGraph(FrameId.Get(Depth), Depth, FrameTitle.Get(Depth));
                        FrameId.RemoveAt(Depth);
                        FrameTitle.RemoveAt(Depth);
                        if FrameId.Count() > 0 then
                            AddItem(Id, false);
                    end;
                'SUBGRAPH':
                    begin
                        Tk += 1;
                        Id := EntityName();
                        Title := Id;
                        if TypeAt(Tk) = 'SQS' then begin
                            Tk += 1;
                            Title := EntityName();
                            while IsName(TypeAt(Tk)) do
                                Title += ' ' + EntityName();
                            Expect('SQE');
                        end;
                        Separator();
                        FrameId.Add(Id);
                        FrameTitle.Add(Title);
                    end;
                'acc_title':
                    begin
                        Tk += 1;
                        Value := MText.TrimWs(Expect('acc_title_value'));
                        AccTitle := MText.TrimStartWs(Value);
                        if Nested then
                            AddItem(Value, false);
                    end;
                'acc_descr':
                    begin
                        Tk += 1;
                        Value := MText.TrimWs(Expect('acc_descr_value'));
                        SetAccDescription(Value);
                        if Nested then
                            AddItem(Value, false);
                    end;
                'acc_descr_multiline_value':
                    begin
                        Value := MText.TrimWs(TextAt(Tk));
                        Tk += 1;
                        SetAccDescription(Value);
                        if Nested then
                            AddItem(Value, false);
                    end;
                'direction_tb', 'direction_bt', 'direction_rl', 'direction_lr':
                    begin
                        Tk += 1;
                        Value := UpperCase(CopyStr(T, 11));
                        if Nested then
                            AddItem(Value, true)
                        else
                            DiagramDir := Value;
                    end;
                'CLASSDEF':
                    begin
                        KeywordText := TextAt(Tk);
                        Tk += 1;
                        IdList(Ids);
                        StylesOpt(Styles);
                        Separator();
                        AddClass(Ids, Styles);
                        if Nested then
                            AddItem(KeywordText, false);
                    end;
                'CLASS':
                    begin
                        KeywordText := TextAt(Tk);
                        Tk += 1;
                        IdList(Ids);
                        IdList(ClassList);
                        SetClass(Ids, ClassList);
                        if Nested then
                            AddItem(KeywordText, false);
                    end;
                'STYLE':
                    begin
                        KeywordText := TextAt(Tk);
                        Tk += 1;
                        IdList(Ids);
                        StylesOpt(Styles);
                        Separator();
                        AddCssStyles(Ids, Styles);
                        if Nested then
                            AddItem(KeywordText, false);
                    end;
                else begin
                    if not IsName(T) then
                        if Nested then
                            ParseFail('''END'', ' + LineList())
                        else
                            ParseFail(LineList());
                    EntityStatement(Names);
                    if Nested then
                        foreach Value in Names do
                            AddItem(Value, false);
                end;
            end;
        until Done;
    end;

    // ================================================================ model (pele's ErDb)

    local procedure AddEntity(Name: Text; Alias: Text): Integer
    var
        Idx: Integer;
    begin
        if EntIndex.Get(Name, Idx) then begin
            if (EntAlias.Get(Idx) = '') and (Alias <> '') then
                EntAlias.Set(Idx, Alias);
            exit(Idx);
        end;
        EntName.Add(Name);
        EntId.Add('entity-' + Name + '-' + MText.IntText(EntName.Count() - 1));
        EntAlias.Add(Alias);
        EntClasses.Add('default');
        EntStyles.Add('');
        Idx := EntName.Count();
        EntIndex.Add(Name, Idx);
        exit(Idx);
    end;

    local procedure AddAttributes(Name: Text; var Types: List of [Text]; var Names: List of [Text]; var KeyTexts: List of [Text]; var Comments: List of [Text])
    var
        Idx: Integer;
        I: Integer;
    begin
        Idx := AddEntity(Name, '');
        for I := 1 to Types.Count() do begin
            AttrEnt.Add(Idx);
            AttrType.Add(Types.Get(I));
            AttrName.Add(Names.Get(I));
            AttrKeys.Add(KeyTexts.Get(I));
            AttrComment.Add(Comments.Get(I));
        end;
    end;

    local procedure AddRelationship(EntA: Text; RoleText: Text; EntB: Text; CardA: Text; Identifying: Boolean; CardB: Text)
    begin
        if SgLookup.ContainsKey(EntA) then
            RelA.Add(EntA)
        else
            RelA.Add(EntId.Get(AddEntity(EntA, '')));
        if SgLookup.ContainsKey(EntB) then
            RelB.Add(EntB)
        else
            RelB.Add(EntId.Get(AddEntity(EntB, '')));
        RelRole.Add(RoleText);
        RelCardA.Add(CardA);
        RelCardB.Add(CardB);
        RelIdentifying.Add(Identifying);
    end;

    local procedure AppendJoined(Existing: Text; Value: Text; Sep: Text): Text
    begin
        if Existing = '' then
            exit(Value);
        exit(Existing + Sep + Value);
    end;

    local procedure AddCssStyles(var Ids: List of [Text]; var Styles: List of [Text])
    var
        Id: Text;
        Style: Text;
        Idx: Integer;
    begin
        foreach Id in Ids do begin
            if EntIndex.Get(Id, Idx) then
                foreach Style in Styles do
                    EntStyles.Set(Idx, AppendJoined(EntStyles.Get(Idx), Style, MText.LF()));
            if SgLookup.Get(Id, Idx) then
                foreach Style in Styles do
                    SgStyles.Set(Idx, AppendJoined(SgStyles.Get(Idx), Style, MText.LF()));
        end;
    end;

    local procedure AddClass(var Ids: List of [Text]; var Styles: List of [Text])
    var
        Id: Text;
        Style: Text;
        Pos: Integer;
        TextStyle: Text;
    begin
        foreach Id in Ids do begin
            if not ClassStyles.ContainsKey(Id) then begin
                ClassStyles.Add(Id, '');
                ClassTextStyles.Add(Id, '');
            end;
            foreach Style in Styles do begin
                if Style.Contains('color') then begin
                    TextStyle := Style;
                    Pos := StrPos(TextStyle, 'fill');
                    if Pos > 0 then
                        TextStyle := CopyStr(TextStyle, 1, Pos - 1) + 'bgFill' + CopyStr(TextStyle, Pos + 4);
                    ClassTextStyles.Set(Id, AppendJoined(ClassTextStyles.Get(Id), TextStyle, MText.LF()));
                end;
                ClassStyles.Set(Id, AppendJoined(ClassStyles.Get(Id), Style, MText.LF()));
            end;
        end;
    end;

    local procedure SetClass(var Ids: List of [Text]; var ClassList: List of [Text])
    var
        Id: Text;
    begin
        foreach Id in Ids do
            SetClassOn(Id, ClassList);
    end;

    local procedure SetClassOn(Id: Text; var ClassList: List of [Text])
    var
        ClassName: Text;
        Idx: Integer;
    begin
        if EntIndex.Get(Id, Idx) then
            foreach ClassName in ClassList do
                EntClasses.Set(Idx, EntClasses.Get(Idx) + ' ' + ClassName);
        if SgLookup.Get(Id, Idx) then
            foreach ClassName in ClassList do
                SgClasses.Set(Idx, AppendJoined(SgClasses.Get(Idx), ClassName, ' '));
    end;

    /// <summary>Records the subgraph of the frame at Depth from the items listed in it, and drops those items.</summary>
    local procedure AddSubGraph(IdText: Text; Depth: Integer; TitleText: Text): Text
    var
        Seen: Dictionary of [Text, Boolean];
        Nodes: List of [Text];
        Id: Text;
        Item: Text;
        Trimmed: Text;
        DirValue: Text;
        Node: Text;
        K: Integer;
        Idx: Integer;
    begin
        Id := MText.TrimWs(IdText);
        for K := 1 to ItemDepth.Count() do
            if ItemDepth.Get(K) = Depth then
                if ItemIsDir.Get(K) then
                    DirValue := ItemText.Get(K)
                else begin
                    Item := ItemText.Get(K);
                    Trimmed := MText.TrimWs(Item);
                    if Trimmed <> '' then
                        if not Seen.ContainsKey(Trimmed) then begin
                            Seen.Add(Trimmed, true);
                            // A node belongs to the first subgraph that lists it.
                            if not Claimed.ContainsKey(Item) then
                                Nodes.Add(Item);
                        end;
                end;
        for K := ItemDepth.Count() downto 1 do
            if ItemDepth.Get(K) = Depth then begin
                ItemDepth.RemoveAt(K);
                ItemText.RemoveAt(K);
                ItemIsDir.RemoveAt(K);
            end;
        foreach Node in Nodes do
            if not Claimed.ContainsKey(Node) then
                Claimed.Add(Node, true);
        SgId.Add(Id);
        SgTitle.Add(MText.TrimWs(TitleText));
        SgClasses.Add('');
        SgStyles.Add('');
        SgDir.Add(DirValue);
        Idx := SgId.Count();
        foreach Node in Nodes do begin
            SgNodeOwner.Add(Idx);
            SgNodeName.Add(Node);
        end;
        if SgLookup.ContainsKey(Id) then
            SgLookup.Set(Id, Idx)
        else
            SgLookup.Add(Id, Idx);
        exit(Id);
    end;

    local procedure SetAccDescription(Value: Text)
    var
        Result: TextBuilder;
        I: Integer;
        N: Integer;
    begin
        N := StrLen(Value);
        I := 1;
        while I <= N do
            if (Value[I] = 10) and MText.IsSpace(MText.CharAt(Value, I + 1)) then begin
                Result.Append(MText.LF());
                I += 1;
                while MText.IsSpace(MText.CharAt(Value, I)) do
                    I += 1;
            end else begin
                Result.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        AccDescr := Result.ToText();
    end;

    // ================================================================ graph (pele's buildErGraph)

    local procedure Compiled(ClassNamesText: Text; var Styles: List of [Text])
    var
        Parts: List of [Text];
        ClassName: Text;
        Joined: Text;
        Style: Text;
    begin
        Parts := ClassNamesText.Split(' ');
        foreach ClassName in Parts do
            if ClassStyles.Get(ClassName, Joined) then begin
                if Joined <> '' then
                    foreach Style in Joined.Split(MText.LF()) do
                        Styles.Add(MText.TrimWs(Style));
                Joined := ClassTextStyles.Get(ClassName);
                if Joined <> '' then
                    foreach Style in Joined.Split(MText.LF()) do
                        Styles.Add(MText.TrimWs(Style));
            end;
    end;

    local procedure JoinStyles(ClassNamesText: Text; Own: Text): Text
    var
        Styles: List of [Text];
        Style: Text;
        Result: Text;
    begin
        Compiled(ClassNamesText, Styles);
        if Own <> '' then
            foreach Style in Own.Split(MText.LF()) do
                Styles.Add(Style);
        foreach Style in Styles do
            Result := AppendJoined(Result, Style, MText.LF());
        exit(Result);
    end;

    local procedure AddGraphNode(Id: Text; LabelText: Text; Alias: Text; IsGroup: Boolean; var ParentOf: Dictionary of [Text, Text]; ParentKey: Text; Styles: Text; Classes: Text; Dir: Text; Ent: Integer)
    var
        ParentId: Text;
    begin
        NId.Add(Id);
        NLabel.Add(LabelText);
        NAlias.Add(Alias);
        NIsGroup.Add(IsGroup);
        if ParentOf.Get(ParentKey, ParentId) then begin
            NParentId.Add(ParentId);
            NHasParent.Add(true);
        end else begin
            NParentId.Add('');
            NHasParent.Add(false);
        end;
        NStyles.Add(Styles);
        NClasses.Add(Classes);
        NDir.Add(Dir);
        NEnt.Add(Ent);
        NParent.Add(0);
    end;

    local procedure BuildGraph()
    var
        ParentOf: Dictionary of [Text, Text];
        SubgraphIds: Dictionary of [Text, Boolean];
        Moved: Dictionary of [Text, Text];
        I: Integer;
        K: Integer;
        P: Integer;
        Name: Text;
        Target: Text;
        CardText: Text;
    begin
        for I := SgId.Count() downto 1 do begin
            if not SubgraphIds.ContainsKey(SgId.Get(I)) then
                SubgraphIds.Add(SgId.Get(I), true);
            for K := 1 to SgNodeOwner.Count() do
                if SgNodeOwner.Get(K) = I then
                    if ParentOf.ContainsKey(SgNodeName.Get(K)) then
                        ParentOf.Set(SgNodeName.Get(K), SgId.Get(I))
                    else
                        ParentOf.Add(SgNodeName.Get(K), SgId.Get(I));
        end;
        for I := SgId.Count() downto 1 do
            AddGraphNode(SgId.Get(I), SgTitle.Get(I), '', true, ParentOf, SgId.Get(I), JoinStyles(SgClasses.Get(I), SgStyles.Get(I)), SgClasses.Get(I), SgDir.Get(I), 0);

        // A name that is also a subgraph id stands for the subgraph. Mermaid drops such an entity and
        // leaves relationships written before the subgraph pointing at nothing; here they follow it.
        for I := 1 to EntName.Count() do begin
            Name := EntName.Get(I);
            if SubgraphIds.ContainsKey(Name) then begin
                if not Moved.ContainsKey(EntId.Get(I)) then
                    Moved.Add(EntId.Get(I), Name);
            end else
                AddGraphNode(EntId.Get(I), Name, EntAlias.Get(I), false, ParentOf, Name, JoinStyles(EntClasses.Get(I), EntStyles.Get(I)), EntClasses.Get(I), '', I);
        end;

        for I := 1 to NId.Count() do
            if NodeIndex.ContainsKey(NId.Get(I)) then
                NodeIndex.Set(NId.Get(I), I)
            else
                NodeIndex.Add(NId.Get(I), I);
        for I := 1 to NId.Count() do
            if NHasParent.Get(I) then
                if NodeIndex.Get(NParentId.Get(I), P) then
                    NParent.Set(I, P);

        for I := 1 to RelA.Count() do begin
            GEdgeId.Add('id_' + RelA.Get(I) + '_' + RelB.Get(I) + '_' + MText.IntText(I - 1));
            if Moved.Get(RelA.Get(I), Target) then
                GStart.Add(Target)
            else
                GStart.Add(RelA.Get(I));
            if Moved.Get(RelB.Get(I), Target) then
                GEnd.Add(Target)
            else
                GEnd.Add(RelB.Get(I));
            GLabel.Add(RelRole.Get(I));
            CardText := LowerCase(RelCardB.Get(I));
            GArrowStart.Add(CardText);
            CardText := LowerCase(RelCardA.Get(I));
            GArrowEnd.Add(CardText);
            GDashed.Add(not RelIdentifying.Get(I));
        end;
    end;

    // ================================================================ generics (pele's common/generics.ts)

    local procedure Tildes(Value: Text): Integer
    var
        I: Integer;
        Result: Integer;
    begin
        for I := 1 to StrLen(Value) do
            if Value[I] = 126 then
                Result += 1;
        exit(Result);
    end;

    // Pairs tildes from the outside in: the first with the last, the second with the one before it.
    local procedure PairTildes(Value: Text): Text
    var
        At: List of [Integer];
        Result: Text;
        Total: Integer;
        I: Integer;
        Lo: Integer;
        Hi: Integer;
        StartAtPos: Integer;
    begin
        Total := Tildes(Value);
        if Total <= 1 then
            exit(Value);
        StartAtPos := 1;
        if (Total mod 2 <> 0) and Value.StartsWith('~') then
            StartAtPos := 2;
        for I := StartAtPos to StrLen(Value) do
            if Value[I] = 126 then
                At.Add(I);
        Result := Value;
        Lo := 1;
        Hi := At.Count();
        while Lo < Hi do begin
            Result[At.Get(Lo)] := '<';
            Result[At.Get(Hi)] := '>';
            Lo += 1;
            Hi -= 1;
        end;
        exit(Result);
    end;

    // Turns `List~int~` into `List<int>`, with the quirks of Mermaid's parseGenericTypes around commas.
    local procedure ParseGenericTypes(Input: Text): Text
    var
        Parts: List of [Text];
        Sets: List of [Text];
        Output: List of [Text];
        Part: Text;
        SetText: Text;
        Result: TextBuilder;
        I: Integer;
        First: Boolean;
        Merge: Boolean;
    begin
        if not Input.Contains('~') then
            exit(Input);
        Parts := Input.Split(',');
        First := true;
        foreach Part in Parts do begin
            if not First then
                Sets.Add(',');
            Sets.Add(Part);
            First := false;
        end;
        I := 1;
        while I <= Sets.Count() do begin
            SetText := Sets.Get(I);
            Merge := false;
            if (SetText = ',') and (I > 1) and (I < Sets.Count()) then
                if (Tildes(Sets.Get(I - 1)) = 1) and (Tildes(Sets.Get(I + 1)) = 1) then
                    Merge := true;
            if Merge then begin
                SetText := Sets.Get(I - 1) + ',' + Sets.Get(I + 1);
                I += 1;
                Output.RemoveAt(Output.Count());
            end;
            Output.Add(PairTildes(SetText));
            I += 1;
        end;
        foreach SetText in Output do
            Result.Append(SetText);
        exit(Result.ToText());
    end;

    // Mermaid reads `~` pairs as angle brackets. They are written as entities so the label parser
    // does not take `<int>` for a tag.
    local procedure CellText(Raw: Text): Text
    var
        Converted: Text;
    begin
        Converted := ParseGenericTypes(Raw);
        if Converted = Raw then
            exit(Raw);
        exit(Converted.Replace('<', '&lt;').Replace('>', '&gt;'));
    end;

    // ================================================================ rendering

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

    // The direction of the level a node is laid out in: its nearest subgraph that sets one, or the diagram's.
    local procedure Horizontal(I: Integer): Boolean
    var
        At: Integer;
        Up: Integer;
        Steps: Integer;
        Dir: Text;
    begin
        At := I;
        // Subgraphs can name each other as members, so the walk up is bounded.
        for Steps := 1 to NId.Count() do begin
            Up := NParent.Get(At);
            if Up = 0 then
                break;
            Dir := NDir.Get(Up);
            if Dir <> '' then
                exit((Dir = 'LR') or (Dir = 'RL'));
            At := Up;
        end;
        exit((DiagramDir = 'LR') or (DiagramDir = 'RL'));
    end;

    local procedure NodeLabel(I: Integer; var Lbl: Codeunit "Mermaid Label")
    var
        Name: Text;
    begin
        if NIsGroup.Get(I) then
            Lbl.Layout(NLabel.Get(I), true, VNameSize.Get(I), 4000, VBase.Get(I))
        else begin
            Name := NAlias.Get(I);
            if Name = '' then
                Name := NLabel.Get(I);
            Lbl.Layout(Name, true, VNameSize.Get(I), 240, VBase.Get(I));
        end;
    end;

    /// <summary>Lays out one cell of an attribute row: 1 type, 2 name, 3 keys, 4 comment.</summary>
    local procedure CellLabel(Node: Integer; Attr: Integer; Column: Integer; var Lbl: Codeunit "Mermaid Label")
    begin
        case Column of
            1:
                Lbl.Layout(CellText(AttrType.Get(Attr)), true, VRowSize.Get(Node), 1000000, VBase.Get(Node));
            2:
                Lbl.Layout(CellText(AttrName.Get(Attr)), true, VRowSize.Get(Node), 1000000, VBase.Get(Node));
            3:
                Lbl.Layout(AttrKeys.Get(Attr), false, VKeySize.Get(Node), 1000000, VBase.Get(Node));
            4:
                Lbl.Layout(CellText(AttrComment.Get(Attr)), true, VRowSize.Get(Node), 260, VBase.Get(Node));
        end;
    end;

    local procedure BuildView(I: Integer; Size: Decimal)
    var
        Lbl: Codeunit "Mermaid Label";
        Cell: Codeunit "Mermaid Label";
        Styles: List of [Text];
        Widths: List of [Decimal];
        Style: Text;
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        Below: Boolean;
        StyleSize: Decimal;
        NameSize: Decimal;
        RowSize: Decimal;
        KeySize: Decimal;
        Base: Integer;
        OwnCount: Integer;
        D: Integer;
        A: Integer;
        K: Integer;
        Columns: Integer;
        Band: Decimal;
        Bands: Decimal;
        Reach: Decimal;
        MinW: Decimal;
        PadTop: Decimal;
        NameH: Decimal;
        RowLine: Decimal;
        CellH: Decimal;
        Inner: Decimal;
        Spare: Decimal;
        X: Decimal;
        W: Decimal;
        H: Decimal;
        HeadH: Decimal;
        Room: Decimal;
    begin
        Columns := 0;
        if NStyles.Get(I) <> '' then
            foreach Style in NStyles.Get(I).Split(MText.LF()) do
                Styles.Add(Style);
        Builder.ResolveStyle(Styles, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
        Base := 0;
        if IsBold then
            Base += MText.StyleBold();
        if IsItalic then
            Base += MText.StyleItalic();
        NameSize := Size;
        RowSize := SmallSize;
        KeySize := Round(Size * 0.75, 1);
        if StyleSize > 0 then begin
            NameSize := StyleSize;
            RowSize := StyleSize;
            KeySize := StyleSize;
        end;
        VNameSize.Add(NameSize);
        VRowSize.Add(RowSize);
        VKeySize.Add(KeySize);
        VBase.Add(Base);
        VShapeAttr.Add(ShapeAttr);
        VLineAttr.Add(LineAttr);
        VTextAttr.Add(TextAttr);
        VStroke.Add(Stroke);
        NodeLabel(I, Lbl);

        for D := 1 to DSrc.Count() do
            if DLoop.Get(D) and (DSrc.Get(D) = I) then
                OwnCount += 1;
        // Loops leave by a side the layout keeps free of other edges: the right when ranks run down,
        // the bottom when they run across.
        Below := false;
        if (OwnCount > 0) and not NIsGroup.Get(I) then
            Below := Horizontal(I);
        VBelow.Add(Below);
        for D := 1 to DSrc.Count() do
            if DLoop.Get(D) and (DSrc.Get(D) = I) then begin
                if Below then
                    Band := MText.MaxDec(38, DLabelW.Get(D) + 12)
                else
                    Band := MText.MaxDec(38, DLabelH.Get(D) + 6);
                DBand.Set(D, Band);
                Bands += Band;
                if Below then
                    Reach := MText.MaxDec(Reach, DLabelH.Get(D))
                else
                    Reach := MText.MaxDec(Reach, DLabelW.Get(D));
            end;
        MinW := 96;
        if Below then
            MinW := MText.MaxDec(96, Bands + 8);

        VRowFirst.Add(RowAttr.Count() + 1);
        if NIsGroup.Get(I) then begin
            for K := 1 to 4 do
                VCols.Add(0);
            VW.Add(0);
            VH.Add(0);
            VHeadH.Add(0);
            VRowCount.Add(0);
            Layout.AddNode(0, 0, 0);
            PadTop := 20;
            if Lbl.GetHeight() > 0 then
                PadTop := Lbl.GetHeight() + 16;
            Layout.SetGroup(I, 20, PadTop, 20, MText.MaxDec(Lbl.GetWidth() + 2 * 20 - 12, 96), NDir.Get(I));
            Layout.SetSpan(I, 0);
            exit;
        end;

        NameH := MText.MaxDec(Lbl.GetHeight(), Round(NameSize * 1.5, 1));
        H := 0;
        HeadH := 0;
        for K := 1 to 4 do
            Widths.Add(0);
        for A := 1 to AttrEnt.Count() do
            if AttrEnt.Get(A) = NEnt.Get(I) then begin
                RowLine := Round(RowSize * 1.5, 1);
                CellH := RowLine;
                for K := 1 to 4 do begin
                    CellLabel(I, A, K, Cell);
                    if Cell.GetWidth() > Widths.Get(K) then
                        Widths.Set(K, Cell.GetWidth());
                    if Cell.GetHeight() > CellH then
                        CellH := Cell.GetHeight();
                end;
                RowAttr.Add(A);
                RowH.Add(CellH + 9);
                H += CellH + 9;
            end;
        VRowCount.Add(RowAttr.Count() - VRowFirst.Get(I) + 1);
        if VRowCount.Get(I) = 0 then begin
            W := MText.MaxDec(Lbl.GetWidth() + 2 * 18, MinW);
            if Below then
                H := MText.MaxDec(NameH + 2 * 12, 0)
            else
                H := MText.MaxDec(NameH + 2 * 12, Bands + 8);
            for K := 1 to 4 do
                VCols.Add(0);
        end else begin
            for K := 1 to 4 do
                if Widths.Get(K) > 0 then begin
                    if Columns > 0 then
                        Inner += Widths.Get(K) + 16
                    else
                        Inner += Widths.Get(K);
                    Columns += 1;
                end;
            W := MText.MaxDec(MText.MaxDec(Inner + 2 * 12, Lbl.GetWidth() + 2 * 18), MinW);
            // A box wider than its table shares the spare width between the columns.
            Spare := 0;
            if Columns > 0 then
                Spare := (W - Inner - 2 * 12) / Columns;
            X := 12;
            for K := 1 to 4 do begin
                VCols.Add(X);
                if Widths.Get(K) > 0 then
                    X += Widths.Get(K) + Spare + 16;
            end;
            HeadH := NameH + 2 * 9;
            H += HeadH;
        end;
        VW.Add(W);
        VH.Add(H);
        VHeadH.Add(HeadH);
        // The layout keeps a node centered in its box, so room for loops is added on both sides.
        Room := 0;
        if OwnCount > 0 then
            Room := 2 * (18 + 28 * 0.75 + 10 + Reach);
        if Below then
            Layout.AddNode(W, H + Room, 0)
        else
            Layout.AddNode(W + Room, H, 0);
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Lbl: Codeunit "Mermaid Label";
        Route: List of [Decimal];
        Size: Decimal;
        Pad: Decimal;
        LayoutWidth: Decimal;
        Reach: Decimal;
        TitleHeight: Decimal;
        Inner: Decimal;
        LabelW: Decimal;
        LabelH: Decimal;
        Width: Integer;
        Height: Integer;
        G: Integer;
        I: Integer;
        D: Integer;
        Src1: Integer;
        Dst1: Integer;
        AnyGroup: Boolean;
        Clusters: Text;
        NodesOut: Text;
        EdgesOut: Text;
        LabelsOut: Text;
        Content: Text;
        V: Decimal;
    begin
        BuildGraph();
        Size := MText.FontSize();
        SmallSize := Round(Size * 0.875, 1);
        Pad := 8;

        for G := 1 to GEdgeId.Count() do
            if NodeIndex.Get(GStart.Get(G), Src1) and NodeIndex.Get(GEnd.Get(G), Dst1) then begin
                Lbl.Layout(GLabel.Get(G), true, SmallSize, 200, 0);
                DGraph.Add(G);
                DSrc.Add(Src1);
                DDst.Add(Dst1);
                DLoop.Add(Src1 = Dst1);
                DBand.Add(0);
                DAt.Add(0);
                DLabelW.Add(Lbl.GetWidth());
                DLabelH.Add(Lbl.GetHeight());
            end;

        Layout.Init(DiagramDir, NumberOption(Config, 'er.nodeSpacing', 48), 20, NumberOption(Config, 'er.rankSpacing', 64), 0);
        for I := 1 to NId.Count() do
            BuildView(I, Size);
        for I := 1 to NId.Count() do
            if NParent.Get(I) <> 0 then
                Layout.SetParent(I, NParent.Get(I));
        for D := 1 to DSrc.Count() do begin
            LabelW := 0;
            LabelH := 0;
            if DLabelW.Get(D) > 0 then
                LabelW := DLabelW.Get(D) + 12;
            if DLabelH.Get(D) > 0 then
                LabelH := DLabelH.Get(D) + 4;
            Layout.AddEdge(DSrc.Get(D), DDst.Get(D), 1, LabelW, LabelH);
        end;
        Layout.Execute();

        // A subgraph gets its size from the layout, so its loops hang outside it and may widen the diagram.
        LayoutWidth := Layout.GetWidth();
        for I := 1 to NId.Count() do
            if NIsGroup.Get(I) then begin
                Reach := -1;
                for D := 1 to DSrc.Count() do
                    if DLoop.Get(D) and (DSrc.Get(D) = I) then
                        Reach := MText.MaxDec(Reach, DLabelW.Get(D));
                if Reach >= 0 then
                    LayoutWidth := MText.MaxDec(LayoutWidth, Layout.NodeX(I) + Layout.NodeW(I) / 2 + 18 + 28 * 0.75 + 10 + Reach);
            end;

        TitleLbl.Layout(DiagramTitle, false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 12;
        Inner := MText.MaxDec(LayoutWidth, TitleLbl.GetWidth());
        Layout.Shift(Pad + (Inner - LayoutWidth) / 2, Pad + TitleHeight);
        Width := MText.Ceil(Inner + 2 * Pad);
        Height := MText.Ceil(Layout.GetHeight() + TitleHeight + 2 * Pad);

        for D := 1 to DSrc.Count() do begin
            Layout.EdgeRoute(D, Route);
            DRtStart.Add(RtVals.Count() + 1);
            DRtLen.Add(Route.Count());
            foreach V in Route do
                RtVals.Add(V);
        end;
        for I := 1 to NId.Count() do
            if NIsGroup.Get(I) then begin
                AnyGroup := true;
                VW.Set(I, Layout.NodeW(I));
                VH.Set(I, Layout.NodeH(I));
            end;
        SpreadEnds();

        DrawNodes(Clusters, NodesOut, AnyGroup);
        PlaceLoops();
        DrawEdges(EdgesOut, LabelsOut);

        Content := Builder.TitleSvg(TitleLbl, Width / 2, Pad + TitleLbl.GetHeight() / 2);
        if Clusters <> '' then
            Content += '<g class="pele-clusters">' + Clusters + '</g>';
        if EdgesOut <> '' then
            Content += '<g class="pele-edges" fill="none" stroke="var(--_l)" stroke-linecap="round">' + EdgesOut + '</g>';
        if LabelsOut <> '' then
            Content += '<g class="pele-edge-labels" font-size="' + MText.Num(SmallSize) + '">' + LabelsOut + '</g>';
        Content += '<g class="pele-nodes">' + NodesOut + '</g>';
        exit(Builder.Document('er', Width, Height, Size, AccTitle, AccDescr, Content));
    end;

    // ---------------------------------------------------------------- route ends

    local procedure AddEnd(Node: Integer; Start: Integer; At: Integer; Next: Integer; var EKey: List of [Integer]; var EPos: List of [Integer]; var EToward: List of [Decimal]; var KeyOrder: List of [Integer])
    var
        Dx: Decimal;
        Dy: Decimal;
        Side: Integer;
        KeyNo: Integer;
    begin
        Dx := RtVals.Get(Start + At) - Layout.NodeX(Node);
        Dy := RtVals.Get(Start + At + 1) - Layout.NodeY(Node);
        if Abs(Abs(Dy) - Layout.NodeH(Node) / 2) < 0.5 then begin
            Side := 2;
            if Dy < 0 then
                Side := 0;
        end else
            if Abs(Abs(Dx) - Layout.NodeW(Node) / 2) < 0.5 then begin
                Side := 1;
                if Dx < 0 then
                    Side := 3;
            end else
                exit;
        KeyNo := Node * 4 + Side;
        EKey.Add(KeyNo);
        EPos.Add(Start + At);
        if (Side = 1) or (Side = 3) then
            EToward.Add(RtVals.Get(Start + Next + 1))
        else
            EToward.Add(RtVals.Get(Start + Next));
        if not KeyOrder.Contains(KeyNo) then
            KeyOrder.Add(KeyNo);
    end;

    // The layout brings every edge that ends on one side of a box to the middle of that side, where
    // their markers would cover each other. This spaces them along the side, in the order they fan out.
    local procedure SpreadEnds()
    var
        EKey: List of [Integer];
        EPos: List of [Integer];
        EToward: List of [Decimal];
        KeyOrder: List of [Integer];
        Ends: List of [Integer];
        D: Integer;
        Last: Integer;
        KeyNo: Integer;
        K: Integer;
        J: Integer;
        Item: Integer;
        Node: Integer;
        Vertical: Boolean;
        Moving: Boolean;
        BoxLen: Decimal;
        Step: Decimal;
        Center: Decimal;
        Total: Integer;
    begin
        for D := 1 to DSrc.Count() do begin
            Last := DRtLen.Get(D) - 3;
            if (DSrc.Get(D) <> DDst.Get(D)) and (Last >= 3) then begin
                AddEnd(DSrc.Get(D), DRtStart.Get(D), 0, 3, EKey, EPos, EToward, KeyOrder);
                AddEnd(DDst.Get(D), DRtStart.Get(D), Last, Last - 3, EKey, EPos, EToward, KeyOrder);
            end;
        end;
        foreach KeyNo in KeyOrder do begin
            Clear(Ends);
            for K := 1 to EKey.Count() do
                if EKey.Get(K) = KeyNo then
                    Ends.Add(K);
            Total := Ends.Count();
            if Total >= 2 then begin
                Node := KeyNo div 4;
                Vertical := (KeyNo mod 2) = 1;
                if Vertical then
                    BoxLen := VH.Get(Node)
                else
                    BoxLen := VW.Get(Node);
                Step := MText.MaxDec(MText.MinDec(18, (BoxLen - 2 * 14) / (Total - 1)), 0);
                if Vertical then
                    Center := Layout.NodeY(Node)
                else
                    Center := Layout.NodeX(Node);
                // A stable sort by where each edge heads.
                for K := 2 to Total do begin
                    Item := Ends.Get(K);
                    J := K - 1;
                    Moving := true;
                    while Moving do
                        if J < 1 then
                            Moving := false
                        else
                            if EToward.Get(Ends.Get(J)) > EToward.Get(Item) then begin
                                Ends.Set(J + 1, Ends.Get(J));
                                J -= 1;
                            end else
                                Moving := false;
                    Ends.Set(J + 1, Item);
                end;
                for K := 1 to Total do
                    if Vertical then
                        RtVals.Set(EPos.Get(Ends.Get(K)) + 1, Center + (K - 1 - (Total - 1) / 2) * Step)
                    else
                        RtVals.Set(EPos.Get(Ends.Get(K)), Center + (K - 1 - (Total - 1) / 2) * Step);
            end;
        end;
    end;

    local procedure Straighten(D: Integer; var Output: List of [Decimal])
    var
        Start: Integer;
        Len: Integer;
        K: Integer;
        Prev: Integer;
        Skip: Boolean;
    begin
        Clear(Output);
        Start := DRtStart.Get(D);
        Len := DRtLen.Get(D);
        if Len < 3 then
            exit;
        for K := 0 to 2 do
            Output.Add(RtVals.Get(Start + K));
        K := 3;
        while K < Len do begin
            Prev := Output.Count() - 3;
            Skip := false;
            if K + 3 < Len then
                Skip := Flat(Output, Prev, Start, K, 0) or Flat(Output, Prev, Start, K, 1);
            if not Skip then begin
                Output.Add(RtVals.Get(Start + K));
                Output.Add(RtVals.Get(Start + K + 1));
                Output.Add(RtVals.Get(Start + K + 2));
            end;
            K += 3;
        end;
    end;

    local procedure Flat(var Output: List of [Decimal]; Prev: Integer; Start: Integer; K: Integer; Axis: Integer): Boolean
    begin
        if Abs(Output.Get(Prev + Axis + 1) - RtVals.Get(Start + K + Axis)) >= 0.01 then
            exit(false);
        exit(Abs(RtVals.Get(Start + K + Axis) - RtVals.Get(Start + K + 3 + Axis)) < 0.01);
    end;

    // An entity with a self-relationship is laid out larger than it is drawn; this moves a route end
    // from the side of that larger box onto the entity's own side.
    local procedure Inset(var Route: List of [Decimal]; At: Integer; I: Integer)
    var
        Dx: Decimal;
        Dy: Decimal;
        CW: Decimal;
        CHeight: Decimal;
    begin
        if NIsGroup.Get(I) then
            exit;
        Dx := Route.Get(At) - Layout.NodeX(I);
        Dy := Route.Get(At + 1) - Layout.NodeY(I);
        CW := Layout.NodeW(I);
        CHeight := Layout.NodeH(I);
        if CW <> VW.Get(I) then
            if Abs(Abs(Dx) - CW / 2) < 0.5 then
                Route.Set(At, Route.Get(At) - MText.Sign(Dx) * (CW - VW.Get(I)) / 2);
        if CHeight <> VH.Get(I) then
            if Abs(Abs(Dy) - CHeight / 2) < 0.5 then
                Route.Set(At + 1, Route.Get(At + 1) - MText.Sign(Dy) * (CHeight - VH.Get(I)) / 2);
    end;

    // ---------------------------------------------------------------- drawing

    /// <summary>Where a cluster title sits along the top edge so that edges entering there do not cross it (pele's clusterTitleX).</summary>
    local procedure ClusterTitleX(I: Integer; TitleWidth: Decimal): Decimal
    var
        Xs: List of [Decimal];
        Candidates: List of [Decimal];
        Cx: Decimal;
        Cy: Decimal;
        CW: Decimal;
        CHeight: Decimal;
        Top: Decimal;
        Left: Decimal;
        Half: Decimal;
        Candidate: Decimal;
        X: Decimal;
        Gap: Decimal;
        Best: Decimal;
        BestGap: Decimal;
        K: Integer;
    begin
        Cx := Layout.NodeX(I);
        Cy := Layout.NodeY(I);
        CW := Layout.NodeW(I);
        CHeight := Layout.NodeH(I);
        if TitleWidth = 0 then
            exit(Cx);
        Top := Cy - CHeight / 2;
        Left := Cx - CW / 2;
        Half := TitleWidth / 2;
        Candidates.Add(Left + 20 - 6 + Half);
        Candidates.Add(Cx);
        Candidates.Add(Left + CW - 20 + 6 - Half);
        K := 1;
        while K + 1 <= RtVals.Count() do begin
            if Round(RtVals.Get(K + 1), 1) = Round(Top, 1) then
                Xs.Add(RtVals.Get(K));
            K += 3;
        end;
        if Xs.Count() = 0 then
            exit(Candidates.Get(1));
        Best := Candidates.Get(1);
        BestGap := -1;
        foreach Candidate in Candidates do begin
            Gap := 1000000000;
            foreach X in Xs do
                if (X > Left) and (X < Left + CW) then
                    Gap := MText.MinDec(Gap, Abs(X - Candidate) - Half);
            if Gap >= 6 then
                exit(Candidate);
            if Gap > BestGap + 0.5 then begin
                BestGap := Gap;
                Best := Candidate;
            end;
        end;
        exit(Best);
    end;

    /// <summary>Writes a measured label starting at X, with the baseline of its first line at Y (pele's textLeft).</summary>
    local procedure TextLeft(var Lbl: Codeunit "Mermaid Label"; X: Decimal; Y: Decimal; Attrs: Text): Text
    var
        Svg: Text;
    begin
        if Lbl.LineCount() = 0 then
            exit('');
        Svg := Lbl.ToSvg(X, Y + Lbl.GetHeight() / 2 - Lbl.GetLineHeight() / 2 - Lbl.GetSize() * 0.35, Attrs);
        exit(Svg.Replace(' text-anchor="middle"', ''));
    end;

    local procedure StripDefault(Classes: Text): Text
    begin
        if not Classes.StartsWith('default') then
            exit(Classes);
        Classes := CopyStr(Classes, 8);
        if MText.IsSpace(MText.CharAt(Classes, 1)) then
            Classes := CopyStr(Classes, 2);
        exit(Classes);
    end;

    /// <summary>Whether an internal link to the entity's name may be followed (pele's linkUrl over sanitizeUrl, for plain names).</summary>
    local procedure SafeLink(Url: Text): Boolean
    var
        Lower: Text;
        Scheme: Text;
        Protocol: Text;
        I: Integer;
        C: Integer;
        Colon: Integer;
    begin
        Url := MText.TrimWs(Url);
        if Url = '' then
            exit(false);
        if (MText.CharAt(Url, 1) in [47, 92]) and (MText.CharAt(Url, 2) in [47, 92]) then
            exit(false);
        if (Url[1] = '.') or (Url[1] = '/') then
            exit(true);
        Lower := LowerCase(Url);
        Colon := MText.LastIndexOf(Lower.Split(MText.LF()).Get(1), ':');
        if Colon > 1 then begin
            Protocol := MText.TrimWs(CopyStr(Lower, 1, Colon));
            I := 1;
            while (I <= StrLen(Protocol)) and not MText.IsWord(MText.CharAt(Protocol, I)) do
                I += 1;
            Protocol := CopyStr(Protocol, I);
            if Protocol.StartsWith('javascript') or Protocol.StartsWith('data') or Protocol.StartsWith('vbscript') then
                exit(false);
        end;
        if not MText.IsLetter(MText.CharAt(Lower, 1)) then
            exit(true);
        I := 2;
        C := MText.CharAt(Lower, I);
        while MText.IsLetter(C) or MText.IsDigit(C) or (C in [43, 46, 45]) do begin
            I += 1;
            C := MText.CharAt(Lower, I);
        end;
        if C <> 58 then
            exit(true);
        Scheme := CopyStr(Lower, 1, I - 1);
        exit(Scheme in ['http', 'https', 'mailto', 'tel']);
    end;

    local procedure DrawNodes(var Clusters: Text; var NodesOut: Text; AnyGroup: Boolean)
    var
        Lbl: Codeunit "Mermaid Label";
        Cell: Codeunit "Mermaid Label";
        ClustersBuilder: TextBuilder;
        NodesBuilder: TextBuilder;
        Stripes: TextBuilder;
        Cells: TextBuilder;
        I: Integer;
        R: Integer;
        RowNo: Integer;
        A: Integer;
        Classes: Text;
        TextAttr: Text;
        Shape: Text;
        Name: Text;
        Display: Text;
        Target: Text;
        Body: Text;
        SpanAttr: Text;
        LineColor: Text;
        StripeOpacity: Text;
        X: Decimal;
        Y: Decimal;
        W: Decimal;
        H: Decimal;
        X0: Decimal;
        Y0: Decimal;
        TitleX: Decimal;
        RowLine: Decimal;
        Baseline: Decimal;
        Cols: Integer;
    begin
        for I := 1 to NId.Count() do begin
            NodeLabel(I, Lbl);
            Classes := Builder.ClassNames(StripDefault(NClasses.Get(I)));
            TextAttr := VTextAttr.Get(I);
            if NIsGroup.Get(I) then begin
                X := Layout.NodeX(I) - Layout.NodeW(I) / 2;
                Y := Layout.NodeY(I) - Layout.NodeH(I) / 2;
                if AnyGroup then
                    TitleX := ClusterTitleX(I, Lbl.GetWidth())
                else
                    TitleX := Layout.NodeX(I);
                ClustersBuilder.Append('<g class="pele-cluster' + Classes + '" data-id="' + MText.EscText(NId.Get(I)) + '">' +
                    '<rect x="' + MText.Num(X) + '" y="' + MText.Num(Y) + '" width="' + MText.Num(Layout.NodeW(I)) + '" height="' + MText.Num(Layout.NodeH(I)) +
                    '" rx="' + Builder.Radius() + '" fill="var(--_a)" fill-opacity="0.5" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>' +
                    Lbl.ToSvg(TitleX, Y + 8 + Lbl.GetHeight() / 2, ' class="pele-cluster-label" fill="var(--_m)"' + TextAttr) + '</g>');
            end else begin
                W := VW.Get(I);
                H := VH.Get(I);
                X0 := -W / 2;
                Y0 := -H / 2;
                Shape := 'x="' + MText.Num(X0) + '" y="' + MText.Num(Y0) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) + '" rx="' + Builder.Radius() + '"';
                if VRowCount.Get(I) > 0 then
                    Name := Lbl.ToSvg(0, Y0 + VHeadH.Get(I) / 2, ' class="pele-label"' + TextAttr)
                else
                    Name := Lbl.ToSvg(0, 0, ' class="pele-label"' + TextAttr);
                Display := NAlias.Get(I);
                if Display = '' then
                    Display := NLabel.Get(I);
                Display := MText.DecodeEntities(Display);
                if (StrPos(Classes + ' ', ' internal-link ') > 0) and (Name <> '') then begin
                    // The name ends up in an href, so it gets the same check as a URL.
                    Target := MText.Esc(Display);
                    if SafeLink(Display) then
                        Name := '<a class="internal-link" href="' + Target + '" rel="noopener" data-href="' + Target + '">' + Name + '</a>'
                    else
                        Name := '<a class="internal-link" data-href="' + Target + '">' + Name + '</a>';
                end;

                if VRowCount.Get(I) = 0 then
                    Body := '<rect ' + Shape + ' fill="var(--_s)" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>' + Name
                else begin
                    RowLine := Round(VRowSize.Get(I) * 1.5, 1);
                    LineColor := 'var(--_b)';
                    if VStroke.Get(I) <> '' then
                        LineColor := MText.Esc(VStroke.Get(I));
                    Clear(Stripes);
                    Clear(Cells);
                    Y := Y0 + VHeadH.Get(I);
                    Cols := (I - 1) * 4;
                    for R := 1 to VRowCount.Get(I) do begin
                        RowNo := VRowFirst.Get(I) + R - 1;
                        A := RowAttr.Get(RowNo);
                        if (R - 1) mod 2 = 0 then begin
                            SpanAttr := 'x="' + MText.Num(X0) + '" width="' + MText.Num(W) + '"';
                            if R = VRowCount.Get(I) then
                                // The last row follows the box's rounded bottom corners: a rounded rect, squared off on top.
                                Stripes.Append('<rect ' + SpanAttr + ' y="' + MText.Num(Y) + '" height="' + MText.Num(RowH.Get(RowNo)) + '" rx="' + Builder.Radius() + '"/>' +
                                               '<rect ' + SpanAttr + ' y="' + MText.Num(Y) + '" height="' + MText.Num(RowH.Get(RowNo) / 2) + '"/>')
                            else
                                Stripes.Append('<rect ' + SpanAttr + ' y="' + MText.Num(Y) + '" height="' + MText.Num(RowH.Get(RowNo)) + '"/>');
                        end;
                        Baseline := Y + 9 / 2 + RowLine / 2 + VRowSize.Get(I) * 0.35;
                        CellLabel(I, A, 1, Cell);
                        Cells.Append(TextLeft(Cell, X0 + VCols.Get(Cols + 1), Baseline, ' class="pele-er-type" fill="var(--_m)"' + TextAttr));
                        CellLabel(I, A, 2, Cell);
                        Cells.Append(TextLeft(Cell, X0 + VCols.Get(Cols + 2), Baseline, ' class="pele-er-name"' + TextAttr));
                        CellLabel(I, A, 3, Cell);
                        Cells.Append(TextLeft(Cell, X0 + VCols.Get(Cols + 3), Baseline, ' class="pele-er-keys" font-size="' + MText.Num(VKeySize.Get(I)) + '" fill="var(--_m)"' + TextAttr));
                        CellLabel(I, A, 4, Cell);
                        Cells.Append(TextLeft(Cell, X0 + VCols.Get(Cols + 4), Baseline, ' class="pele-er-comment" fill="var(--_m)"' + TextAttr));
                        Y += RowH.Get(RowNo);
                    end;
                    // Over a fill the diagram chose, the shading is a tint of that fill. The opacity is on the
                    // group because the two parts of the last row overlap.
                    StripeOpacity := '';
                    if VShapeAttr.Get(I).Contains('fill:') then
                        StripeOpacity := ' opacity="0.6"';
                    Body := '<rect ' + Shape + ' fill="var(--_s)" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>' +
                            '<g class="pele-er-stripes" fill="var(--_bg)"' + StripeOpacity + '>' + Stripes.ToText() + '</g>' +
                            '<path class="pele-er-divider" d="M' + MText.Num(X0) + ',' + MText.Num(Y0 + VHeadH.Get(I)) + 'H' + MText.Num(X0 + W) + '" stroke="' + LineColor + '"/>' +
                            '<rect ' + Shape + ' fill="none" stroke="var(--_b)"' + VLineAttr.Get(I) + '/>' +
                            Name +
                            '<g class="pele-er-attributes" font-size="' + MText.Num(VRowSize.Get(I)) + '">' + Cells.ToText() + '</g>';
                end;
                NodesBuilder.Append('<g class="pele-node pele-entity' + Classes + '" data-id="' + MText.EscText(NLabel.Get(I)) + '" transform="translate(' +
                                    Builder.P(Layout.NodeX(I), Layout.NodeY(I)) + ')">' + Body + '</g>');
            end;
        end;
        Clusters := ClustersBuilder.ToText();
        NodesOut := NodesBuilder.ToText();
    end;

    // Self-relationships share the side they loop out of, squeezed together if it is too short for them.
    local procedure PlaceLoops()
    var
        I: Integer;
        D: Integer;
        Total: Decimal;
        Scale: Decimal;
        At: Decimal;
        Band: Decimal;
        SideLen: Decimal;
    begin
        for I := 1 to NId.Count() do begin
            Total := 0;
            for D := 1 to DSrc.Count() do
                if DLoop.Get(D) and (DSrc.Get(D) = I) then
                    Total += DBand.Get(D);
            if Total > 0 then begin
                if VBelow.Get(I) then
                    SideLen := VW.Get(I)
                else
                    SideLen := VH.Get(I);
                Scale := MText.MinDec(1, MText.MaxDec(SideLen - 8, 0) / Total);
                At := -Total * Scale / 2;
                for D := 1 to DSrc.Count() do
                    if DLoop.Get(D) and (DSrc.Get(D) = I) then begin
                        Band := DBand.Get(D) * Scale;
                        DBand.Set(D, Band);
                        DAt.Set(D, At + Band / 2);
                        At += Band;
                    end;
            end;
        end;
    end;

    // Draws a crow's foot cardinality marker over the end of a line that meets a box at (X, Y)
    // while travelling along the unit vector (Dx, Dy). Types are Mermaid's lower-cased cardinalities.
    local procedure ErMarker(MarkerType: Text; X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal): Text
    var
        Foot: Text;
    begin
        Foot := 'M' + MarkerAt(X, Y, Dx, Dy, 0, -6) + 'L' + MarkerAt(X, Y, Dx, Dy, 10, 0) + 'L' + MarkerAt(X, Y, Dx, Dy, 0, 6);
        case MarkerType of
            'only_one':
                exit(MarkerPath(MarkerBar(X, Y, Dx, Dy, 6) + MarkerBar(X, Y, Dx, Dy, 10)));
            'zero_or_one':
                exit(MarkerPath(MarkerBar(X, Y, Dx, Dy, 6)) + MarkerRing(X, Y, Dx, Dy, 13.5));
            'one_or_more':
                exit(MarkerPath(Foot + MarkerBar(X, Y, Dx, Dy, 10 + 3.5)));
            'zero_or_more':
                exit(MarkerPath(Foot) + MarkerRing(X, Y, Dx, Dy, 10 + 3.5 + 0.5));
            'md_parent':
                exit('<path class="pele-marker" d="M' + MarkerAt(X, Y, Dx, Dy, 0, 0) + 'L' + MarkerAt(X, Y, Dx, Dy, 6, 4) + 'L' +
                     MarkerAt(X, Y, Dx, Dy, 12, 0) + 'L' + MarkerAt(X, Y, Dx, Dy, 6, -4) + 'Z" fill="var(--_bg)"/>');
        end;
        exit('');
    end;

    local procedure MarkerAt(X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal; Back: Decimal; Side: Decimal): Text
    begin
        exit(MText.Num(X - Dx * Back - Dy * Side) + ',' + MText.Num(Y - Dy * Back + Dx * Side));
    end;

    local procedure MarkerBar(X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal; Back: Decimal): Text
    begin
        exit('M' + MarkerAt(X, Y, Dx, Dy, Back, -5) + 'L' + MarkerAt(X, Y, Dx, Dy, Back, 5));
    end;

    local procedure MarkerRing(X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal; Back: Decimal): Text
    begin
        exit('<circle class="pele-marker" cx="' + MText.Num(X - Dx * Back) + '" cy="' + MText.Num(Y - Dy * Back) + '" r="3.5" fill="var(--_bg)"/>');
    end;

    local procedure MarkerPath(D: Text): Text
    begin
        exit('<path class="pele-marker" d="' + D + '"/>');
    end;

    local procedure DrawEdges(var EdgesOut: Text; var LabelsOut: Text)
    var
        Lbl: Codeunit "Mermaid Label";
        Route: List of [Decimal];
        EdgesBuilder: TextBuilder;
        LabelsBuilder: TextBuilder;
        D: Integer;
        G: Integer;
        S: Integer;
        Last: Integer;
        Drawn: Boolean;
        Direct: Boolean;
        Dashed: Boolean;
        Path: Text;
        StartMarker: Text;
        EndMarker: Text;
        Turn: Text;
        OutAt: Text;
        Spread: Decimal;
        Far: Decimal;
        X: Decimal;
        Y: Decimal;
        Dx: Decimal;
        Dy: Decimal;
        Stub: Decimal;
        LabelX: Decimal;
        LabelY: Decimal;
        Sx: Decimal;
        Sy: Decimal;
        Sdx: Decimal;
        Sdy: Decimal;
        Ex: Decimal;
        Ey: Decimal;
        Edx: Decimal;
        Edy: Decimal;
    begin
        for D := 1 to DSrc.Count() do begin
            G := DGraph.Get(D);
            S := DSrc.Get(D);
            Lbl.Layout(GLabel.Get(G), true, SmallSize, 200, 0);
            Drawn := true;
            if DLoop.Get(D) then begin
                Spread := MText.MaxDec(MText.MinDec(DBand.Get(D) / 2 - 6, 13), 1);
                Far := 18 + 28 * 0.75 + 6;
                if VBelow.Get(S) then begin
                    X := Layout.NodeX(S) + DAt.Get(D);
                    Y := Layout.NodeY(S) + VH.Get(S) / 2;
                    Turn := MText.Num(Y + 18);
                    OutAt := MText.Num(Y + 18 + 28);
                    Path := 'M' + MText.Num(X - Spread) + ',' + MText.Num(Y) + 'V' + Turn + 'C' + MText.Num(X - Spread) + ',' + OutAt + ' ' +
                            MText.Num(X + Spread) + ',' + OutAt + ' ' + MText.Num(X + Spread) + ',' + Turn + 'V' + MText.Num(Y);
                    StartMarker := ErMarker(GArrowStart.Get(G), X - Spread, Y, 0, -1);
                    EndMarker := ErMarker(GArrowEnd.Get(G), X + Spread, Y, 0, -1);
                    LabelX := X;
                    LabelY := Y + Far + Lbl.GetHeight() / 2;
                end else begin
                    X := Layout.NodeX(S) + VW.Get(S) / 2;
                    Y := Layout.NodeY(S) + DAt.Get(D);
                    Turn := MText.Num(X + 18);
                    OutAt := MText.Num(X + 18 + 28);
                    Path := 'M' + MText.Num(X) + ',' + MText.Num(Y - Spread) + 'H' + Turn + 'C' + OutAt + ',' + MText.Num(Y - Spread) + ' ' +
                            OutAt + ',' + MText.Num(Y + Spread) + ' ' + Turn + ',' + MText.Num(Y + Spread) + 'H' + MText.Num(X);
                    StartMarker := ErMarker(GArrowStart.Get(G), X, Y - Spread, -1, 0);
                    EndMarker := ErMarker(GArrowEnd.Get(G), X, Y + Spread, -1, 0);
                    LabelX := X + Far + Lbl.GetWidth() / 2;
                    LabelY := Y;
                end;
            end else begin
                Straighten(D, Route);
                if Route.Count() < 6 then
                    Drawn := false
                else begin
                    Last := Route.Count() - 2;
                    Inset(Route, 1, S);
                    Inset(Route, Last, DDst.Get(D));
                    // A curve stops short of each box so that the marker sits on a straight run of line.
                    Dx := Abs(Route.Get(Last) - Route.Get(1));
                    Dy := Abs(Route.Get(Last + 1) - Route.Get(2));
                    Direct := false;
                    if Route.Count() = 6 then
                        Direct := (Dx < 0.01) or (Dy < 0.01) or (MText.Hypot(Dx, Dy) <= 3 * 18);
                    Stub := 18;
                    if Direct then
                        Stub := 0;
                    Builder.RoutePath(Route, '', Stub, Stub, Path, Sx, Sy, Sdx, Sdy, Ex, Ey, Edx, Edy);
                    if Stub > 0 then
                        Path := 'M' + MText.Num(Sx) + ',' + MText.Num(Sy) + 'L' + CopyStr(Path, 2) + 'L' + MText.Num(Ex) + ',' + MText.Num(Ey);
                    StartMarker := ErMarker(GArrowStart.Get(G), Sx, Sy, Sdx, Sdy);
                    EndMarker := ErMarker(GArrowEnd.Get(G), Ex, Ey, Edx, Edy);
                    LabelX := Layout.EdgeLabelX(D);
                    LabelY := Layout.EdgeLabelY(D);
                end;
            end;
            if Drawn then begin
                Dashed := GDashed.Get(G);
                if Dashed then
                    EdgesBuilder.Append('<g class="pele-edge pele-er-non-identifying" data-id="' + MText.EscText(GEdgeId.Get(G)) + '">' +
                                        '<path d="' + Path + '" stroke-dasharray="4 3"/>' + StartMarker + EndMarker + '</g>')
                else
                    EdgesBuilder.Append('<g class="pele-edge pele-er-identifying" data-id="' + MText.EscText(GEdgeId.Get(G)) + '">' +
                                        '<path d="' + Path + '"/>' + StartMarker + EndMarker + '</g>');
                if Lbl.GetWidth() > 0 then
                    LabelsBuilder.Append(Builder.EdgeLabelSvg(GEdgeId.Get(G), Lbl, LabelX, LabelY, ''));
            end;
        end;
        EdgesOut := EdgesBuilder.ToText();
        LabelsOut := LabelsBuilder.ToText();
    end;
}
