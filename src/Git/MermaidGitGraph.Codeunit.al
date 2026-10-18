/// <summary>
/// Port of pele's diagrams/git: parser.ts (the Langium token table and a hand-written parser), db.ts (the
/// commit, branch, merge, cherry-pick and checkout calls Mermaid's parser makes on its database) and
/// render.ts (lanes, commits, connectors, ids and tags, left to right, top to bottom or bottom to top).
/// pele's responsive turn from LR to TB (turnToFit) is left out: a graph is drawn in its own direction.
/// </summary>
codeunit 68917 "Mermaid Git Graph"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Src: Text;
        // Tokens: kind (-1 for the end of input), start and end (exclusive), 1-based.
        TokKinds: List of [Integer];
        TokStarts: List of [Integer];
        TokEnds: List of [Integer];
        TokI: Integer;
        AccDescrDead: Boolean;
        YamlDead: Boolean;
        DirectiveDead: Boolean;
        // Statements: 1 commit, 2 branch, 3 merge, 4 checkout, 5 cherry-pick.
        StKind: List of [Integer];
        StName: List of [Text];
        StId: List of [Text];
        StMsg: List of [Text];
        StType: List of [Integer];
        StOrder: List of [Decimal];
        StParent: List of [Text];
        StTagFrom: List of [Integer];
        StTagCount: List of [Integer];
        StTags: List of [Text];
        // The model.
        GitTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        Direction: Text;
        CId: List of [Text];
        CMsg: List of [Text];
        CSeq: List of [Integer];
        CType: List of [Integer];
        CCustomType: List of [Integer];
        CCustomId: List of [Boolean];
        CBranch: List of [Text];
        CParent1: List of [Text];
        CParent2: List of [Text];
        CParentCount: List of [Integer];
        CTagFrom: List of [Integer];
        CTagCount: List of [Integer];
        CAlive: List of [Boolean];
        CTags: List of [Text];
        IdIndex: Dictionary of [Text, Integer];
        BranchHead: Dictionary of [Text, Text];
        OrderNames: List of [Text];
        OrderValues: List of [Decimal];
        Lanes: List of [Text];
        CurrentBranch: Text;
        HeadIdx: Integer;
        Seq: Integer;

    // ---------------------------------------------------------------- token kinds (pele's const enum T)
    // 0 cherry-pick, 1 gitGraph:, 2 HIGHLIGHT, 3 gitGraph, 4 checkout, 5 REVERSE, 6 parent:, 7 commit,
    // 8 NORMAL, 9 branch, 10 order:, 11 switch, 12 type:, 13 merge, 14 msg:, 15 tag:, 16 id:, 17 LR,
    // 18 TB, 19 BT, 20 :, 21 ACC_DESCR, 22 ACC_TITLE, 23 TITLE, 24 INT, 25 STRING, 26 NEWLINE,
    // 27 WHITESPACE, 28 YAML, 29 DIRECTIVE, 30 SINGLE_LINE_COMMENT, 31 REFERENCE.

    local procedure KindName(KindNo: Integer): Text
    begin
        case KindNo of
            3:
                exit('gitGraph');
            24:
                exit('INT');
            25:
                exit('STRING');
        end;
        exit('');
    end;

    local procedure IsHidden(KindNo: Integer): Boolean
    begin
        exit(KindNo in [27, 28, 29, 30]);
    end;

    local procedure HasLonger(KindNo: Integer): Boolean
    begin
        exit(KindNo in [0, 2, 3, 4, 5, 7, 8, 9, 11, 13, 17, 18, 19]);
    end;

    // ---------------------------------------------------------------- lexing

    local procedure Tokenize()
    var
        P: Integer;
        N: Integer;
        K: Integer;
        E: Integer;
        KindNo: Integer;
        AltEnd: Integer;
        Matched: Boolean;
    begin
        Clear(TokKinds);
        Clear(TokStarts);
        Clear(TokEnds);
        AccDescrDead := false;
        YamlDead := false;
        DirectiveDead := false;
        N := StrLen(Src);
        P := 1;
        while P <= N do begin
            Matched := false;
            for K := 0 to 31 do begin
                E := MatchAt(K, P);
                if E > P then begin
                    KindNo := K;
                    if HasLonger(K) then begin
                        AltEnd := MatchAt(31, P);
                        if AltEnd > E then begin
                            KindNo := 31;
                            E := AltEnd;
                        end;
                    end;
                    if not IsHidden(KindNo) then begin
                        TokKinds.Add(KindNo);
                        TokStarts.Add(P);
                        TokEnds.Add(E);
                    end;
                    P := E;
                    Matched := true;
                    break;
                end;
            end;
            if not Matched then
                MText.SyntaxError('gitGraph', Src, P, '', true);
        end;
        TokKinds.Add(-1);
        TokStarts.Add(N + 1);
        TokEnds.Add(N + 1);
    end;

    local procedure MatchAt(KindNo: Integer; P: Integer): Integer
    begin
        case KindNo of
            0:
                exit(Lit('cherry-pick', P));
            1:
                exit(Lit('gitGraph:', P));
            2:
                exit(Lit('HIGHLIGHT', P));
            3:
                exit(MatchGitGraph(P));
            4:
                exit(Lit('checkout', P));
            5:
                exit(Lit('REVERSE', P));
            6:
                exit(Lit('parent:', P));
            7:
                exit(Lit('commit', P));
            8:
                exit(Lit('NORMAL', P));
            9:
                exit(Lit('branch', P));
            10:
                exit(Lit('order:', P));
            11:
                exit(Lit('switch', P));
            12:
                exit(Lit('type:', P));
            13:
                exit(Lit('merge', P));
            14:
                exit(Lit('msg:', P));
            15:
                exit(Lit('tag:', P));
            16:
                exit(Lit('id:', P));
            17:
                exit(Lit('LR', P));
            18:
                exit(Lit('TB', P));
            19:
                exit(Lit('BT', P));
            20:
                exit(Lit(':', P));
            21:
                exit(MatchAccDescr(P));
            22:
                exit(MatchAccTitle(P));
            23:
                exit(MatchTitle(P));
            24:
                exit(MatchInt(P));
            25:
                exit(MatchString(P));
            26:
                exit(MatchNewline(P));
            27:
                exit(MatchWhitespace(P));
            28:
                exit(MatchYaml(P));
            29:
                exit(MatchDirective(P));
            30:
                exit(MatchComment(P));
            31:
                exit(MatchReference(P));
        end;
        exit(-1);
    end;

    local procedure Lit(Value: Text; P: Integer): Integer
    begin
        if MText.CharAt(Src, P) <> Value[1] then
            exit(-1);
        if MText.StartsWithAt(Src, Value, P) then
            exit(P + StrLen(Value));
        exit(-1);
    end;

    local procedure SkipBlanks(P: Integer): Integer
    begin
        while MText.IsBlank(MText.CharAt(Src, P)) do
            P += 1;
        exit(P);
    end;

    local procedure IsCrLf(C: Integer): Boolean
    begin
        exit((C = 10) or (C = 13));
    end;

    /// <summary>Where `[^\n\r]*?(?=%%)|[^\n\r]*` starting at P ends.</summary>
    local procedure LazyToComment(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        while (C <> -1) and not IsCrLf(C) do begin
            if (C = 37) and (MText.CharAt(Src, P + 1) = 37) then
                exit(P);
            P += 1;
            C := MText.CharAt(Src, P);
        end;
        exit(P);
    end;

    local procedure MatchGitGraph(P: Integer): Integer
    var
        E: Integer;
        C: Integer;
    begin
        E := Lit('gitGraph', P);
        if E < 0 then
            exit(-1);
        C := MText.CharAt(Src, E);
        if (C = 37) and (MText.CharAt(Src, E + 1) = 37) then
            exit(E);
        if (C = -1) or MText.IsSpace(C) then
            exit(E);
        exit(-1);
    end;

    local procedure MatchAccDescr(P: Integer): Integer
    var
        Q: Integer;
        R: Integer;
        Close: Integer;
    begin
        if AccDescrDead then
            exit(-1);
        Q := SkipBlanks(P);
        if not MText.StartsWithAt(Src, 'accDescr', Q) then
            exit(-1);
        Q += 8;
        R := SkipBlanks(Q);
        if MText.CharAt(Src, R) = 58 then
            exit(LazyToComment(R + 1));
        R := Q;
        while MText.IsSpace(MText.CharAt(Src, R)) do
            R += 1;
        if MText.CharAt(Src, R) <> 123 then
            exit(-1);
        Close := MText.IndexOfFrom(Src, '}', R + 1);
        if Close = 0 then begin
            AccDescrDead := true;
            exit(-1);
        end;
        exit(Close + 1);
    end;

    local procedure MatchAccTitle(P: Integer): Integer
    var
        Q: Integer;
    begin
        Q := SkipBlanks(P);
        if not MText.StartsWithAt(Src, 'accTitle', Q) then
            exit(-1);
        Q := SkipBlanks(Q + 8);
        if MText.CharAt(Src, Q) <> 58 then
            exit(-1);
        exit(LazyToComment(Q + 1));
    end;

    local procedure MatchTitle(P: Integer): Integer
    var
        Q: Integer;
    begin
        Q := SkipBlanks(P);
        if not MText.StartsWithAt(Src, 'title', Q) then
            exit(-1);
        Q += 5;
        if MText.IsBlank(MText.CharAt(Src, Q)) then
            exit(LazyToComment(Q + 1));
        exit(Q);
    end;

    local procedure MatchInt(P: Integer): Integer
    var
        C: Integer;
        E: Integer;
    begin
        C := MText.CharAt(Src, P);
        if C = 48 then
            exit(P + 1);
        if (C < 49) or (C > 57) then
            exit(-1);
        E := P + 1;
        while MText.IsDigit(MText.CharAt(Src, E)) do
            E += 1;
        if MText.CharAt(Src, E) = 46 then begin
            if E - 1 > P then
                exit(E - 1);
            exit(-1);
        end;
        exit(E);
    end;

    local procedure MatchString(P: Integer): Integer
    var
        Quote: Integer;
        C: Integer;
        Q: Integer;
    begin
        Quote := MText.CharAt(Src, P);
        if (Quote <> 34) and (Quote <> 39) then
            exit(-1);
        Q := P + 1;
        repeat
            C := MText.CharAt(Src, Q);
            if C = -1 then
                exit(-1);
            if C = Quote then
                exit(Q + 1);
            if C = 92 then begin
                C := MText.CharAt(Src, Q + 1);
                if (C = -1) or MText.IsLineEnd(C) then
                    exit(-1);
                Q += 2;
            end else
                Q += 1;
        until false;
    end;

    local procedure MatchNewline(P: Integer): Integer
    begin
        if MText.CharAt(Src, P) = 10 then
            exit(P + 1);
        if (MText.CharAt(Src, P) = 13) and (MText.CharAt(Src, P + 1) = 10) then
            exit(P + 2);
        exit(-1);
    end;

    local procedure MatchWhitespace(P: Integer): Integer
    var
        E: Integer;
    begin
        E := SkipBlanks(P);
        if E = P then
            exit(-1);
        exit(E);
    end;

    /// <summary>Where `(?:\r?\n|(?!\S))` ends at P, or -1.</summary>
    local procedure LineTail(P: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, P);
        if C = 10 then
            exit(P + 1);
        if (C = 13) and (MText.CharAt(Src, P + 1) = 10) then
            exit(P + 2);
        if (C = -1) or MText.IsSpace(C) then
            exit(P);
        exit(-1);
    end;

    local procedure MatchYaml(P: Integer): Integer
    var
        Q: Integer;
        Body: Integer;
        E: Integer;
        L: Integer;
    begin
        if YamlDead then
            exit(-1);
        if not MText.StartsWithAt(Src, '---', P) then
            exit(-1);
        Q := SkipBlanks(P + 3);
        if MText.CharAt(Src, Q) = 13 then
            Q += 1;
        if MText.CharAt(Src, Q) <> 10 then
            exit(-1);
        Body := Q + 1;
        if MText.StartsWithAt(Src, '---', Body) then begin
            E := LineTail(Body + 3);
            if E >= 0 then
                exit(E);
        end;
        L := MText.IndexOfFrom(Src, MText.LF(), Body);
        while L > 0 do begin
            if MText.StartsWithAt(Src, '---', L + 1) then begin
                E := LineTail(L + 4);
                if E >= 0 then
                    exit(E);
            end;
            L := MText.IndexOfFrom(Src, MText.LF(), L + 1);
        end;
        YamlDead := true;
        exit(-1);
    end;

    local procedure MatchDirective(P: Integer): Integer
    var
        Q: Integer;
        Close: Integer;
        E: Integer;
    begin
        if DirectiveDead then
            exit(-1);
        Q := SkipBlanks(P);
        if not MText.StartsWithAt(Src, '%%{', Q) then
            exit(-1);
        Close := MText.IndexOfFrom(Src, '}%%', Q + 3);
        while Close > 0 do begin
            E := LineTail(Close + 3);
            if E >= 0 then
                exit(E);
            Close := MText.IndexOfFrom(Src, '}%%', Close + 1);
        end;
        DirectiveDead := true;
        exit(-1);
    end;

    local procedure MatchComment(P: Integer): Integer
    var
        Q: Integer;
        C: Integer;
    begin
        Q := SkipBlanks(P);
        if not MText.StartsWithAt(Src, '%%', Q) then
            exit(-1);
        Q += 2;
        C := MText.CharAt(Src, Q);
        while (C <> -1) and not IsCrLf(C) do begin
            Q += 1;
            C := MText.CharAt(Src, Q);
        end;
        exit(Q);
    end;

    local procedure MatchReference(P: Integer): Integer
    var
        C: Integer;
        Q: Integer;
        Last: Integer;
    begin
        if not MText.IsWord(MText.CharAt(Src, P)) then
            exit(-1);
        Q := P + 1;
        Last := Q;
        C := MText.CharAt(Src, Q);
        while MText.IsWord(C) or (C = 45) or (C = 46) or (C = 47) do begin
            if MText.IsWord(C) or (C = 45) then
                Last := Q + 1;
            Q += 1;
            C := MText.CharAt(Src, Q);
        end;
        exit(Last);
    end;

    // ---------------------------------------------------------------- token reader

    local procedure Kind(): Integer
    begin
        exit(TokKinds.Get(TokI));
    end;

    local procedure KindAt(J: Integer): Integer
    begin
        if (J < 1) or (J > TokKinds.Count()) then
            exit(-1);
        exit(TokKinds.Get(J));
    end;

    local procedure TokText(J: Integer): Text
    begin
        exit(MText.Substr(Src, TokStarts.Get(J), TokEnds.Get(J)));
    end;

    local procedure Take(): Text
    begin
        TokI += 1;
        exit(TokText(TokI - 1));
    end;

    local procedure Accept(K: Integer): Boolean
    begin
        if Kind() <> K then
            exit(false);
        TokI += 1;
        exit(true);
    end;

    local procedure Expect(K: Integer): Text
    begin
        if Kind() <> K then
            ReaderFail('token of type ''' + KindName(K) + '''');
        exit(Take());
    end;

    local procedure ReaderFail(Expected: Text)
    var
        Found: Text;
    begin
        if Kind() = -1 then
            Found := 'end of input'
        else
            Found := '`' + TokText(TokI) + '`';
        MText.SyntaxError('gitGraph', Src, TokStarts.Get(TokI), 'Expecting ' + Expected + ' but found ' + Found + '.', false);
    end;

    // ---------------------------------------------------------------- token values (common/tokens.ts)

    local procedure Single(Value: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
        RunStart: Integer;
        C: Integer;
    begin
        Value := MText.TrimWs(Value);
        I := 1;
        while I <= StrLen(Value) do begin
            C := Value[I];
            if MText.IsBlank(C) then begin
                RunStart := I;
                while MText.IsBlank(MText.CharAt(Value, I)) do
                    I += 1;
                if I - RunStart >= 2 then
                    Result.Append(' ')
                else
                    Result.Append(CopyStr(Value, RunStart, 1));
            end else begin
                Result.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        end;
        exit(Result.ToText());
    end;

    local procedure TitleValue(Value: Text): Text
    var
        At: Integer;
    begin
        At := StrPos(Value, 'title');
        exit(Single(CopyStr(Value, At + 5)));
    end;

    local procedure AccTitleValue(Value: Text): Text
    var
        At: Integer;
    begin
        At := StrPos(Value, ':');
        exit(Single(CopyStr(Value, At + 1)));
    end;

    local procedure AccDescrValue(Value: Text): Text
    var
        At: Integer;
        Q: Integer;
        Close: Integer;
        Lines: List of [Text];
        Line: Text;
        Result: Text;
    begin
        At := StrPos(Value, 'accDescr');
        Q := SkipBlanksIn(Value, At + 8);
        if MText.CharAt(Value, Q) = 58 then
            exit(Single(CopyStr(Value, Q + 1)));
        Q := StrPos(Value, '{');
        Close := MText.IndexOfFrom(Value, '}', Q + 1);
        if Close = 0 then
            Close := StrLen(Value) + 1;
        Lines := MText.Substr(Value, Q + 1, Close).Replace(MText.CR(), MText.LF()).Split(MText.LF());
        foreach Line in Lines do begin
            Line := Single(Line);
            if Line <> '' then begin
                if Result <> '' then
                    Result += MText.LF();
                Result += Line;
            end;
        end;
        exit(Result);
    end;

    local procedure SkipBlanksIn(Value: Text; P: Integer): Integer
    begin
        while MText.IsBlank(MText.CharAt(Value, P)) do
            P += 1;
        exit(P);
    end;

    local procedure StringValue(Value: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
        C: Text;
    begin
        if StrPos(Value, '\') = 0 then
            exit(MText.Substr(Value, 2, StrLen(Value)));
        I := 2;
        while I < StrLen(Value) do begin
            C := CopyStr(Value, I, 1);
            if C = '\' then begin
                I += 1;
                C := CopyStr(Value, I, 1);
                case C of
                    'b':
                        Result.Append(MText.FromCode(8));
                    'f':
                        Result.Append(MText.FromCode(12));
                    'n':
                        Result.Append(MText.LF());
                    'r':
                        Result.Append(MText.CR());
                    't':
                        Result.Append(MText.FromCode(9));
                    'v':
                        Result.Append(MText.FromCode(11));
                    '0':
                        Result.Append(MText.FromCode(0));
                    else
                        Result.Append(C);
                end;
            end else
                Result.Append(C);
            I += 1;
        end;
        exit(Result.ToText());
    end;

    // ---------------------------------------------------------------- parsing

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    var
        Next: Integer;
    begin
        Src := Source;
        ClearAst();
        Tokenize();
        TokI := 1;

        while Kind() = 26 do
            TokI += 1;
        if not Accept(1) then begin
            Expect(3);
            Next := KindAt(TokI + 1);
            if (Kind() in [17, 18, 19]) and (Next = 20) then begin
                Direction := Take();
                TokI += 1;
            end else
                Accept(20);
        end;

        while Kind() <> -1 do
            case Kind() of
                26:
                    TokI += 1;
                21:
                    begin
                        AccDescr := AccDescrValue(Take());
                        EndOfLine();
                    end;
                22:
                    begin
                        AccTitle := AccTitleValue(Take());
                        EndOfLine();
                    end;
                23:
                    begin
                        GitTitle := TitleValue(Take());
                        EndOfLine();
                    end;
                7:
                    ParseCommit();
                9:
                    ParseBranch();
                13:
                    ParseMerge();
                4, 11:
                    begin
                        TokI += 1;
                        AddStatement(4, ParseName());
                        EndOfLine();
                    end;
                0:
                    ParseCherryPick();
                else
                    ReaderFail('a statement, a title, or a line break');
            end;

        Build(FrontTitle, Config);
    end;

    local procedure ClearAst()
    begin
        Clear(StKind);
        Clear(StName);
        Clear(StId);
        Clear(StMsg);
        Clear(StType);
        Clear(StOrder);
        Clear(StParent);
        Clear(StTagFrom);
        Clear(StTagCount);
        Clear(StTags);
        GitTitle := '';
        AccTitle := '';
        AccDescr := '';
        Direction := 'LR';
    end;

    local procedure AddStatement(StatementKind: Integer; Name: Text)
    begin
        StKind.Add(StatementKind);
        StName.Add(Name);
        StId.Add('');
        StMsg.Add('');
        StType.Add(-1);
        StOrder.Add(0);
        StParent.Add('');
        StTagFrom.Add(StTags.Count() + 1);
        StTagCount.Add(0);
    end;

    local procedure AddTag(Value: Text)
    var
        Last: Integer;
    begin
        Last := StKind.Count();
        StTags.Add(Value);
        StTagCount.Set(Last, StTagCount.Get(Last) + 1);
    end;

    local procedure EndOfLine()
    begin
        if Kind() = -1 then
            exit;
        if Kind() <> 26 then
            ReaderFail('a line break or the end of input');
        while Kind() = 26 do
            TokI += 1;
    end;

    local procedure ParseName(): Text
    begin
        if Kind() = 31 then
            exit(Take());
        if Kind() = 25 then
            exit(StringValue(Take()));
        ReaderFail('a branch name');
    end;

    local procedure ParseString(): Text
    begin
        exit(StringValue(Expect(25)));
    end;

    local procedure ParseCommitType(): Integer
    var
        Value: Text;
    begin
        if not (Kind() in [8, 5, 2]) then
            ReaderFail('NORMAL, REVERSE, or HIGHLIGHT');
        Value := Take();
        case Value of
            'REVERSE':
                exit(1);
            'HIGHLIGHT':
                exit(2);
        end;
        exit(0);
    end;

    local procedure ParseCommit()
    var
        Last: Integer;
    begin
        TokI += 1;
        AddStatement(1, '');
        Last := StKind.Count();
        repeat
            if Accept(16) then
                StId.Set(Last, ParseString())
            else
                if Accept(15) then
                    AddTag(ParseString())
                else
                    if Accept(12) then
                        StType.Set(Last, ParseCommitType())
                    else
                        if Accept(14) or (Kind() = 25) then
                            StMsg.Set(Last, ParseString())
                        else
                            break;
        until false;
        EndOfLine();
    end;

    local procedure ParseBranch()
    var
        Last: Integer;
        Value: Decimal;
    begin
        TokI += 1;
        AddStatement(2, ParseName());
        Last := StKind.Count();
        if Accept(10) then begin
            if not Evaluate(Value, Expect(24), 9) then
                Value := 1000000000000000000.0;
            StOrder.Set(Last, Value);
        end;
        EndOfLine();
    end;

    local procedure ParseMerge()
    var
        Last: Integer;
    begin
        TokI += 1;
        AddStatement(3, ParseName());
        Last := StKind.Count();
        repeat
            if Accept(16) then
                StId.Set(Last, ParseString())
            else
                if Accept(15) then
                    AddTag(ParseString())
                else
                    if Accept(12) then
                        StType.Set(Last, ParseCommitType())
                    else
                        break;
        until false;
        EndOfLine();
    end;

    local procedure ParseCherryPick()
    var
        Last: Integer;
    begin
        TokI += 1;
        AddStatement(5, '');
        Last := StKind.Count();
        repeat
            if Accept(16) then
                StId.Set(Last, ParseString())
            else
                if Accept(15) then
                    AddTag(ParseString())
                else
                    if Accept(6) then
                        StParent.Set(Last, ParseString())
                    else
                        break;
        until false;
        EndOfLine();
    end;

    // ---------------------------------------------------------------- the model (db.ts)
    // Commit types: 0 NORMAL, 1 REVERSE, 2 HIGHLIGHT, 3 MERGE, 4 CHERRY_PICK.

    local procedure Build(FrontTitle: Text; var Config: Dictionary of [Text, Text])
    var
        MainName: Text;
        MainOrder: Decimal;
        S: Integer;
    begin
        Clear(CId);
        Clear(CMsg);
        Clear(CSeq);
        Clear(CType);
        Clear(CCustomType);
        Clear(CCustomId);
        Clear(CBranch);
        Clear(CParent1);
        Clear(CParent2);
        Clear(CParentCount);
        Clear(CTagFrom);
        Clear(CTagCount);
        Clear(CAlive);
        Clear(CTags);
        Clear(IdIndex);
        Clear(BranchHead);
        Clear(OrderNames);
        Clear(OrderValues);
        Clear(Lanes);
        MainName := MText.ConfigText(Config, 'gitGraph.mainBranchName', 'main');
        if not MText.ConfigNumber(Config, 'gitGraph.mainBranchOrder', MainOrder) then
            MainOrder := 0;
        BranchHead.Add(MainName, '');
        OrderNames.Add(MainName);
        OrderValues.Add(MainOrder);
        HeadIdx := 0;
        CurrentBranch := MainName;
        Seq := 0;

        for S := 1 to StKind.Count() do
            case StKind.Get(S) of
                1:
                    DoCommit(S);
                2:
                    DoBranch(StName.Get(S), StOrder.Get(S));
                3:
                    DoMerge(S);
                4:
                    DoCheckout(StName.Get(S));
                5:
                    DoCherryPick(S);
            end;

        SortLanes();
        if GitTitle = '' then
            GitTitle := FrontTitle;
    end;

    local procedure SortLanes()
    var
        Orders: List of [Decimal];
        I: Integer;
        J: Integer;
        Value: Decimal;
        Name: Text;
    begin
        // A stable insertion sort by order, so branches of equal order keep their creation order.
        for I := 1 to OrderNames.Count() do begin
            Value := OrderValues.Get(I);
            Name := OrderNames.Get(I);
            J := Orders.Count();
            while J >= 1 do begin
                if Orders.Get(J) <= Value then
                    break;
                J -= 1;
            end;
            if J = Orders.Count() then begin
                Orders.Add(Value);
                Lanes.Add(Name);
            end else begin
                Orders.Insert(J + 1, Value);
                Lanes.Insert(J + 1, Name);
            end;
        end;
    end;

    local procedure TwoPow32(): BigInteger
    var
        Value: BigInteger;
    begin
        Value := 65536;
        exit(Value * 65536);
    end;

    /// <summary>(A * 0x9e3779b1) mod 2^32, as Math.imul(A, 0x9e3779b1) >>> 0.</summary>
    local procedure MulGolden(A: BigInteger): BigInteger
    var
        R: BigInteger;
    begin
        // 0x9e3779b1 = 40503 * 65536 + 31153.
        R := ((A * 40503) mod 65536) * 65536 + A * 31153;
        exit(R mod TwoPow32());
    end;

    local procedure Hex8(Value: BigInteger): Text
    var
        Digits: Text;
        Result: Text;
        I: Integer;
        D: Integer;
    begin
        Digits := '0123456789abcdef';
        for I := 1 to 8 do begin
            D := Value mod 16;
            Value := Value div 16;
            Result := CopyStr(Digits, D + 1, 1) + Result;
        end;
        exit(Result);
    end;

    /// <summary>
    /// Mermaid appends seven random hex digits to the sequence number. pele derives them from the
    /// sequence number instead, so the same text always gives the same ids.
    /// </summary>
    local procedure NextId(): Text
    var
        Salt: BigInteger;
        Id: Text;
        Golden: BigInteger;
    begin
        Golden := 40503;
        Golden := Golden * 65536 + 31153;
        Salt := Seq + 1;
        repeat
            Id := MText.IntText(Seq) + '-' + CopyStr(Hex8(MulGolden(Salt mod TwoPow32())), 1, 7);
            if not IdIndex.ContainsKey(Id) then
                exit(Id);
            Salt := (Salt + Golden) mod TwoPow32();
        until false;
    end;

    local procedure AddCommit(Id: Text; Message: Text; CommitType: Integer; CustomType: Integer; CustomId: Boolean; Parent1: Text; Parent2: Text; ParentCount: Integer)
    var
        Idx: Integer;
        Old: Integer;
    begin
        CId.Add(Id);
        CMsg.Add(Message);
        CSeq.Add(Seq);
        Seq += 1;
        CType.Add(CommitType);
        CCustomType.Add(CustomType);
        CCustomId.Add(CustomId);
        CBranch.Add(CurrentBranch);
        CParent1.Add(Parent1);
        CParent2.Add(Parent2);
        CParentCount.Add(ParentCount);
        CTagFrom.Add(CTags.Count() + 1);
        CTagCount.Add(0);
        CAlive.Add(true);
        Idx := CId.Count();
        HeadIdx := Idx;
        // A commit with an id that is taken replaces the earlier one, as Map.set does.
        if IdIndex.Get(Id, Old) then begin
            CAlive.Set(Old, false);
            IdIndex.Set(Id, Idx);
        end else
            IdIndex.Add(Id, Idx);
        BranchHead.Set(CurrentBranch, Id);
    end;

    local procedure AddCommitTag(Value: Text)
    var
        Last: Integer;
    begin
        Last := CId.Count();
        CTags.Add(Value);
        CTagCount.Set(Last, CTagCount.Get(Last) + 1);
    end;

    local procedure HeadId(): Text
    begin
        if HeadIdx = 0 then
            exit('');
        exit(CId.Get(HeadIdx));
    end;

    local procedure DoCommit(S: Integer)
    var
        Id: Text;
        CommitType: Integer;
        I: Integer;
    begin
        Id := StId.Get(S);
        if Id = '' then
            Id := NextId();
        CommitType := StType.Get(S);
        if CommitType < 0 then
            CommitType := 0;
        if HeadIdx = 0 then
            AddCommit(Id, StMsg.Get(S), CommitType, -1, false, '', '', 0)
        else
            AddCommit(Id, StMsg.Get(S), CommitType, -1, false, HeadId(), '', 1);
        for I := StTagFrom.Get(S) to StTagFrom.Get(S) + StTagCount.Get(S) - 1 do
            AddCommitTag(StTags.Get(I));
    end;

    local procedure DoCheckout(Branch: Text)
    var
        Id: Text;
        Idx: Integer;
    begin
        if not BranchHead.ContainsKey(Branch) then
            MText.Fail('Trying to checkout branch which is not yet created. (Help try using "branch ' + Branch + '")');
        CurrentBranch := Branch;
        Id := BranchHead.Get(Branch);
        HeadIdx := 0;
        if Id <> '' then
            if IdIndex.Get(Id, Idx) then
                HeadIdx := Idx;
    end;

    local procedure DoBranch(Name: Text; Order: Decimal)
    begin
        if BranchHead.ContainsKey(Name) then
            MText.Fail('Trying to create an existing branch. (Help: Either use a new name if you want create a new branch or try using "checkout ' + Name + '")');
        BranchHead.Add(Name, HeadId());
        OrderNames.Add(Name);
        OrderValues.Add(Order);
        DoCheckout(Name);
    end;

    local procedure CommitOf(Id: Text): Integer
    var
        Idx: Integer;
    begin
        if Id = '' then
            exit(0);
        if IdIndex.Get(Id, Idx) then
            exit(Idx);
        exit(0);
    end;

    local procedure DoMerge(S: Integer)
    var
        Other: Text;
        CustomId: Text;
        OtherHead: Text;
        CurrentCommit: Integer;
        OtherCommit: Integer;
        I: Integer;
    begin
        Other := StName.Get(S);
        CustomId := StId.Get(S);
        if BranchHead.ContainsKey(Other) then
            OtherHead := BranchHead.Get(Other);
        CurrentCommit := CommitOf(BranchHead.Get(CurrentBranch));
        OtherCommit := CommitOf(OtherHead);
        if (CurrentCommit <> 0) and (OtherCommit <> 0) then
            if CBranch.Get(CurrentCommit) = Other then
                MText.Fail('Cannot merge branch ''' + Other + ''' into itself.');
        if CurrentBranch = Other then
            MText.Fail('Incorrect usage of "merge". Cannot merge a branch to itself');
        if CurrentCommit = 0 then
            MText.Fail('Incorrect usage of "merge". Current branch (' + CurrentBranch + ')has no commits');
        if not BranchHead.ContainsKey(Other) then
            MText.Fail('Incorrect usage of "merge". Branch to be merged (' + Other + ') does not exist');
        if OtherCommit = 0 then
            MText.Fail('Incorrect usage of "merge". Branch to be merged (' + Other + ') has no commits');
        if CurrentCommit = OtherCommit then
            MText.Fail('Incorrect usage of "merge". Both branches have same head');
        if CustomId <> '' then
            if IdIndex.ContainsKey(CustomId) then
                MText.Fail('Incorrect usage of "merge". Commit with id:' + CustomId + ' already exists, use different custom id');
        if CustomId = '' then
            CustomId := NextId();
        if HeadIdx = 0 then
            AddCommit(CustomId, 'merged branch ' + Other + ' into ' + CurrentBranch, 3, StType.Get(S), StId.Get(S) <> '', '', '', 0)
        else
            AddCommit(CustomId, 'merged branch ' + Other + ' into ' + CurrentBranch, 3, StType.Get(S), StId.Get(S) <> '', HeadId(), OtherHead, 2);
        for I := StTagFrom.Get(S) to StTagFrom.Get(S) + StTagCount.Get(S) - 1 do
            AddCommitTag(StTags.Get(I));
    end;

    local procedure DoCherryPick(S: Integer)
    var
        Source: Integer;
        Parent: Text;
        CurrentHead: Text;
        Id: Text;
        SourceId: Text;
        DefaultTag: Text;
        I: Integer;
        IsParent: Boolean;
    begin
        Source := CommitOf(StId.Get(S));
        if Source = 0 then
            MText.Fail('Incorrect usage of "cherryPick". Source commit id should exist and provided');
        Parent := StParent.Get(S);
        if Parent <> '' then begin
            IsParent := false;
            if CParentCount.Get(Source) >= 1 then
                if CParent1.Get(Source) = Parent then
                    IsParent := true;
            if CParentCount.Get(Source) >= 2 then
                if CParent2.Get(Source) = Parent then
                    IsParent := true;
            if not IsParent then
                MText.Fail('Invalid operation: The specified parent commit is not an immediate parent of the cherry-picked commit.');
        end;
        if (CType.Get(Source) = 3) and (Parent = '') then
            MText.Fail('Incorrect usage of cherry-pick: If the source commit is a merge commit, an immediate parent commit must be specified.');
        if CBranch.Get(Source) = CurrentBranch then
            MText.Fail('Incorrect usage of "cherryPick". Source commit is already on current branch');
        CurrentHead := BranchHead.Get(CurrentBranch);
        if CommitOf(CurrentHead) = 0 then
            MText.Fail('Incorrect usage of "cherry-pick". Current branch (' + CurrentBranch + ')has no commits');
        SourceId := CId.Get(Source);
        DefaultTag := 'cherry-pick:' + SourceId;
        if CType.Get(Source) = 3 then
            DefaultTag += '|parent:' + Parent;
        Id := NextId();
        if HeadIdx = 0 then
            AddCommit(Id, 'cherry-picked ' + CMsg.Get(Source) + ' into ' + CurrentBranch, 4, -1, false, '', '', 0)
        else
            AddCommit(Id, 'cherry-picked ' + CMsg.Get(Source) + ' into ' + CurrentBranch, 4, -1, false, HeadId(), SourceId, 2);
        if StTagCount.Get(S) = 0 then
            AddCommitTag(DefaultTag)
        else
            for I := StTagFrom.Get(S) to StTagFrom.Get(S) + StTagCount.Get(S) - 1 do
                if StTags.Get(I) <> '' then
                    AddCommitTag(StTags.Get(I));
    end;

    // ---------------------------------------------------------------- rendering (render.ts)

    local procedure Dot(): Decimal
    begin
        exit(7);
    end;

    local procedure Half(): Decimal
    begin
        // Math.SQRT1_2
        exit(0.7071067811865476);
    end;

    local procedure TagWidth(LabelWidth: Decimal): Decimal
    begin
        // NOTCH + 4 + width + 6
        exit(7 + 4 + LabelWidth + 6);
    end;

    /// <summary>pele's plainLabel: only &lt;br&gt; is markup, other tags and icon names show as written.</summary>
    local procedure PlainSource(Raw: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
        J: Integer;
        IsBreak: Boolean;
    begin
        if StrPos(Raw, '<') = 0 then begin
            if StrPos(Raw, ':fa-') = 0 then
                exit(Raw);
            exit(Raw.Replace(':fa-', '&colon;fa-'));
        end;
        I := 1;
        while I <= StrLen(Raw) do begin
            if Raw[I] = 60 then begin
                IsBreak := false;
                if LowerCase(CopyStr(Raw, I + 1, 2)) = 'br' then begin
                    J := I + 3;
                    while MText.IsSpace(MText.CharAt(Raw, J)) do
                        J += 1;
                    if MText.CharAt(Raw, J) = 47 then
                        J += 1;
                    IsBreak := MText.CharAt(Raw, J) = 62;
                end;
                if IsBreak then
                    Result.Append('<')
                else
                    Result.Append('&lt;');
            end else
                Result.Append(CopyStr(Raw, I, 1));
            I += 1;
        end;
        exit(Result.ToText().Replace(':fa-', '&colon;fa-'));
    end;

    local procedure PlainLabel(var Lbl: Codeunit "Mermaid Label"; Raw: Text; Size: Decimal)
    begin
        Lbl.Layout(PlainSource(Raw), false, Size, 4000, 0);
    end;

    local procedure Symbol(CommitType: Integer; X: Decimal; Y: Decimal; Color: Text): Text
    var
        At: Text;
        DotSvg: Text;
    begin
        At := 'cx="' + MText.Num(X) + '" cy="' + MText.Num(Y) + '"';
        if CommitType = 2 then
            exit('<rect x="' + MText.Num(X - Dot() - 1) + '" y="' + MText.Num(Y - Dot() - 1) + '" width="' + MText.Num(2 * Dot() + 2) + '" height="' + MText.Num(2 * Dot() + 2) + '" rx="2" fill="' + Color + '"/>');
        if CommitType = 3 then
            exit('<circle ' + At + ' r="' + MText.Num(Dot() - 1) + '" fill="var(--_bg)" stroke="' + Color + '" stroke-width="2"/><circle ' + At + ' r="2.5" fill="' + Color + '"/>');
        DotSvg := '<circle ' + At + ' r="' + MText.Num(Dot()) + '" fill="' + Color + '"/>';
        if CommitType = 1 then
            exit(DotSvg +
                 '<path d="M' + MText.Num(X - 3) + ',' + MText.Num(Y - 3) + 'l6,6M' + MText.Num(X - 3) + ',' + MText.Num(Y + 3) + 'l6,-6" fill="none" stroke="var(--_bg)" stroke-width="1.5" stroke-linecap="round"/>');
        if CommitType = 4 then
            exit(DotSvg +
                 '<path d="M' + MText.Num(X - 2.6) + ',' + MText.Num(Y + 1) + 'L' + MText.Num(X + 0.8) + ',' + MText.Num(Y - 4.2) + 'L' + MText.Num(X + 2.6) + ',' + MText.Num(Y + 1) + '" fill="none" stroke="var(--_bg)" stroke-linejoin="round"/>' +
                 '<circle cx="' + MText.Num(X - 2.6) + '" cy="' + MText.Num(Y + 2.2) + '" r="1.8" fill="var(--_bg)"/>' +
                 '<circle cx="' + MText.Num(X + 2.6) + '" cy="' + MText.Num(Y + 2.2) + '" r="1.8" fill="var(--_bg)"/>');
        exit(DotSvg);
    end;

    local procedure ClassOf(CommitType: Integer): Text
    begin
        case CommitType of
            1:
                exit('reverse');
            2:
                exit('highlight');
            3:
                exit('merge');
            4:
                exit('cherry-pick');
        end;
        exit('normal');
    end;

    local procedure PX(M: Decimal; C: Decimal; Vertical: Boolean): Decimal
    begin
        if Vertical then
            exit(C);
        exit(M);
    end;

    local procedure PY(M: Decimal; C: Decimal; Vertical: Boolean; Flip: Boolean): Decimal
    begin
        if not Vertical then
            exit(C);
        if Flip then
            exit(-M);
        exit(M);
    end;

    local procedure Point(M: Decimal; C: Decimal; Vertical: Boolean; Flip: Boolean): Text
    begin
        exit(MText.Num(PX(M, C, Vertical)) + ',' + MText.Num(PY(M, C, Vertical, Flip)));
    end;

    local procedure Grow(X0: Decimal; Y0: Decimal; X1: Decimal; Y1: Decimal; var Bounded: Boolean; var MinX: Decimal; var MinY: Decimal; var MaxX: Decimal; var MaxY: Decimal)
    begin
        if not Bounded then begin
            MinX := X0;
            MinY := Y0;
            MaxX := X1;
            MaxY := Y1;
            Bounded := true;
            exit;
        end;
        if X0 < MinX then
            MinX := X0;
        if Y0 < MinY then
            MinY := Y0;
        if X1 > MaxX then
            MaxX := X1;
        if Y1 > MaxY then
            MaxY := Y1;
    end;

    /// <summary>Whether a commit on the lane lies strictly between FromM and ToM.</summary>
    local procedure Busy(var VLane: List of [Integer]; var VM: List of [Decimal]; Lane: Integer; FromM: Decimal; ToM: Decimal): Boolean
    var
        I: Integer;
        M: Decimal;
    begin
        for I := 1 to VLane.Count() do
            if VLane.Get(I) = Lane then begin
                M := VM.Get(I);
                if (M > FromM) and (M < ToM) then
                    exit(true);
            end;
        exit(false);
    end;

    local procedure Space(var VHalf: List of [Decimal]; var VLead: List of [Decimal]; P: Integer; K: Integer): Decimal
    var
        Result: Decimal;
    begin
        // STEP, GAP and CURVE are 44, 8 and 36.
        Result := MText.MaxDec(44, VHalf.Get(P) + VHalf.Get(K) + 8);
        if VLead.Get(K) > 0 then
            Result := MText.MaxDec(Result, VHalf.Get(P) + 36 + VLead.Get(K));
        exit(Result);
    end;

    local procedure ViewOf(var ById: Dictionary of [Text, Integer]; Id: Text): Integer
    var
        V: Integer;
    begin
        if ById.Get(Id, V) then
            exit(V);
        exit(0);
    end;

    local procedure ParentAt(C: Integer; J: Integer): Text
    begin
        if J = 1 then
            exit(CParent1.Get(C));
        exit(CParent2.Get(C));
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        Lbl: Codeunit "Mermaid Label";
        TitleLbl: Codeunit "Mermaid Label";
        LaneOf: Dictionary of [Text, Integer];
        ById: Dictionary of [Text, Integer];
        NameW: List of [Decimal];
        NameH: List of [Decimal];
        NameEmpty: List of [Boolean];
        VCommit: List of [Integer];
        VLane: List of [Integer];
        VM: List of [Decimal];
        VHasLabel: List of [Boolean];
        VLabelW: List of [Decimal];
        VLabelH: List of [Decimal];
        VHalf: List of [Decimal];
        VTagHalf: List of [Decimal];
        VLead: List of [Decimal];
        VTagFrom: List of [Integer];
        VTagCount: List of [Integer];
        TagTxt: List of [Text];
        TagW: List of [Decimal];
        TagH: List of [Decimal];
        Lo: List of [Decimal];
        Hi: List of [Decimal];
        Cross: List of [Decimal];
        BranchesOut: TextBuilder;
        CurvesOut: TextBuilder;
        LinesOut: TextBuilder;
        CommitsOut: TextBuilder;
        Body: TextBuilder;
        Size: Decimal;
        Small: Integer;
        Medium: Integer;
        Pad: Decimal;
        ShowBranches: Boolean;
        ShowCommitLabel: Boolean;
        Rotate: Boolean;
        Parallel: Boolean;
        Vertical: Boolean;
        Flip: Boolean;
        Labelled: Boolean;
        Bounded: Boolean;
        Merged: Boolean;
        Picked: Boolean;
        LaneCount: Integer;
        N: Integer;
        I: Integer;
        J: Integer;
        K: Integer;
        T: Integer;
        C: Integer;
        V: Integer;
        PV: Integer;
        Lane: Integer;
        CommitType: Integer;
        TagsMain: Decimal;
        TagsCross: Decimal;
        LabelMain: Decimal;
        LabelCross: Decimal;
        TagSide: Decimal;
        LabelSide: Decimal;
        W: Decimal;
        H: Decimal;
        M: Decimal;
        EndM: Decimal;
        Reach: Decimal;
        CrossC: Decimal;
        FromM: Decimal;
        Cx: Decimal;
        Cy: Decimal;
        X: Decimal;
        Y: Decimal;
        C1: Decimal;
        C2: Decimal;
        M1: Decimal;
        M2: Decimal;
        Mid: Decimal;
        S: Decimal;
        ToM: Decimal;
        Along: Decimal;
        Ka: Decimal;
        Ax: Decimal;
        Ay: Decimal;
        Offset: Decimal;
        Left: Decimal;
        MinX: Decimal;
        MinY: Decimal;
        MaxX: Decimal;
        MaxY: Decimal;
        TitleHeight: Decimal;
        Inner: Decimal;
        Width: Integer;
        Height: Integer;
        Dx: Decimal;
        Dy: Decimal;
        Color: Text;
        D: Text;
        EdgeClass: Text;
        MergeClass: Text;
        Content: Text;
        Rotation: Text;
    begin
        Size := MText.FontSize();
        Small := Round(Size * 0.75, 1);
        Medium := Round(Size * 0.875, 1);
        Pad := 8;
        ShowBranches := MText.ConfigBool(Config, 'gitGraph.showBranches', true);
        ShowCommitLabel := MText.ConfigBool(Config, 'gitGraph.showCommitLabel', true);
        Rotate := MText.ConfigBool(Config, 'gitGraph.rotateCommitLabel', true);
        Parallel := MText.ConfigBool(Config, 'gitGraph.parallelCommits', false);
        Vertical := Direction <> 'LR';
        Flip := Direction = 'BT';

        LaneCount := Lanes.Count();
        for I := 1 to LaneCount do begin
            LaneOf.Add(Lanes.Get(I), I);
            if ShowBranches then
                PlainLabel(Lbl, Lanes.Get(I), Medium)
            else
                PlainLabel(Lbl, '', Medium);
            NameW.Add(Lbl.GetWidth());
            NameH.Add(Lbl.GetHeight());
            NameEmpty.Add(Lbl.IsEmpty());
            Lo.Add(Dot());
            Hi.Add(Dot());
            Cross.Add(0);
        end;

        // The commits in sequence order, which is the order they were added in.
        for C := 1 to CId.Count() do
            if CAlive.Get(C) then begin
                Labelled := ShowCommitLabel and (CType.Get(C) <> 4);
                if CType.Get(C) = 3 then
                    if not CCustomId.Get(C) then
                        Labelled := false;
                VCommit.Add(C);
                if LaneOf.Get(CBranch.Get(C), Lane) then
                    VLane.Add(Lane)
                else
                    VLane.Add(1);
                VM.Add(0);
                VTagFrom.Add(TagTxt.Count() + 1);
                K := 0;
                for T := CTagFrom.Get(C) to CTagFrom.Get(C) + CTagCount.Get(C) - 1 do begin
                    PlainLabel(Lbl, CTags.Get(T), Small);
                    if not Lbl.IsEmpty() then begin
                        TagTxt.Add(CTags.Get(T));
                        TagW.Add(Lbl.GetWidth());
                        TagH.Add(Lbl.GetHeight());
                        K += 1;
                    end;
                end;
                VTagCount.Add(K);
                if Labelled then begin
                    PlainLabel(Lbl, CId.Get(C), Small);
                    VHasLabel.Add(not Lbl.IsEmpty());
                    VLabelW.Add(Lbl.GetWidth());
                    VLabelH.Add(Lbl.GetHeight());
                end else begin
                    VHasLabel.Add(false);
                    VLabelW.Add(0);
                    VLabelH.Add(0);
                end;
                if ById.ContainsKey(CId.Get(C)) then
                    ById.Set(CId.Get(C), VCommit.Count())
                else
                    ById.Add(CId.Get(C), VCommit.Count());
            end;
        N := VCommit.Count();

        // Room each commit needs: along the main axis on either side, and across it towards the
        // previous lane (Lo) and the next one (Hi). Tags sit on one side of a lane and ids on the other.
        for V := 1 to N do begin
            TagsMain := 0;
            TagsCross := 0;
            for T := VTagFrom.Get(V) to VTagFrom.Get(V) + VTagCount.Get(V) - 1 do begin
                W := TagWidth(TagW.Get(T));
                if Vertical then begin
                    TagsMain := MText.MaxDec(TagsMain, TagH.Get(T));
                    TagsCross += W + 4;
                end else begin
                    TagsMain := MText.MaxDec(TagsMain, W);
                    TagsCross += TagH.Get(T) + 3;
                end;
            end;
            LabelMain := 0;
            LabelCross := 0;
            if VHasLabel.Get(V) then
                if Rotate then
                    LabelCross := 3 + Half() * (VLabelW.Get(V) + VLabelH.Get(V))
                else
                    if Vertical then begin
                        LabelMain := VLabelH.Get(V);
                        LabelCross := 6 + VLabelW.Get(V);
                    end else begin
                        LabelMain := VLabelW.Get(V);
                        LabelCross := 6 + VLabelH.Get(V);
                    end;
            VHalf.Add(MText.MaxDec(Dot(), MText.MaxDec(TagsMain / 2, LabelMain / 2)));
            VTagHalf.Add(TagsMain / 2);
            TagSide := Dot();
            if VTagCount.Get(V) > 0 then
                TagSide += 6 + TagsCross;
            LabelSide := Dot() + LabelCross;
            Lane := VLane.Get(V);
            if Vertical then begin
                Lo.Set(Lane, MText.MaxDec(Lo.Get(Lane), LabelSide));
                Hi.Set(Lane, MText.MaxDec(Hi.Get(Lane), TagSide));
            end else begin
                Lo.Set(Lane, MText.MaxDec(Lo.Get(Lane), TagSide));
                Hi.Set(Lane, MText.MaxDec(Hi.Get(Lane), LabelSide));
            end;
        end;

        // In a left-to-right graph the tags stand over their commit. A connector that comes down from
        // a lane above joins the commit's lane this far before the commit, clear of the tags.
        for V := 1 to N do begin
            VLead.Add(0);
            if not Vertical then
                if VTagHalf.Get(V) <> 0 then begin
                    C := VCommit.Get(V);
                    for J := 1 to CParentCount.Get(C) do begin
                        PV := ViewOf(ById, ParentAt(C, J));
                        if PV <> 0 then
                            if VLane.Get(PV) < VLane.Get(V) then
                                VLead.Set(V, VTagHalf.Get(V) + 4);
                    end;
                end;
        end;

        for V := 1 to N do
            if not Parallel then begin
                if V = 1 then
                    VM.Set(V, 0)
                else
                    VM.Set(V, VM.Get(V - 1) + Space(VHalf, VLead, V - 1, V));
            end else begin
                // Mermaid's parallelCommits: a commit sits one step after its furthest parent.
                M := 0;
                C := VCommit.Get(V);
                for J := 1 to CParentCount.Get(C) do begin
                    PV := ViewOf(ById, ParentAt(C, J));
                    if (PV <> 0) and (PV < V) then
                        M := MText.MaxDec(M, VM.Get(PV) + Space(VHalf, VLead, PV, V));
                end;
                VM.Set(V, M);
            end;
        EndM := 0;
        for V := 1 to N do
            EndM := MText.MaxDec(EndM, VM.Get(V));

        for I := 1 to LaneCount do begin
            Reach := 0;
            if not NameEmpty.Get(I) then
                if Vertical then
                    Reach := NameW.Get(I) / 2 + 8
                else
                    Reach := NameH.Get(I) / 2 + 2;
            Lo.Set(I, MText.MaxDec(Lo.Get(I), Reach));
            Hi.Set(I, MText.MaxDec(Hi.Get(I), Reach));
            if I > 1 then
                Cross.Set(I, Cross.Get(I - 1) + MText.MaxDec(44, Hi.Get(I - 1) + Lo.Get(I) + 8));
        end;

        if ShowBranches then
            for I := 1 to LaneCount do begin
                Color := Builder.SeriesColor(I - 1);
                CrossC := Cross.Get(I);
                PlainLabel(Lbl, Lanes.Get(I), Medium);
                W := Lbl.GetWidth() + 16;
                H := Lbl.GetHeight() + 4;
                if Lbl.IsEmpty() then
                    FromM := -20
                else
                    if Vertical then
                        FromM := -20 - H
                    else
                        FromM := -20 - W;
                if Vertical then begin
                    Cx := PX(FromM + H / 2, CrossC, Vertical);
                    Cy := PY(FromM + H / 2, CrossC, Vertical, Flip);
                end else begin
                    Cx := PX(FromM + W / 2, CrossC, Vertical);
                    Cy := PY(FromM + W / 2, CrossC, Vertical, Flip);
                end;
                X := PX(-20, CrossC, Vertical);
                Y := PY(-20, CrossC, Vertical, Flip);
                Grow(X, Y, X, Y, Bounded, MinX, MinY, MaxX, MaxY);
                X := PX(EndM + 20, CrossC, Vertical);
                Y := PY(EndM + 20, CrossC, Vertical, Flip);
                Grow(X, Y, X, Y, Bounded, MinX, MinY, MaxX, MaxY);
                BranchesOut.Append('<g class="pele-branch" data-id="' + MText.EscText(Lanes.Get(I)) + '">' +
                                   '<path class="pele-lane" d="M' + Point(-20, CrossC, Vertical, Flip) + 'L' + Point(EndM + 20, CrossC, Vertical, Flip) + '" stroke="' + Color + '" stroke-dasharray="2 4"/>');
                if not Lbl.IsEmpty() then begin
                    Grow(Cx - W / 2, Cy - H / 2, Cx + W / 2, Cy + H / 2, Bounded, MinX, MinY, MaxX, MaxY);
                    BranchesOut.Append('<rect x="' + MText.Num(Cx - W / 2) + '" y="' + MText.Num(Cy - H / 2) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) + '" rx="' + Builder.Radius() + '" fill="' + Color + '"/>' +
                                       Lbl.ToSvg(Cx, Cy, ' class="pele-label" fill="var(--_bg)"'));
                end;
                BranchesOut.Append('</g>');
            end;

        for V := 1 to N do begin
            C := VCommit.Get(V);
            C2 := Cross.Get(VLane.Get(V));
            M2 := VM.Get(V);
            for J := 1 to CParentCount.Get(C) do begin
                PV := ViewOf(ById, ParentAt(C, J));
                if (PV <> 0) and (PV <> V) then begin
                    C1 := Cross.Get(VLane.Get(PV));
                    M1 := VM.Get(PV);
                    if VLane.Get(PV) = VLane.Get(V) then
                        LinesOut.Append('<path class="pele-edge" d="M' + Point(M1, C1, Vertical, Flip) + 'L' + Point(M2, C2, Vertical, Flip) + '" stroke="' + Builder.SeriesColor(VLane.Get(V) - 1) + '"/>')
                    else begin
                        Merged := (J > 1) and (CType.Get(C) = 3);
                        Picked := (J > 1) and not Merged;
                        D := 'M' + Point(M1, C1, Vertical, Flip);
                        if M2 <= M1 then begin
                            Mid := (M1 + M2) / 2;
                            D += 'C' + Point(Mid, C1, Vertical, Flip) + ' ' + Point(Mid, C2, Vertical, Flip) + ' ' + Point(M2, C2, Vertical, Flip);
                        end else
                            if (not Merged) and (not Busy(VLane, VM, VLane.Get(V), M1, M2)) then begin
                                // Leaves the parent at once and runs along the child's lane.
                                S := MText.MinDec(36, M2 - M1);
                                D += 'C' + Point(M1 + S / 2, C1, Vertical, Flip) + ' ' + Point(M1 + S / 2, C2, Vertical, Flip) + ' ' + Point(M1 + S, C2, Vertical, Flip) +
                                     'L' + Point(M2, C2, Vertical, Flip);
                            end else begin
                                // Turns in just before the child, or before its tags when it comes from their side.
                                ToM := M2;
                                if VLane.Get(PV) < VLane.Get(V) then
                                    if M2 - VLead.Get(V) > M1 then
                                        ToM := M2 - VLead.Get(V);
                                S := MText.MinDec(36, ToM - M1);
                                Along := C1;
                                if (not Merged) or Busy(VLane, VM, VLane.Get(PV), M1, M2) then begin
                                    // Neither lane is free to run along: take the strip between two lanes.
                                    if C1 > C2 then
                                        Along := C2 + Hi.Get(VLane.Get(V)) + 4
                                    else
                                        Along := C2 - Lo.Get(VLane.Get(V)) - 4;
                                    S := MText.MinDec(36, (ToM - M1) / 2);
                                    D += 'C' + Point(M1 + S / 2, C1, Vertical, Flip) + ' ' + Point(M1 + S / 2, Along, Vertical, Flip) + ' ' + Point(M1 + S, Along, Vertical, Flip);
                                end;
                                D += 'L' + Point(ToM - S, Along, Vertical, Flip) + 'C' + Point(ToM - S / 2, Along, Vertical, Flip) + ' ' + Point(ToM - S / 2, C2, Vertical, Flip) + ' ' + Point(ToM, C2, Vertical, Flip);
                                if ToM < M2 then
                                    D += 'L' + Point(M2, C2, Vertical, Flip);
                            end;
                        EdgeClass := '';
                        if Merged then
                            EdgeClass := ' pele-edge-merge'
                        else
                            if Picked then
                                EdgeClass := ' pele-edge-cherry-pick';
                        if Merged then
                            Color := Builder.SeriesColor(VLane.Get(PV) - 1)
                        else
                            Color := Builder.SeriesColor(VLane.Get(V) - 1);
                        CurvesOut.Append('<path class="pele-edge' + EdgeClass + '" d="' + D + '" stroke="' + Color + '"');
                        if Picked then
                            CurvesOut.Append(' stroke-dasharray="4 3"');
                        CurvesOut.Append('/>');
                    end;
                end;
            end;
        end;

        for V := 1 to N do begin
            C := VCommit.Get(V);
            X := PX(VM.Get(V), Cross.Get(VLane.Get(V)), Vertical);
            Y := PY(VM.Get(V), Cross.Get(VLane.Get(V)), Vertical, Flip);
            CommitType := CCustomType.Get(C);
            if CommitType < 0 then
                CommitType := CType.Get(C);
            Grow(X - Dot() - 1, Y - Dot() - 1, X + Dot() + 1, Y + Dot() + 1, Bounded, MinX, MinY, MaxX, MaxY);
            Clear(Body);
            // Merges and cherry-picks carry a message Mermaid makes up; only a written one is worth showing.
            if (CType.Get(C) < 3) and (CMsg.Get(C) <> '') then
                Body.Append('<title>' + MText.EscText(CMsg.Get(C)) + '</title>');
            Body.Append(Symbol(CommitType, X, Y, Builder.SeriesColor(VLane.Get(V) - 1)));

            if VHasLabel.Get(V) then begin
                PlainLabel(Lbl, CId.Get(C), Small);
                W := Lbl.GetWidth();
                H := Lbl.GetHeight();
                if Rotate then begin
                    // The text ends beside the commit and trails back the way the history came.
                    Ka := (Half() * H) / 2;
                    if Vertical then begin
                        Ax := X - Dot() - 3 - Ka;
                        Ay := Y;
                    end else begin
                        Ax := X + 3;
                        Ay := Y + Dot() + 3 + Ka;
                    end;
                    Reach := Half() * W + Ka;
                    if Flip then
                        Grow(Ax - Reach, Ay - Reach, Ax + Ka, Ay + Ka, Bounded, MinX, MinY, MaxX, MaxY)
                    else
                        Grow(Ax - Reach, Ay - Ka, Ax + Ka, Ay + Reach, Bounded, MinX, MinY, MaxX, MaxY);
                    Rotation := '-45';
                    if Flip then
                        Rotation := '45';
                    Body.Append('<g class="pele-commit-label" transform="rotate(' + Rotation + ' ' + MText.Num(Ax) + ' ' + MText.Num(Ay) + ')">' +
                                LabelBack(Ax - W / 2, Ay, W, H) + Lbl.ToSvg(Ax - W / 2, Ay, '') + '</g>');
                end else begin
                    if Vertical then begin
                        Cx := X - Dot() - 6 - W / 2;
                        Cy := Y;
                    end else begin
                        Cx := X;
                        Cy := Y + Dot() + 6 + H / 2;
                    end;
                    Grow(Cx - W / 2, Cy - H / 2, Cx + W / 2, Cy + H / 2, Bounded, MinX, MinY, MaxX, MaxY);
                    Body.Append('<g class="pele-commit-label">' + LabelBack(Cx, Cy, W, H) + Lbl.ToSvg(Cx, Cy, '') + '</g>');
                end;
            end;

            // Beside the lane the tags form a row; above it they stack, the first one furthest out.
            Offset := Dot() + 6;
            for K := 0 to VTagCount.Get(V) - 1 do begin
                if Vertical then
                    T := VTagFrom.Get(V) + K
                else
                    T := VTagFrom.Get(V) + VTagCount.Get(V) - 1 - K;
                PlainLabel(Lbl, TagTxt.Get(T), Small);
                W := TagWidth(Lbl.GetWidth());
                H := Lbl.GetHeight();
                if Vertical then begin
                    Left := X + Offset;
                    Cy := Y;
                    Offset += W + 4;
                end else begin
                    Left := X - W / 2;
                    Cy := Y - Offset - H / 2;
                    Offset += H + 3;
                end;
                Grow(Left, Cy - H / 2, Left + W, Cy + H / 2, Bounded, MinX, MinY, MaxX, MaxY);
                Body.Append('<g class="pele-tag">' +
                            '<path d="M' + MText.Num(Left) + ',' + MText.Num(Cy) + 'L' + MText.Num(Left + 7) + ',' + MText.Num(Cy - H / 2) + 'H' + MText.Num(Left + W) + 'V' + MText.Num(Cy + H / 2) + 'H' + MText.Num(Left + 7) + 'Z" fill="var(--_s)" stroke="var(--_b)" stroke-linejoin="round"/>' +
                            '<circle cx="' + MText.Num(Left + 7) + '" cy="' + MText.Num(Cy) + '" r="1.5" fill="var(--_b)"/>' +
                            Lbl.ToSvg(Left + 7 + 4 + Lbl.GetWidth() / 2, Cy, ' fill="var(--_fg)"') +
                            '</g>');
            end;

            MergeClass := '';
            if (CType.Get(C) = 3) and (CommitType <> 3) then
                MergeClass := ' pele-commit-merge';
            CommitsOut.Append('<g class="pele-commit pele-commit-' + ClassOf(CommitType) + MergeClass + '" data-id="' + MText.EscText(CId.Get(C)) + '">' + Body.ToText() + '</g>');
        end;

        if not Bounded then
            Grow(0, 0, 0, 0, Bounded, MinX, MinY, MaxX, MaxY);
        TitleLbl.Layout(GitTitle, false, Size, 4000, MText.StyleBold());
        TitleHeight := 0;
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 16;
        Inner := MText.MaxDec(MaxX - MinX, TitleLbl.GetWidth());
        Width := MText.Ceil(Inner + 2 * Pad);
        Height := MText.Ceil(MaxY - MinY + TitleHeight + 2 * Pad);
        Dx := Pad - MinX + (Inner - (MaxX - MinX)) / 2;
        Dy := Pad + TitleHeight - MinY;

        Content := Builder.TitleSvg(TitleLbl, Width / 2, Pad + TitleLbl.GetHeight() / 2) +
                   '<g transform="translate(' + MText.Num(Dx) + ',' + MText.Num(Dy) + ')">';
        if BranchesOut.Length() > 0 then
            Content += '<g class="pele-branches" fill="none" font-size="' + MText.IntText(Medium) + '">' + BranchesOut.ToText() + '</g>';
        if (CurvesOut.Length() > 0) or (LinesOut.Length() > 0) then
            Content += '<g class="pele-edges" fill="none" stroke-width="2" stroke-linecap="round">' + CurvesOut.ToText() + LinesOut.ToText() + '</g>';
        if CommitsOut.Length() > 0 then
            Content += '<g class="pele-commits" font-size="' + MText.IntText(Small) + '" fill="var(--_m)">' + CommitsOut.ToText() + '</g>';
        Content += '</g>';
        exit(Builder.Document('gitGraph', Width, Height, Size, AccTitle, AccDescr, Content));
    end;

    local procedure LabelBack(Cx: Decimal; Cy: Decimal; W: Decimal; H: Decimal): Text
    begin
        exit('<rect x="' + MText.Num(Cx - W / 2 - 2) + '" y="' + MText.Num(Cy - H / 2 + 2) + '" width="' + MText.Num(W + 4) + '" height="' + MText.Num(H - 4) + '" rx="3" fill="var(--_bg)"/>');
    end;
}
