/// <summary>
/// Port of pele's diagrams/class: lexer.ts, parser.ts, db.ts, members.ts, graph.ts, markers.ts and render.ts,
/// with common/generics.ts as local helpers. Parse fills the model; Render resolves it into a graph of
/// namespaces, classes, notes and lollipop interfaces, lays it out with codeunit "Mermaid Compound Layout"
/// and draws it.
/// </summary>
codeunit 68913 "Mermaid Class Diagram"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Layout: Codeunit "Mermaid Compound Layout";
        // ---------------------------------------------------------------- lexer
        Src: Text;
        SrcLen: Integer;
        TokType: List of [Text];
        TokText: List of [Text];
        TokStart: List of [Integer];
        LexState: Integer;
        LexStack: List of [Integer];
        LexPos: Integer;
        DirFailed: Integer;
        DirNext: Integer;
        LineEndPos: Integer;
        // ---------------------------------------------------------------- parser
        TI: Integer;
        // ---------------------------------------------------------------- model
        DiagramDir: Text;
        DiagramTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        ClsId: List of [Text];
        ClsType: List of [Text];
        ClsLabel: List of [Text];
        ClsCss: List of [Text];
        ClsParent: List of [Text];
        ClsLink: List of [Text];
        ClsLinkTarget: List of [Text];
        ClsTooltip: List of [Text];
        ClsCallback: List of [Text];
        ClsCallbackArgs: List of [Text];
        ClsIndex: Dictionary of [Text, Integer];
        MemClass: List of [Integer];
        MemIsMethod: List of [Boolean];
        MemVis: List of [Text];
        MemName: List of [Text];
        MemParams: List of [Text];
        MemReturn: List of [Text];
        MemClassifier: List of [Text];
        AnnClass: List of [Integer];
        AnnText: List of [Text];
        StyClass: List of [Integer];
        StyText: List of [Text];
        TagName: List of [Text];
        TagClass: List of [Integer];
        DefName: List of [Text];
        DefStyle: List of [Text];
        RelId1: List of [Text];
        RelId2: List of [Text];
        RelTitle1: List of [Text];
        RelTitle2: List of [Text];
        RelTitle: List of [Text];
        RelType1: List of [Integer];
        RelType2: List of [Integer];
        RelLine: List of [Integer];
        NoteId: List of [Text];
        NoteClass: List of [Text];
        NoteHasClass: List of [Boolean];
        NoteText: List of [Text];
        NoteParent: List of [Text];
        NoteIndex: Dictionary of [Text, Integer];
        NsId: List of [Text];
        NsLabel: List of [Text];
        NsParent: List of [Text];
        NsExplicit: List of [Boolean];
        NsIndex: Dictionary of [Text, Integer];
        NsStack: List of [Text];
        IfId: List of [Text];
        IfLabel: List of [Text];
        IfClassId: List of [Text];
        // ---------------------------------------------------------------- graph
        GId: List of [Text];
        GLabel: List of [Text];
        GShape: List of [Text];
        GIsGroup: List of [Boolean];
        GParent: List of [Integer];
        GClass: List of [Integer];
        GeId: List of [Text];
        GeSource: List of [Integer];
        GeTarget: List of [Integer];
        GeLabel: List of [Text];
        GeStartMarker: List of [Text];
        GeEndMarker: List of [Text];
        GeStartText: List of [Text];
        GeEndText: List of [Text];
        GePattern: List of [Text];
        // ---------------------------------------------------------------- views
        VW: List of [Decimal];
        VH: List of [Decimal];
        VLoops: List of [Integer];
        VTitleH: List of [Decimal];
        VAttrH: List of [Decimal];
        VFontSize: List of [Decimal];
        VLabelRaw: List of [Text];
        VLabelMd: List of [Boolean];
        VLabelSize: List of [Decimal];
        VLabelMax: List of [Decimal];
        VLabelStyle: List of [Integer];
        VLabelW: List of [Decimal];
        VLabelH: List of [Decimal];
        VShapeAttr: List of [Text];
        VTextAttr: List of [Text];
        VStroke: List of [Text];
        VAnnCount: List of [Integer];
        VAttrCount: List of [Integer];
        VMethCount: List of [Integer];
        LnNode: List of [Integer];
        LnIsMethod: List of [Boolean];
        LnText: List of [Text];
        LnClassifier: List of [Text];
        AnLineNode: List of [Integer];
        AnLineText: List of [Text];
        // layout nodes, before the layout runs
        CNW: List of [Decimal];
        CNH: List of [Decimal];
        CNGroup: List of [Boolean];
        CNPadTop: List of [Decimal];
        CNMinW: List of [Decimal];
        // drawn edges, by index in the layout
        DEdge: List of [Integer];
        DSrc: List of [Integer];
        DDst: List of [Integer];
        DLabelW: List of [Decimal];
        DLayoutW: List of [Decimal];
        DLayoutH: List of [Decimal];
        DStartRoom: List of [Decimal];
        DEndRoom: List of [Decimal];
        DLabX: List of [Decimal];
        DLabY: List of [Decimal];
        DLoopAt: List of [Integer];
        DStartEnd: List of [Integer];
        DEndEnd: List of [Integer];
        Routes: Dictionary of [Integer, List of [Decimal]];
        // the ends of edges on the sides of classes
        EnEdge: List of [Integer];
        EnAt: List of [Integer];
        EnToward: List of [Decimal];
        EnOrder: List of [Integer];
        EnRoom: List of [Decimal];
        EnSide: List of [Integer];
        EnAfter: List of [Boolean];
        EnKey: List of [Integer];
        // cardinalities
        CardText: List of [Text];
        CardX: List of [Decimal];
        CardY: List of [Decimal];
        // route points by rounded y, for cluster titles
        CrossKey: List of [Integer];
        CrossX: List of [Decimal];
        // sizes
        Size: Decimal;
        Small: Decimal;
        Tiny: Decimal;
        TinyHeight: Decimal;
        MinX: Decimal;
        MinY: Decimal;
        MaxX: Decimal;
        MaxY: Decimal;

    // ================================================================ public contract

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    begin
        ClearAll();
        DiagramDir := 'TB';
        DiagramTitle := FrontTitle;
        Src := Source;
        SrcLen := StrLen(Src);
        Tokenize();
        ParseTokens();
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    begin
        exit(Draw(Config));
    end;

    // ================================================================ lexer (lexer.ts)

    local procedure Tokenize()
    var
        C: Integer;
        Q: Integer;
        Ok: Boolean;
    begin
        Clear(TokType);
        Clear(TokText);
        Clear(TokStart);
        Clear(LexStack);
        LexState := 0;
        LexPos := 1;
        DirFailed := 0;
        LineEndPos := 0;
        DirNext := MText.IndexOfFrom(Src, 'direction', 1);
        while true do begin
            if LexPos > SrcLen then begin
                AddToken(AtEnd(LexState), '', SrcLen + 1);
                break;
            end;
            C := MText.CharAt(Src, LexPos);
            Ok := true;
            case LexState of
                0:
                    Ok := LexInitial(C);
                9:
                    // cls
                    if MText.IsSpace(C) then
                        LexSpace(true)
                    else
                        if C = 125 then begin
                            Pop();
                            Pop();
                            Emit('STRUCT_STOP', LexPos, LexPos + 1);
                        end else
                            if C = 123 then begin
                                Push(10);
                                Emit('STRUCT_START', LexPos, LexPos + 1);
                            end else
                                Ok := LexCommon(C);
                10:
                    // classBody
                    if C = 34 then begin
                        Push(1);
                        LexPos += 1;
                    end else
                        if C = 125 then begin
                            Pop();
                            Emit('STRUCT_STOP', LexPos, LexPos + 1);
                        end else
                            if (C = 91) and MText.StartsWithAt(Src, '*]', LexPos + 1) then
                                Emit('EDGE_STATE', LexPos, LexPos + 3)
                            else
                                if C = 123 then
                                    Emit('OPEN_IN_STRUCT', LexPos, LexPos + 1)
                                else
                                    if C = 10 then
                                        LexPos += 1
                                    else begin
                                        Q := LexPos + 1;
                                        while (Q <= SrcLen) and not (MText.CharAt(Src, Q) in [123, 125, 10]) do
                                            Q += 1;
                                        Emit('MEMBER', LexPos, Q);
                                    end;
                11:
                    // namespace
                    if MText.IsSpace(C) then
                        LexSpace(true)
                    else
                        if C = 123 then begin
                            Push(12);
                            Emit('STRUCT_START', LexPos, LexPos + 1);
                        end else
                            if C = 125 then
                                // The brace is read again in the state the namespace was opened from.
                                Pop()
                            else
                                if (C = 110) and Kw('namespace') then begin
                                    Push(11);
                                    Emit('NAMESPACE', LexPos, LexPos + 9);
                                end else
                                    Ok := LexCommon(C);
                12:
                    // namespaceBody
                    if MText.IsSpace(C) then
                        LexSpace(false)
                    else
                        if C = 125 then begin
                            Pop();
                            Emit('STRUCT_STOP', LexPos, LexPos + 1);
                        end else
                            if (C = 110) and Kw('namespace') then begin
                                Push(11);
                                Emit('NAMESPACE', LexPos, LexPos + 9);
                            end else
                                if (C = 91) and MText.StartsWithAt(Src, '*]', LexPos + 1) then
                                    Emit('EDGE_STATE', LexPos, LexPos + 3)
                                else
                                    if (C = 99) and Kw('class') then begin
                                        Push(9);
                                        Emit('CLASS', LexPos, LexPos + 5);
                                    end else
                                        Ok := LexCommon(C);
                1:
                    // string
                    if C = 34 then begin
                        Pop();
                        LexPos += 1;
                    end else
                        Emit('STR', LexPos, UntilCh('"'));
                3:
                    // generic
                    if C = 34 then begin
                        Push(1);
                        LexPos += 1;
                    end else
                        if not LexKeyword(C) then
                            if C = 126 then begin
                                Pop();
                                LexPos += 1;
                            end else
                                Emit('GENERICTYPE', LexPos, UntilCh('~'));
                2:
                    // bqstring
                    if C = 34 then begin
                        Push(1);
                        LexPos += 1;
                    end else
                        if not LexKeyword(C) then
                            case C of
                                126:
                                    begin
                                        Push(3);
                                        LexPos += 1;
                                    end;
                                96:
                                    begin
                                        Pop();
                                        LexPos += 1;
                                    end;
                                else
                                    Emit('BQUOTE_STR', LexPos, UntilCh('`'));
                            end;
                4:
                    // callbackName
                    if C = 40 then begin
                        Q := SkipWs(LexPos + 1);
                        Pop();
                        if MText.CharAt(Src, Q) = 41 then
                            LexPos := Q + 1
                        else begin
                            Push(5);
                            LexPos += 1;
                        end;
                    end else
                        Emit('CALLBACK_NAME', LexPos, UntilCh('('));
                5:
                    // callbackArgs
                    if C = 41 then begin
                        Pop();
                        LexPos += 1;
                    end else
                        Emit('CALLBACK_ARGS', LexPos, UntilCh(')'));
                6:
                    begin
                        Emit('acc_title_value', LexPos, UntilCh(MText.LF()));
                        Pop();
                    end;
                7:
                    begin
                        Emit('acc_descr_value', LexPos, UntilCh(MText.LF()));
                        Pop();
                    end;
                8:
                    if C = 125 then begin
                        Pop();
                        LexPos += 1;
                    end else
                        Emit('acc_descr_multiline_value', LexPos, UntilCh('}'));
            end;
            if not Ok then begin
                AddToken('INVALID', '', LexPos);
                exit;
            end;
        end;
        AddToken('$end', '', SrcLen + 1);
    end;

    /// <summary>The token each state gives at the end of input, before the parser sees the end itself.</summary>
    local procedure AtEnd(State: Integer): Text
    begin
        case State of
            1:
                exit('STR');
            3:
                exit('GENERICTYPE');
            4:
                exit('CALLBACK_NAME');
            5:
                exit('CALLBACK_ARGS');
            6:
                exit('acc_title_value');
            7:
                exit('acc_descr_value');
            8:
                exit('acc_descr_multiline_value');
            10, 12:
                exit('EOF_IN_STRUCT');
        end;
        exit('EOF');
    end;

    local procedure AddToken(TokenType: Text; Value: Text; StartPos: Integer)
    begin
        TokType.Add(TokenType);
        TokText.Add(Value);
        TokStart.Add(StartPos);
    end;

    local procedure Emit(TokenType: Text; StartPos: Integer; EndPos: Integer): Boolean
    begin
        AddToken(TokenType, MText.Substr(Src, StartPos, EndPos), StartPos);
        LexPos := EndPos;
        exit(true);
    end;

    local procedure Push(State: Integer)
    begin
        LexStack.Add(LexState);
        LexState := State;
    end;

    local procedure Pop()
    begin
        if LexStack.Count() > 0 then begin
            LexState := LexStack.Get(LexStack.Count());
            LexStack.RemoveAt(LexStack.Count());
        end;
    end;

    local procedure Kw(Word: Text): Boolean
    begin
        if not MText.StartsWithAt(Src, Word, LexPos) then
            exit(false);
        exit(not MText.IsWord(MText.CharAt(Src, LexPos + StrLen(Word))));
    end;

    local procedure SkipWs(Q: Integer): Integer
    begin
        while MText.IsSpace(MText.CharAt(Src, Q)) do
            Q += 1;
        exit(Q);
    end;

    local procedure UntilCh(Ch: Text): Integer
    var
        E: Integer;
    begin
        E := MText.IndexOfFrom(Src, Ch, LexPos);
        if E = 0 then
            exit(SrcLen + 1);
        exit(E);
    end;

    /// <summary>A run of whitespace is a NEWLINE up to its last line feed; the rest is skipped.</summary>
    local procedure LexSpace(Leaves: Boolean)
    var
        Q: Integer;
        K: Integer;
    begin
        Q := LexPos;
        K := -1;
        while MText.IsSpace(MText.CharAt(Src, Q)) do begin
            if MText.CharAt(Src, Q) = 10 then
                K := Q;
            Q += 1;
        end;
        if K < 0 then begin
            LexPos := Q;
            exit;
        end;
        if Leaves then
            Pop();
        Emit('NEWLINE', LexPos, K + 1);
    end;

    /// <summary>The keywords that every state recognizes, even inside generics and backtick names.</summary>
    local procedure LexKeyword(C: Integer): Boolean
    begin
        case C of
            99:
                begin
                    if Kw('cssClass') then
                        exit(Emit('CSSCLASS', LexPos, LexPos + 8));
                    if Kw('callback') then
                        exit(Emit('CALLBACK', LexPos, LexPos + 8));
                    if Kw('click') then
                        exit(Emit('CLICK', LexPos, LexPos + 5));
                end;
            108:
                if Kw('link') then
                    exit(Emit('LINK', LexPos, LexPos + 4));
            110:
                begin
                    if Kw('note for') then
                        exit(Emit('NOTE_FOR', LexPos, LexPos + 8));
                    if Kw('note') then
                        exit(Emit('NOTE', LexPos, LexPos + 4));
                end;
            60:
                if MText.CharAt(Src, LexPos + 1) = 60 then
                    exit(Emit('ANNOTATION_START', LexPos, LexPos + 2));
            62:
                if MText.CharAt(Src, LexPos + 1) = 62 then
                    exit(Emit('ANNOTATION_END', LexPos, LexPos + 2));
            104:
                if Kw('href') then
                    exit(Emit('HREF', LexPos, LexPos + 4));
        end;
        exit(false);
    end;

    local procedure LexCommon(C: Integer): Boolean
    var
        D: Integer;
        Q: Integer;
        Ch: Integer;
    begin
        if LexKeyword(C) then
            exit(true);
        D := MText.CharAt(Src, LexPos + 1);
        case C of
            34:
                begin
                    Push(1);
                    LexPos += 1;
                    exit(true);
                end;
            126:
                begin
                    Push(3);
                    LexPos += 1;
                    exit(true);
                end;
            96:
                begin
                    Push(2);
                    LexPos += 1;
                    exit(true);
                end;
            95:
                begin
                    if Kw('_self') then
                        exit(Emit('LINK_TARGET', LexPos, LexPos + 5));
                    if Kw('_blank') then
                        exit(Emit('LINK_TARGET', LexPos, LexPos + 6));
                    if Kw('_parent') then
                        exit(Emit('LINK_TARGET', LexPos, LexPos + 7));
                    if Kw('_top') then
                        exit(Emit('LINK_TARGET', LexPos, LexPos + 4));
                end;
            60:
                begin
                    if D = 124 then
                        exit(Emit('EXTENSION', LexPos, LexPos + 2));
                    exit(Emit('DEPENDENCY', LexPos, LexPos + 1));
                end;
            124:
                begin
                    if D = 62 then
                        exit(Emit('EXTENSION', LexPos, LexPos + 2));
                    exit(false);
                end;
            62:
                exit(Emit('DEPENDENCY', LexPos, LexPos + 1));
            42:
                exit(Emit('COMPOSITION', LexPos, LexPos + 1));
            111:
                if not MText.IsWord(D) then
                    exit(Emit('AGGREGATION', LexPos, LexPos + 1));
            40:
                begin
                    if D = 41 then
                        exit(Emit('LOLLIPOP', LexPos, LexPos + 2));
                    exit(false);
                end;
            45:
                begin
                    if D = 45 then
                        exit(Emit('LINE', LexPos, LexPos + 2));
                    exit(Emit('MINUS', LexPos, LexPos + 1));
                end;
            46:
                begin
                    if D = 46 then
                        exit(Emit('DOTTED_LINE', LexPos, LexPos + 2));
                    exit(Emit('DOT', LexPos, LexPos + 1));
                end;
            58:
                begin
                    Q := LexPos + 1;
                    while Q <= SrcLen do begin
                        Ch := MText.CharAt(Src, Q);
                        if (Ch = 58) or (Ch = 10) or (Ch = 59) then
                            break;
                        Q += 1;
                    end;
                    if Q > LexPos + 1 then
                        exit(Emit('LABEL', LexPos, Q));
                    if (D = 58) and (MText.CharAt(Src, LexPos + 2) = 58) then
                        exit(Emit('STYLE_SEPARATOR', LexPos, LexPos + 3));
                    exit(false);
                end;
            43:
                exit(Emit('PLUS', LexPos, LexPos + 1));
            37:
                exit(Emit('PCT', LexPos, LexPos + 1));
            61:
                exit(Emit('EQUALS', LexPos, LexPos + 1));
            91:
                exit(Emit('SQS', LexPos, LexPos + 1));
            93:
                exit(Emit('SQE', LexPos, LexPos + 1));
            33, 35, 36, 38, 39, 44, 63, 92, 47:
                exit(Emit('PUNCTUATION', LexPos, LexPos + 1));
        end;
        if MText.IsWord(C) then begin
            Q := LexPos + 1;
            while MText.IsWord(MText.CharAt(Src, Q)) do
                Q += 1;
            exit(Emit('ALPHA', LexPos, Q));
        end;
        if MText.IsUnicodeLetter(C) then
            exit(Emit('UNICODE_TEXT', LexPos, LexPos + 1));
        exit(false);
    end;

    /// <summary>A direction statement: anything on the line up to the last `direction XX` on it, and the rest of the line.</summary>
    local procedure LexDirection(): Boolean
    var
        NextAt: Integer;
        Dirs: List of [Text];
        Dir: Text;
        EndPos: Integer;
    begin
        if (DirNext = 0) or (LexPos < DirFailed) then
            exit(false);
        if DirNext < LexPos then
            DirNext := MText.IndexOfFrom(Src, 'direction', LexPos);
        NextAt := DirNext;
        if NextAt = 0 then
            exit(false);
        if LineEndPos < LexPos then begin
            LineEndPos := LexPos;
            while (LineEndPos <= SrcLen) and not MText.IsLineEnd(MText.CharAt(Src, LineEndPos)) do
                LineEndPos += 1;
        end;
        if NextAt >= LineEndPos then
            exit(false);
        Dirs.Add('TB');
        Dirs.Add('BT');
        Dirs.Add('RL');
        Dirs.Add('LR');
        foreach Dir in Dirs do
            if MatchDirection(Dir, EndPos) then
                exit(Emit('direction_' + LowerCase(Dir), LexPos, EndPos));
        // No direction statement starts anywhere in the rest of this line either.
        DirFailed := LineEndPos;
        exit(false);
    end;

    local procedure MatchDirection(Dir: Text; var EndPos: Integer): Boolean
    var
        Q: Integer;
        R: Integer;
    begin
        for Q := LineEndPos - 1 downto LexPos do
            if MText.StartsWithAt(Src, 'direction', Q) then begin
                R := Q + 9;
                if MText.IsSpace(MText.CharAt(Src, R)) then begin
                    while MText.IsSpace(MText.CharAt(Src, R)) do
                        R += 1;
                    if MText.StartsWithAt(Src, Dir, R) then begin
                        EndPos := R + 2;
                        while (EndPos <= SrcLen) and (MText.CharAt(Src, EndPos) <> 10) do
                            EndPos += 1;
                        exit(true);
                    end;
                end;
            end;
        exit(false);
    end;

    local procedure LexInitial(C: Integer): Boolean
    var
        E: Integer;
        Q: Integer;
        D: Integer;
        IsTitle: Boolean;
    begin
        if LexDirection() then
            exit(true);
        if MText.IsSpace(C) then begin
            LexSpace(false);
            exit(true);
        end;
        case C of
            37:
                if MText.CharAt(Src, LexPos + 1) = 37 then begin
                    E := UntilCh(MText.LF());
                    while (E <= SrcLen) and (MText.CharAt(Src, E) in [10, 13]) do
                        E += 1;
                    LexPos := E;
                    exit(true);
                end;
            97:
                begin
                    IsTitle := MText.StartsWithAt(Src, 'accTitle', LexPos);
                    if IsTitle or MText.StartsWithAt(Src, 'accDescr', LexPos) then begin
                        Q := SkipWs(LexPos + 8);
                        D := MText.CharAt(Src, Q);
                        if D = 58 then begin
                            if IsTitle then begin
                                Emit('acc_title', LexPos, SkipWs(Q + 1));
                                Push(6);
                            end else begin
                                Emit('acc_descr', LexPos, SkipWs(Q + 1));
                                Push(7);
                            end;
                            exit(true);
                        end;
                        if (D = 123) and not IsTitle then begin
                            LexPos := SkipWs(Q + 1);
                            Push(8);
                            exit(true);
                        end;
                    end;
                end;
            99:
                begin
                    if Kw('classDiagram-v2') then
                        exit(Emit('CLASS_DIAGRAM', LexPos, LexPos + 15));
                    if Kw('classDiagram') then
                        exit(Emit('CLASS_DIAGRAM', LexPos, LexPos + 12));
                    if MText.StartsWithAt(Src, 'call', LexPos) then
                        if MText.IsSpace(MText.CharAt(Src, LexPos + 4)) then begin
                            LexPos := SkipWs(LexPos + 4);
                            Push(4);
                            exit(true);
                        end;
                    if Kw('classDef') then
                        exit(Emit('CLASSDEF', LexPos, LexPos + 8));
                    if Kw('class') then begin
                        Push(9);
                        exit(Emit('CLASS', LexPos, LexPos + 5));
                    end;
                end;
            91:
                if MText.StartsWithAt(Src, '*]', LexPos + 1) then
                    exit(Emit('EDGE_STATE', LexPos, LexPos + 3));
            115:
                if Kw('style') then
                    exit(Emit('STYLE', LexPos, LexPos + 5));
            110:
                if Kw('namespace') then begin
                    Push(11);
                    exit(Emit('NAMESPACE', LexPos, LexPos + 9));
                end;
            44:
                exit(Emit('COMMA', LexPos, LexPos + 1));
            35:
                exit(Emit('BRKT', LexPos, LexPos + 1));
        end;
        if LexCommon(C) then
            exit(true);
        if C = 58 then
            exit(Emit('COLON', LexPos, LexPos + 1));
        exit(false);
    end;

    // ================================================================ parser (parser.ts)

    local procedure TypeAt(I: Integer): Text
    begin
        if (I < 1) or (I > TokType.Count()) then
            exit('');
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
            exit(SrcLen + 1);
        exit(TokStart.Get(I));
    end;

    local procedure Fail(Expected: Text)
    var
        T: Text;
    begin
        T := TypeAt(TI);
        if T = 'INVALID' then
            MText.SyntaxError('class', Src, StartAt(TI), '', true);
        MText.SyntaxError('class', Src, StartAt(TI), 'Expecting ' + Expected + ', got ''' + T + '''', false);
    end;

    local procedure Expect(TokenType: Text): Text
    begin
        if TypeAt(TI) <> TokenType then
            Fail('''' + TokenType + '''');
        TI += 1;
        exit(TextAt(TI - 1));
    end;

    local procedure IsAlphaNum(T: Text): Boolean
    begin
        exit(T in ['UNICODE_TEXT', 'ALPHA', 'MINUS']);
    end;

    local procedure IsStylePart(T: Text): Boolean
    begin
        exit(T in ['ALPHA', 'COLON', 'BRKT', 'STYLE', 'PCT', 'LABEL']);
    end;

    /// <summary>Mermaid's relationType number for an end marker token, or -1.</summary>
    local procedure EndType(T: Text): Integer
    begin
        case T of
            'AGGREGATION':
                exit(0);
            'EXTENSION':
                exit(1);
            'COMPOSITION':
                exit(2);
            'DEPENDENCY':
                exit(3);
            'LOLLIPOP':
                exit(4);
        end;
        exit(-1);
    end;

    local procedure AlphaNum(): Text
    begin
        if not IsAlphaNum(TypeAt(TI)) then
            Fail('''UNICODE_TEXT'', ''NUM'', ''ALPHA'', ''MINUS''');
        TI += 1;
        exit(TextAt(TI - 1));
    end;

    local procedure ReadName(Generic: Boolean): Text
    var
        Result: Text;
        T: Text;
    begin
        while true do begin
            if TypeAt(TI) = 'BQUOTE_STR' then begin
                Result += TextAt(TI);
                TI += 1;
                break;
            end;
            if not IsAlphaNum(TypeAt(TI)) then
                Fail('''UNICODE_TEXT'', ''NUM'', ''ALPHA'', ''MINUS'', ''BQUOTE_STR''');
            Result += TextAt(TI);
            TI += 1;
            T := TypeAt(TI);
            if T = 'DOT' then begin
                Result += '.';
                TI += 1;
            end else
                if (not IsAlphaNum(T)) and (T <> 'BQUOTE_STR') then
                    break;
        end;
        if Generic and (TypeAt(TI) = 'GENERICTYPE') then begin
            Result += '~' + TextAt(TI) + '~';
            TI += 1;
        end;
        exit(Result);
    end;

    local procedure ClassLabelText(): Text
    var
        Result: Text;
    begin
        TI += 1;
        Result := Expect('STR');
        Expect('SQE');
        exit(Result);
    end;

    /// <summary>The members of a class body, in the order they are written, up to its closing brace.</summary>
    local procedure ReadMembers(Id: Text)
    var
        Members: List of [Text];
        Member: Text;
    begin
        if TypeAt(TI) <> 'MEMBER' then
            Fail('''STRUCT_STOP'', ''MEMBER''');
        while TypeAt(TI) = 'MEMBER' do begin
            Members.Add(TextAt(TI));
            TI += 1;
        end;
        Expect('STRUCT_STOP');
        // The grammar collects members last to first, and addMembers turns them back.
        foreach Member in Members do
            AddMember(Id, Member);
    end;

    local procedure ClassStatement(): Text
    var
        Id: Text;
        Css: Text;
        Annotation: Text;
    begin
        TI += 1;
        Id := ReadName(true);
        AddClass(Id);
        if TypeAt(TI) = 'SQS' then
            SetClassLabel(Id, ClassLabelText());
        case TypeAt(TI) of
            'STYLE_SEPARATOR':
                begin
                    TI += 1;
                    Css := AlphaNum();
                    SetCssClass(Id, Css);
                    if TypeAt(TI) = 'STRUCT_START' then begin
                        TI += 1;
                        ReadMembers(Id);
                    end;
                end;
            'STRUCT_START':
                begin
                    TI += 1;
                    if TypeAt(TI) = 'STRUCT_STOP' then
                        TI += 1
                    else
                        ReadMembers(Id);
                end;
            'ANNOTATION_START':
                begin
                    TI += 1;
                    Annotation := AlphaNum();
                    Expect('ANNOTATION_END');
                    AddAnnotation(Id, Annotation);
                    if TypeAt(TI) = 'STRUCT_START' then begin
                        TI += 1;
                        if TypeAt(TI) = 'STRUCT_STOP' then
                            TI += 1
                        else
                            ReadMembers(Id);
                    end;
                end;
        end;
        exit(Id);
    end;

    local procedure NoteStatement(): Text
    var
        Id: Text;
        IsPlain: Boolean;
    begin
        IsPlain := TypeAt(TI) = 'NOTE';
        TI += 1;
        if IsPlain then
            exit(AddNote(Expect('STR'), '', false));
        Id := ReadName(true);
        exit(AddNote(Expect('STR'), Id, true));
    end;

    /// <summary>Namespaces nest, so they are parsed with a stack of open ones.</summary>
    local procedure NamespaceStatement()
    var
        OpenIds: List of [Text];
        ItemLevel: List of [Integer];
        ItemIsNote: List of [Boolean];
        ItemName: List of [Text];
        Classes: List of [Text];
        Notes: List of [Text];
        Ns: Text;
        Id: Text;
        T: Text;
        NextType: Text;
        HasItem: Boolean;
        Depth: Integer;
        K: Integer;
    begin
        while true do begin
            TI += 1;
            Ns := ReadName(false);
            if TypeAt(TI) = 'SQS' then
                Id := AddNamespace(Ns, ClassLabelText())
            else
                Id := AddNamespace(Ns, '');
            Expect('STRUCT_START');
            if TypeAt(TI) = 'NEWLINE' then
                TI += 1;
            OpenIds.Add(Id);
            HasItem := true;
            while HasItem do begin
                T := TypeAt(TI);
                if T = 'NAMESPACE' then
                    break;
                Depth := OpenIds.Count();
                if T = 'CLASS' then begin
                    ItemLevel.Add(Depth);
                    ItemIsNote.Add(false);
                    ItemName.Add(ClassStatement());
                end else
                    if T in ['NOTE', 'NOTE_FOR'] then begin
                        ItemLevel.Add(Depth);
                        ItemIsNote.Add(true);
                        ItemName.Add(NoteStatement());
                    end else
                        Fail('''NAMESPACE'', ''CLASS'', ''NOTE_FOR'', ''NOTE''');
                while true do begin
                    if TypeAt(TI) = 'NEWLINE' then begin
                        NextType := TypeAt(TI + 1);
                        if NextType in ['NAMESPACE', 'CLASS', 'NOTE', 'NOTE_FOR'] then begin
                            TI += 1;
                            break;
                        end;
                        TI += 1;
                    end;
                    Expect('STRUCT_STOP');
                    Depth := OpenIds.Count();
                    Id := OpenIds.Get(Depth);
                    OpenIds.RemoveAt(Depth);
                    Clear(Classes);
                    Clear(Notes);
                    K := 1;
                    while K <= ItemLevel.Count() do
                        if ItemLevel.Get(K) = Depth then begin
                            if ItemIsNote.Get(K) then
                                Notes.Add(ItemName.Get(K))
                            else
                                Classes.Add(ItemName.Get(K));
                            ItemLevel.RemoveAt(K);
                            ItemIsNote.RemoveAt(K);
                            ItemName.RemoveAt(K);
                        end else
                            K += 1;
                    AddClassesToNamespace(Id, Classes, Notes);
                    PopNamespace();
                    if OpenIds.Count() = 0 then begin
                        HasItem := false;
                        break;
                    end;
                end;
            end;
            if OpenIds.Count() = 0 then
                exit;
        end;
    end;

    local procedure RelationEnd(): Integer
    var
        Result: Integer;
    begin
        Result := EndType(TypeAt(TI));
        if Result >= 0 then
            TI += 1;
        exit(Result);
    end;

    local procedure ClassOrRelation()
    var
        Id1: Text;
        Id2: Text;
        T: Text;
        LineToken: Text;
        Title1: Text;
        Title2: Text;
        RelationTitle: Text;
        Type1: Integer;
        Type2: Integer;
        LineType: Integer;
    begin
        Id1 := ReadName(true);
        T := TypeAt(TI);
        if T = 'LABEL' then begin
            AddMember(Id1, CleanupLabel(TextAt(TI)));
            TI += 1;
            exit;
        end;
        Title1 := 'none';
        if T = 'STR' then begin
            Title1 := TextAt(TI);
            TI += 1;
            T := TypeAt(TI);
        end else
            if (EndType(T) < 0) and (T <> 'LINE') and (T <> 'DOTTED_LINE') then
                exit;
        Type1 := RelationEnd();
        LineToken := TypeAt(TI);
        if (LineToken <> 'LINE') and (LineToken <> 'DOTTED_LINE') then
            Fail('''AGGREGATION'', ''EXTENSION'', ''COMPOSITION'', ''DEPENDENCY'', ''LOLLIPOP'', ''LINE'', ''DOTTED_LINE''');
        TI += 1;
        Type2 := RelationEnd();
        Title2 := 'none';
        if TypeAt(TI) = 'STR' then begin
            Title2 := TextAt(TI);
            TI += 1;
        end;
        Id2 := ReadName(true);
        LineType := 1;
        if LineToken = 'LINE' then
            LineType := 0;
        RelationTitle := '';
        if TypeAt(TI) = 'LABEL' then begin
            RelationTitle := CleanupLabel(TextAt(TI));
            TI += 1;
        end;
        AddRelation(Id1, Id2, Type1, Type2, LineType, Title1, Title2, RelationTitle);
    end;

    local procedure ReadStyles(var Result: List of [Text])
    var
        S: Text;
    begin
        Clear(Result);
        while true do begin
            if not IsStylePart(TypeAt(TI)) then
                Fail('''ALPHA'', ''NUM'', ''COLON'', ''UNIT'', ''SPACE'', ''BRKT'', ''STYLE'', ''PCT'', ''LABEL''');
            S := TextAt(TI);
            TI += 1;
            while IsStylePart(TypeAt(TI)) do begin
                S += TextAt(TI);
                TI += 1;
            end;
            Result.Add(S);
            if TypeAt(TI) <> 'COMMA' then
                exit;
            TI += 1;
        end;
    end;

    local procedure TooltipAfter(Id: Text)
    begin
        if TypeAt(TI) = 'STR' then begin
            SetTooltip(Id, TextAt(TI));
            TI += 1;
        end;
    end;

    local procedure LinkStatement(Id: Text)
    var
        Href: Text;
        Tip: Text;
        HasTip: Boolean;
    begin
        Href := Expect('STR');
        if TypeAt(TI) = 'STR' then begin
            Tip := TextAt(TI);
            HasTip := true;
            TI += 1;
        end;
        if TypeAt(TI) = 'LINK_TARGET' then begin
            SetLink(Id, Href, TextAt(TI));
            TI += 1;
        end else
            SetLink(Id, Href, '_blank');
        if HasTip then
            SetTooltip(Id, Tip);
    end;

    local procedure Statement()
    var
        Styles: List of [Text];
        Ids: List of [Text];
        T: Text;
        Id: Text;
        Annotation: Text;
        IdsText: Text;
        CallbackName: Text;
        CallbackArgs: Text;
    begin
        T := TypeAt(TI);
        case T of
            'UNICODE_TEXT', 'ALPHA', 'MINUS', 'BQUOTE_STR':
                begin
                    ClassOrRelation();
                    exit;
                end;
            'NAMESPACE':
                begin
                    NamespaceStatement();
                    exit;
                end;
            'CLASS':
                begin
                    ClassStatement();
                    exit;
                end;
            'MEMBER':
                begin
                    TI += 1;
                    exit;
                end;
            'ANNOTATION_START':
                begin
                    TI += 1;
                    Annotation := AlphaNum();
                    Expect('ANNOTATION_END');
                    AddAnnotation(ReadName(true), Annotation);
                    exit;
                end;
            'CALLBACK':
                begin
                    TI += 1;
                    Id := ReadName(true);
                    CallbackName := Expect('STR');
                    SetClickEvent(Id, CallbackName, '');
                    TooltipAfter(Id);
                    exit;
                end;
            'LINK':
                begin
                    TI += 1;
                    LinkStatement(ReadName(true));
                    exit;
                end;
            'CLICK':
                begin
                    TI += 1;
                    Id := ReadName(true);
                    if TypeAt(TI) = 'HREF' then begin
                        TI += 1;
                        LinkStatement(Id);
                        exit;
                    end;
                    CallbackName := MText.TrimWs(Expect('CALLBACK_NAME'));
                    CallbackArgs := '';
                    if TypeAt(TI) = 'CALLBACK_ARGS' then begin
                        CallbackArgs := MText.TrimWs(TextAt(TI));
                        TI += 1;
                    end;
                    SetClickEvent(Id, CallbackName, CallbackArgs);
                    TooltipAfter(Id);
                    exit;
                end;
            'STYLE':
                begin
                    TI += 1;
                    Id := Expect('ALPHA');
                    ReadStyles(Styles);
                    SetCssStyle(Id, Styles);
                    exit;
                end;
            'CSSCLASS':
                begin
                    TI += 1;
                    IdsText := Expect('STR');
                    SetCssClass(IdsText, Expect('ALPHA'));
                    exit;
                end;
            'NOTE', 'NOTE_FOR':
                begin
                    NoteStatement();
                    exit;
                end;
            'CLASSDEF':
                begin
                    TI += 1;
                    Ids.Add(Expect('ALPHA'));
                    while TypeAt(TI) = 'COMMA' do begin
                        TI += 1;
                        Ids.Add(Expect('ALPHA'));
                    end;
                    ReadStyles(Styles);
                    DefineClass(Ids, Styles);
                    exit;
                end;
            'direction_tb', 'direction_bt', 'direction_rl', 'direction_lr':
                begin
                    TI += 1;
                    DiagramDir := UpperCase(CopyStr(T, 11));
                    exit;
                end;
            'acc_title':
                begin
                    TI += 1;
                    AccTitle := MText.TrimStartWs(MText.TrimWs(Expect('acc_title_value')));
                    exit;
                end;
            'acc_descr':
                begin
                    TI += 1;
                    AccDescr := CollapseIndent(MText.TrimWs(Expect('acc_descr_value')));
                    exit;
                end;
            'acc_descr_multiline_value':
                begin
                    AccDescr := CollapseIndent(MText.TrimWs(TextAt(TI)));
                    TI += 1;
                    exit;
                end;
        end;
        Fail('''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''NAMESPACE'', ''ANNOTATION_START'', ''CLASS'', ''MEMBER'', ''NOTE_FOR'', ''NOTE'', ''CLASSDEF'', ''direction_tb'', ''CALLBACK'', ''LINK'', ''CLICK'', ''STYLE'', ''CSSCLASS'', ''ALPHA'', ''MINUS'', ''BQUOTE_STR''');
    end;

    local procedure ParseTokens()
    var
        Header: Boolean;
    begin
        TI := 1;
        // Mermaid's grammar also accepts statements with no `classDiagram` line before them.
        Header := TypeAt(TI) = 'CLASS_DIAGRAM';
        if Header then begin
            TI += 1;
            Expect('NEWLINE');
        end;
        while true do begin
            Statement();
            if TypeAt(TI) <> 'NEWLINE' then
                break;
            TI += 1;
            if TypeAt(TI) in ['EOF', '$end'] then
                break;
        end;
        if Header then
            Expect('EOF');
        Expect('$end');
    end;

    /// <summary>Mermaid's setAccDescription: whitespace after a line break is dropped.</summary>
    local procedure CollapseIndent(Value: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
        C: Integer;
        J: Integer;
    begin
        I := 1;
        while I <= StrLen(Value) do begin
            C := Value[I];
            if (C = 10) and MText.IsSpace(MText.CharAt(Value, I + 1)) then begin
                J := I + 1;
                while MText.IsSpace(MText.CharAt(Value, J)) do
                    J += 1;
                Result.Append(MText.LF());
                I := J;
            end else begin
                Result.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        end;
        exit(Result.ToText());
    end;

    // ================================================================ model (db.ts)

    local procedure SplitClassName(Id: Text): Text
    var
        At: Integer;
    begin
        At := StrPos(Id, '~');
        if At <= 1 then
            exit(Id);
        exit(CopyStr(Id, 1, At - 1));
    end;

    local procedure SplitTypeName(Id: Text): Text
    var
        At: Integer;
        EndAt: Integer;
    begin
        At := StrPos(Id, '~');
        if At <= 1 then
            exit('');
        EndAt := MText.IndexOfFrom(Id, '~', At + 1);
        if EndAt = 0 then
            EndAt := StrLen(Id) + 1;
        exit(MText.Substr(Id, At + 1, EndAt));
    end;

    /// <summary>Mermaid looks up ids that start with a digit under a prefix, so they never match a class.</summary>
    local procedure LookupId(Id: Text): Text
    begin
        if MText.IsDigit(MText.CharAt(Id, 1)) then
            exit(SplitClassName('classId-' + Id));
        exit(SplitClassName(Id));
    end;

    local procedure AddClass(Id: Text)
    var
        ClassName: Text;
    begin
        ClassName := SplitClassName(Id);
        if ClsIndex.ContainsKey(ClassName) then
            exit;
        ClsId.Add(ClassName);
        ClsType.Add(SplitTypeName(Id));
        ClsLabel.Add(ClassName);
        ClsCss.Add('default');
        ClsParent.Add('');
        ClsLink.Add('');
        ClsLinkTarget.Add('');
        ClsTooltip.Add('');
        ClsCallback.Add('');
        ClsCallbackArgs.Add('');
        ClsIndex.Add(ClassName, ClsId.Count());
        Tag(ClsId.Count(), 'default');
    end;

    local procedure Tag(K: Integer; CssClass: Text)
    var
        I: Integer;
    begin
        for I := 1 to TagName.Count() do
            if TagClass.Get(I) = K then
                if TagName.Get(I) = CssClass then
                    exit;
        TagName.Add(CssClass);
        TagClass.Add(K);
    end;

    /// <summary>The class for a name that may carry a generic type, created if needed.</summary>
    local procedure Ensure(Id: Text): Integer
    begin
        AddClass(Id);
        exit(ClsIndex.Get(SplitClassName(Id)));
    end;

    local procedure SetClassLabel(Id: Text; Value: Text)
    begin
        ClsLabel.Set(Ensure(Id), Value);
    end;

    local procedure AddRelation(Id1: Text; Id2: Text; Type1: Integer; Type2: Integer; LineType: Integer; Title1: Text; Title2: Text; RelationTitle: Text)
    begin
        if (Type1 = 4) and (Type2 < 0) then begin
            AddClass(Id2);
            Id1 := AddInterface(Id1, Id2);
        end else
            if (Type2 = 4) and (Type1 < 0) then begin
                AddClass(Id1);
                Id2 := AddInterface(Id2, Id1);
            end else begin
                AddClass(Id1);
                AddClass(Id2);
            end;
        RelId1.Add(SplitClassName(Id1));
        RelId2.Add(SplitClassName(Id2));
        RelTitle1.Add(MText.TrimWs(Title1));
        RelTitle2.Add(MText.TrimWs(Title2));
        RelTitle.Add(RelationTitle);
        RelType1.Add(Type1);
        RelType2.Add(Type2);
        RelLine.Add(LineType);
    end;

    local procedure AddInterface(InterfaceLabel: Text; ClassId: Text): Text
    var
        Id: Text;
    begin
        Id := 'interface' + MText.IntText(IfId.Count());
        IfId.Add(Id);
        IfLabel.Add(InterfaceLabel);
        IfClassId.Add(ClassId);
        exit(Id);
    end;

    local procedure AddAnnotation(ClassName: Text; Annotation: Text)
    begin
        AnnClass.Add(Ensure(ClassName));
        AnnText.Add(Annotation);
    end;

    local procedure AddMember(ClassName: Text; Member: Text)
    var
        K: Integer;
        Txt: Text;
    begin
        K := Ensure(ClassName);
        Txt := MText.TrimWs(Member);
        if Txt.StartsWith('<<') and Txt.EndsWith('>>') then begin
            AnnClass.Add(K);
            AnnText.Add(CopyStr(Txt, 3, StrLen(Txt) - 4));
        end else
            if StrPos(Txt, ')') > 1 then
                AddClassMember(K, Txt, true)
            else
                if Txt <> '' then
                    AddClassMember(K, Txt, false);
    end;

    local procedure AddNote(NoteTxt: Text; ClassName: Text; HasClass: Boolean): Text
    var
        Id: Text;
    begin
        Id := 'note' + MText.IntText(NoteId.Count());
        NoteId.Add(Id);
        NoteClass.Add(ClassName);
        NoteHasClass.Add(HasClass);
        NoteText.Add(NoteTxt);
        NoteParent.Add('');
        NoteIndex.Add(Id, NoteId.Count());
        exit(Id);
    end;

    local procedure CleanupLabel(Value: Text): Text
    begin
        if Value.StartsWith(':') then
            Value := CopyStr(Value, 2);
        exit(MText.TrimWs(Value));
    end;

    local procedure SetCssClass(Ids: Text; ClassName: Text)
    var
        Id: Text;
        Word: Text;
        K: Integer;
    begin
        foreach Id in Ids.Split(',') do
            if ClsIndex.Get(LookupId(Id), K) then begin
                ClsCss.Set(K, ClsCss.Get(K) + ' ' + ClassName);
                foreach Word in ClassName.Split(' ') do
                    Tag(K, Word);
            end;
    end;

    local procedure DefineClass(var Ids: List of [Text]; var Styles: List of [Text])
    var
        Id: Text;
        S: Text;
        Part: Text;
        I: Integer;
    begin
        foreach Id in Ids do begin
            foreach S in Styles do begin
                DefName.Add(Id);
                DefStyle.Add(S);
            end;
            // Mermaid tests `cssClasses.includes(id)`, which also matches part of a longer name.
            // Whole names are compared here, as pele does.
            for I := 1 to TagName.Count() do
                if TagName.Get(I) = Id then
                    foreach S in Styles do
                        foreach Part in S.Split(',') do begin
                            StyClass.Add(TagClass.Get(I));
                            StyText.Add(Part);
                        end;
        end;
    end;

    local procedure SetTooltip(Ids: Text; Tip: Text)
    var
        Id: Text;
        K: Integer;
    begin
        foreach Id in Ids.Split(',') do
            if ClsIndex.Get(SplitClassName(Id), K) then
                ClsTooltip.Set(K, Tip);
    end;

    local procedure SetLink(Ids: Text; Link: Text; Target: Text)
    var
        FlowParser: Codeunit "Mermaid Flowchart Parser";
        Id: Text;
        Url: Text;
        K: Integer;
    begin
        // Entity codes are resolved first, so that what is checked is what a browser would follow.
        Url := MText.TrimWs(MText.DecodeEntities(Link));
        foreach Id in Ids.Split(',') do
            if ClsIndex.Get(LookupId(Id), K) then begin
                if Url <> '' then
                    ClsLink.Set(K, FlowParser.SafeUrl(Url))
                else
                    ClsLink.Set(K, '');
                ClsLinkTarget.Set(K, Target);
            end;
        SetCssClass(Ids, 'clickable');
    end;

    /// <summary>
    /// Callbacks are never executed as script. The class is marked clickable, as in Mermaid's strict mode, and the
    /// callback name and arguments are kept for the viewer's click event.
    /// </summary>
    local procedure SetClickEvent(Ids: Text; CallbackName: Text; CallbackArgs: Text)
    var
        Id: Text;
        K: Integer;
    begin
        foreach Id in Ids.Split(',') do
            if ClsIndex.Get(LookupId(Id), K) then begin
                ClsCallback.Set(K, CallbackName);
                ClsCallbackArgs.Set(K, CallbackArgs);
            end;
        SetCssClass(Ids, 'clickable');
    end;

    local procedure AddNamespace(Id: Text; NsLabelText: Text): Text
    var
        Prefix: Text;
        Qualified: Text;
        ParentId: Text;
        Current: Text;
        Part: Text;
        FromPos: Integer;
        Dot: Integer;
        K: Integer;
        IsLeaf: Boolean;
    begin
        if NsStack.Count() > 0 then
            Prefix := NsStack.Get(NsStack.Count());
        if Prefix <> '' then
            Qualified := Prefix + '.' + Id
        else
            Qualified := Id;
        NsStack.Add(Qualified);

        if NsIndex.Get(Qualified, K) then begin
            NsExplicit.Set(K, true);
            if NsLabelText <> '' then
                NsLabel.Set(K, NsLabelText);
            exit(Qualified);
        end;

        // The enclosing namespace and its ancestors exist already, so only the parts of `Id` are walked.
        ParentId := Prefix;
        if Prefix <> '' then
            FromPos := StrLen(Prefix) + 2
        else
            FromPos := 1;
        while true do begin
            Dot := MText.IndexOfFrom(Qualified, '.', FromPos);
            IsLeaf := Dot = 0;
            if IsLeaf then
                Current := Qualified
            else
                Current := CopyStr(Qualified, 1, Dot - 1);
            if not NsIndex.Get(Current, K) then begin
                if IsLeaf then
                    Part := CopyStr(Qualified, FromPos)
                else
                    Part := MText.Substr(Qualified, FromPos, Dot);
                NsId.Add(Current);
                if IsLeaf and (NsLabelText <> '') then
                    NsLabel.Add(NsLabelText)
                else
                    NsLabel.Add(Part);
                NsParent.Add(ParentId);
                NsExplicit.Add(IsLeaf);
                K := NsId.Count();
                NsIndex.Add(Current, K);
            end else
                if IsLeaf then
                    NsExplicit.Set(K, true);
            if ParentId <> '' then
                if NsIndex.ContainsKey(ParentId) then
                    if NsParent.Get(K) = '' then
                        NsParent.Set(K, ParentId);
            if IsLeaf then
                exit(Qualified);
            ParentId := Current;
            FromPos := Dot + 1;
        end;
    end;

    local procedure PopNamespace()
    begin
        if NsStack.Count() > 0 then
            NsStack.RemoveAt(NsStack.Count());
    end;

    local procedure AddClassesToNamespace(Id: Text; var Classes: List of [Text]; var Notes: List of [Text])
    var
        Item: Text;
        K: Integer;
    begin
        if not NsIndex.ContainsKey(Id) then
            exit;
        foreach Item in Classes do
            if ClsIndex.Get(SplitClassName(Item), K) then
                ClsParent.Set(K, Id);
        foreach Item in Notes do
            if NoteIndex.Get(Item, K) then
                NoteParent.Set(K, Id);
    end;

    local procedure SetCssStyle(Id: Text; var Styles: List of [Text])
    var
        S: Text;
        Part: Text;
        K: Integer;
    begin
        if not ClsIndex.Get(Id, K) then
            exit;
        foreach S in Styles do
            foreach Part in S.Split(',') do begin
                StyClass.Add(K);
                StyText.Add(Part);
            end;
    end;

    // ================================================================ members (members.ts)

    local procedure IsVisibility(C: Integer): Boolean
    begin
        exit(C in [35, 43, 126, 45]);
    end;

    local procedure AddClassMember(K: Integer; Input: Text; AsMethod: Boolean)
    var
        Vis: Text;
        Id: Text;
        Params: Text;
        Ret: Text;
        Classifier: Text;
        IsMethod: Boolean;
    begin
        IsMethod := AsMethod;
        // Mermaid throws a TypeError for a method with no opening parenthesis, such as `run)`.
        // It is kept here as an attribute, so it is shown as written.
        if IsMethod then
            IsMethod := ParseMethod(Input, Vis, Id, Params, Ret, Classifier);
        if not IsMethod then
            ParseAttribute(Input, Vis, Id, Classifier);
        if Id.StartsWith(' ') then
            Id := ' ' + MText.TrimWs(Id)
        else
            Id := MText.TrimWs(Id);
        MemClass.Add(K);
        MemIsMethod.Add(IsMethod);
        MemVis.Add(Vis);
        MemName.Add(Id);
        MemParams.Add(Params);
        MemReturn.Add(Ret);
        MemClassifier.Add(Classifier);
    end;

    /// <summary>
    /// The same split as Mermaid's /([#+~-])?(.+)\((.*)\)([\s$*])?(.*)([$*])?/, found in one pass:
    /// the first line with an opening parenthesis after its first character and a closing one later.
    /// </summary>
    local procedure ParseMethod(Input: Text; var Vis: Text; var Id: Text; var Params: Text; var Ret: Text; var Classifier: Text): Boolean
    var
        N: Integer;
        StartPos: Integer;
        EndPos: Integer;
        ClosePos: Integer;
        OpenPos: Integer;
        RestPos: Integer;
        StopPos: Integer;
        FirstC: Integer;
        NextC: Integer;
        LastC: Integer;
        IsVisible: Boolean;
    begin
        N := StrLen(Input);
        StartPos := 1;
        while StartPos <= N do begin
            EndPos := StartPos;
            while (EndPos <= N) and not MText.IsLineEnd(MText.CharAt(Input, EndPos)) do
                EndPos += 1;
            ClosePos := EndPos - 1;
            while (ClosePos > StartPos) and (MText.CharAt(Input, ClosePos) <> 41) do
                ClosePos -= 1;
            OpenPos := ClosePos - 1;
            while (OpenPos > StartPos) and (MText.CharAt(Input, OpenPos) <> 40) do
                OpenPos -= 1;
            if OpenPos > StartPos then begin
                FirstC := MText.CharAt(Input, StartPos);
                IsVisible := IsVisibility(FirstC) and (OpenPos > StartPos + 1);
                if IsVisible then begin
                    Vis := MText.FromCode(FirstC);
                    Id := MText.Substr(Input, StartPos + 1, OpenPos);
                end else
                    Id := MText.Substr(Input, StartPos, OpenPos);
                Params := MText.TrimWs(MText.Substr(Input, OpenPos + 1, ClosePos));
                RestPos := ClosePos + 1;
                Classifier := '';
                if RestPos <= N then begin
                    NextC := MText.CharAt(Input, RestPos);
                    if (NextC = 36) or (NextC = 42) or MText.IsSpace(NextC) then begin
                        if not MText.IsSpace(NextC) then
                            Classifier := MText.FromCode(NextC);
                        RestPos += 1;
                    end;
                end;
                StopPos := RestPos;
                while (StopPos <= N) and not MText.IsLineEnd(MText.CharAt(Input, StopPos)) do
                    StopPos += 1;
                Ret := MText.TrimWs(MText.Substr(Input, RestPos, StopPos));
                if (Classifier = '') and (Ret <> '') then begin
                    LastC := MText.CharAt(Ret, StrLen(Ret));
                    if (LastC = 36) or (LastC = 42) then begin
                        Classifier := MText.FromCode(LastC);
                        Ret := CopyStr(Ret, 1, StrLen(Ret) - 1);
                    end;
                end;
                exit(true);
            end;
            StartPos := EndPos + 1;
        end;
        exit(false);
    end;

    local procedure ParseAttribute(Input: Text; var Vis: Text; var Id: Text; var Classifier: Text)
    var
        FirstC: Integer;
        LastC: Integer;
        A: Integer;
        B: Integer;
        Lo: Integer;
        Hi: Integer;
    begin
        FirstC := MText.CharAt(Input, 1);
        LastC := MText.CharAt(Input, StrLen(Input));
        if IsVisibility(FirstC) then
            Vis := MText.FromCode(FirstC);
        if (LastC = 36) or (LastC = 42) then
            Classifier := MText.FromCode(LastC);
        A := 0;
        if Vis <> '' then
            A := 1;
        B := StrLen(Input);
        if Classifier <> '' then
            B -= 1;
        // String.prototype.substring swaps its arguments when the first is the larger.
        Lo := A;
        Hi := B;
        if A > B then begin
            Lo := B;
            Hi := A;
        end;
        Id := CopyStr(Input, Lo + 1, Hi - Lo);
    end;

    local procedure MemberDisplay(M: Integer): Text
    var
        Display: Text;
    begin
        Display := MemVis.Get(M) + GenericTypes(MemName.Get(M));
        if MemIsMethod.Get(M) then begin
            Display += '(' + GenericTypes(MText.TrimWs(MemParams.Get(M))) + ')';
            if MemReturn.Get(M) <> '' then
                Display += ' : ' + GenericTypes(MemReturn.Get(M));
        end;
        exit(MText.TrimWs(Display));
    end;

    // ================================================================ generics (common/generics.ts)

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

    /// <summary>Pairs tildes from the outside in: the first with the last, the second with the one before it.</summary>
    local procedure PairTildes(Value: Text): Text
    var
        At: List of [Integer];
        Result: Text;
        Total: Integer;
        I: Integer;
        Lo: Integer;
        Hi: Integer;
        FromPos: Integer;
    begin
        Total := Tildes(Value);
        if Total <= 1 then
            exit(Value);
        FromPos := 1;
        if (Total mod 2 <> 0) and Value.StartsWith('~') then
            FromPos := 2;
        for I := FromPos to StrLen(Value) do
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

    /// <summary>Turns `List~int~` into `List&lt;int&gt;`, with the quirks of Mermaid's parseGenericTypes around commas.</summary>
    local procedure GenericTypes(Input: Text): Text
    var
        Sets: List of [Text];
        Output: List of [Text];
        Part: Text;
        S: Text;
        Result: Text;
        I: Integer;
        IsFirst: Boolean;
        Joined: Boolean;
    begin
        if StrPos(Input, '~') = 0 then
            exit(Input);
        IsFirst := true;
        foreach Part in Input.Split(',') do begin
            if not IsFirst then
                Sets.Add(',');
            Sets.Add(Part);
            IsFirst := false;
        end;
        I := 1;
        while I <= Sets.Count() do begin
            S := Sets.Get(I);
            Joined := false;
            if (S = ',') and (I > 1) and (I < Sets.Count()) then
                if Tildes(Sets.Get(I - 1)) = 1 then
                    if Tildes(Sets.Get(I + 1)) = 1 then
                        Joined := true;
            if Joined then begin
                S := Sets.Get(I - 1) + ',' + Sets.Get(I + 1);
                I += 1;
                Output.RemoveAt(Output.Count());
            end;
            Output.Add(PairTildes(S));
            I += 1;
        end;
        foreach S in Output do
            Result += S;
        exit(Result);
    end;

    // ================================================================ graph (graph.ts)

    local procedure MarkerName(RelType: Integer): Text
    begin
        case RelType of
            0:
                exit('aggregation');
            1:
                exit('extension');
            2:
                exit('composition');
            3:
                exit('dependency');
            4:
                exit('lollipop');
        end;
        exit('none');
    end;

    local procedure AddGraphNode(Id: Text; NodeLabel: Text; IsGroup: Boolean; Shape: Text; Parent: Integer; ClassNo: Integer)
    begin
        GId.Add(Id);
        GLabel.Add(NodeLabel);
        GIsGroup.Add(IsGroup);
        GShape.Add(Shape);
        GParent.Add(Parent);
        GClass.Add(ClassNo);
    end;

    local procedure AddGraphEdge(Id: Text; Source: Integer; Target: Integer; EdgeLabel: Text; StartMarker: Text; EndMarker: Text; StartText: Text; EndText: Text; Pattern: Text)
    begin
        GeId.Add(Id);
        GeSource.Add(Source);
        GeTarget.Add(Target);
        GeLabel.Add(EdgeLabel);
        GeStartMarker.Add(StartMarker);
        GeEndMarker.Add(EndMarker);
        GeStartText.Add(StartText);
        GeEndText.Add(EndText);
        GePattern.Add(Pattern);
    end;

    /// <summary>With `Hierarchical` off, only the nearest namespace the source declares counts.</summary>
    local procedure DeclaredAncestor(Hierarchical: Boolean; Id: Text; var Declared: Dictionary of [Text, Text]): Text
    var
        Chain: List of [Text];
        Current: Text;
        Found: Text;
        Visited: Text;
        K: Integer;
        Hops: Integer;
    begin
        Hops := 0;
        if Hierarchical or (Id = '') then
            exit(Id);
        Current := Id;
        while (Current <> '') and (Hops <= 10000) do begin
            if Declared.ContainsKey(Current) then begin
                Found := Declared.Get(Current);
                break;
            end;
            if not NsIndex.Get(Current, K) then
                break;
            if NsExplicit.Get(K) then begin
                Found := Current;
                break;
            end;
            Chain.Add(Current);
            Current := NsParent.Get(K);
            Hops += 1;
        end;
        foreach Visited in Chain do
            if Declared.ContainsKey(Visited) then
                Declared.Set(Visited, Found)
            else
                Declared.Add(Visited, Found);
        exit(Found);
    end;

    local procedure GroupOf(var NamespaceAt: Dictionary of [Text, Integer]; Id: Text): Integer
    var
        G: Integer;
    begin
        if Id = '' then
            exit(0);
        if NamespaceAt.Get(Id, G) then
            exit(G);
        exit(0);
    end;

    /// <summary>Resolves the parsed diagram into the nodes and edges that are drawn.</summary>
    local procedure BuildGraph(Hierarchical: Boolean)
    var
        NamespaceAt: Dictionary of [Text, Integer];
        ClassAt: Dictionary of [Text, Integer];
        InterfaceAt: Dictionary of [Text, Integer];
        Declared: Dictionary of [Text, Text];
        ParentIds: List of [Text];
        ParentId: Text;
        StartText: Text;
        EndText: Text;
        Pattern: Text;
        K: Integer;
        Target: Integer;
        Owner: Integer;
        Source: Integer;
        Dest: Integer;
        Owners: Integer;
        StartFromInterface: Boolean;
        EndAtInterface: Boolean;
    begin
        for K := 1 to NsId.Count() do
            if Hierarchical or NsExplicit.Get(K) then begin
                NamespaceAt.Add(NsId.Get(K), GId.Count() + 1);
                if Hierarchical then begin
                    AddGraphNode(NsId.Get(K), NsLabel.Get(K), true, 'rect', 0, 0);
                    ParentIds.Add(NsParent.Get(K));
                end else begin
                    AddGraphNode(NsId.Get(K), NsId.Get(K), true, 'rect', 0, 0);
                    ParentIds.Add('');
                end;
            end;
        for K := 1 to GId.Count() do
            GParent.Set(K, GroupOf(NamespaceAt, ParentIds.Get(K)));

        for K := 1 to ClsId.Count() do begin
            ParentId := DeclaredAncestor(Hierarchical, ClsParent.Get(K), Declared);
            ClassAt.Add(ClsId.Get(K), GId.Count() + 1);
            AddGraphNode(ClsId.Get(K), ClsLabel.Get(K), false, 'classBox', GroupOf(NamespaceAt, ParentId), K);
        end;

        for K := 1 to NoteId.Count() do begin
            ParentId := DeclaredAncestor(Hierarchical, NoteParent.Get(K), Declared);
            Target := 0;
            if NoteHasClass.Get(K) then
                if not ClassAt.Get(NoteClass.Get(K), Target) then
                    Target := 0;
            if Target > 0 then
                AddGraphEdge('edgeNote' + MText.IntText(K - 1), GId.Count() + 1, Target, '', 'none', 'none', '', '', 'dotted');
            AddGraphNode(NoteId.Get(K), NoteText.Get(K), false, 'note', GroupOf(NamespaceAt, ParentId), 0);
        end;

        // Mermaid leaves every lollipop interface outside the namespaces. Here it stays beside its class.
        for K := 1 to IfId.Count() do begin
            Owners := 0;
            if ClassAt.Get(IfClassId.Get(K), Owner) then
                Owners := GParent.Get(Owner);
            InterfaceAt.Add(IfId.Get(K), GId.Count() + 1);
            AddGraphNode(IfId.Get(K), IfLabel.Get(K), false, 'interface', Owners, 0);
        end;

        for K := 1 to RelId1.Count() do begin
            // addRelation swaps in an interface for the lollipop end of a relation with no other marker.
            StartFromInterface := (RelType1.Get(K) = 4) and (RelType2.Get(K) < 0);
            EndAtInterface := (not StartFromInterface) and (RelType2.Get(K) = 4) and (RelType1.Get(K) < 0);
            Source := 0;
            Dest := 0;
            if StartFromInterface then begin
                if not InterfaceAt.Get(RelId1.Get(K), Source) then
                    Source := 0;
            end else
                if not ClassAt.Get(RelId1.Get(K), Source) then
                    Source := 0;
            if EndAtInterface then begin
                if not InterfaceAt.Get(RelId2.Get(K), Dest) then
                    Dest := 0;
            end else
                if not ClassAt.Get(RelId2.Get(K), Dest) then
                    Dest := 0;
            StartText := RelTitle1.Get(K);
            if StartText = 'none' then
                StartText := '';
            EndText := RelTitle2.Get(K);
            if EndText = 'none' then
                EndText := '';
            Pattern := 'solid';
            if RelLine.Get(K) = 1 then
                Pattern := 'dashed';
            AddGraphEdge('id_' + RelId1.Get(K) + '_' + RelId2.Get(K) + '_' + MText.IntText(K), Source, Dest, RelTitle.Get(K),
                         MarkerName(RelType1.Get(K)), MarkerName(RelType2.Get(K)), StartText, EndText, Pattern);
        end;
    end;

    // ================================================================ markers (markers.ts)

    /// <summary>How far the line stops short of the node so that it meets the back of the marker.</summary>
    local procedure ClassMarkerTrim(MarkerType: Text): Decimal
    begin
        case MarkerType of
            'extension':
                exit(12);
            'composition', 'aggregation':
                exit(16);
            'lollipop':
                exit(10);
            'dependency':
                exit(Builder.MarkerTrim('arrow_point'));
        end;
        exit(0);
    end;

    /// <summary>Draws an end marker whose tip is at (X, Y), pointing along (Dx, Dy).</summary>
    local procedure ClassMarker(MarkerType: Text; X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal; Color: Text): Text
    var
        Nx: Decimal;
        Ny: Decimal;
        Bx: Decimal;
        By: Decimal;
        Mx: Decimal;
        My: Decimal;
        HalfW: Decimal;
        Fill: Text;
    begin
        Nx := -Dy;
        Ny := Dx;
        case MarkerType of
            'extension':
                begin
                    Bx := X - Dx * 12;
                    By := Y - Dy * 12;
                    exit('<path class="pele-marker" d="M' + Builder.P(X, Y) + 'L' + Builder.P(Bx + Nx * 6, By + Ny * 6) + 'L' +
                         Builder.P(Bx - Nx * 6, By - Ny * 6) + 'Z" stroke-linejoin="round"/>');
                end;
            'composition', 'aggregation':
                begin
                    Mx := X - (Dx * 16) / 2;
                    My := Y - (Dy * 16) / 2;
                    HalfW := 5;
                    if MarkerType = 'composition' then
                        Fill := ' fill="' + Color + '"';
                    exit('<path class="pele-marker" d="M' + Builder.P(X, Y) + 'L' + Builder.P(Mx + Nx * HalfW, My + Ny * HalfW) + 'L' +
                         Builder.P(X - Dx * 16, Y - Dy * 16) + 'L' + Builder.P(Mx - Nx * HalfW, My - Ny * HalfW) + 'Z" stroke-linejoin="round"' + Fill + '/>');
                end;
            'lollipop':
                exit('<circle class="pele-marker" cx="' + MText.Num(X - Dx * 5) + '" cy="' + MText.Num(Y - Dy * 5) + '" r="5"/>');
            'dependency':
                exit(Builder.Marker('arrow_point', X, Y, Dx, Dy, Color));
        end;
        exit('');
    end;

    // ================================================================ render (render.ts)

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

    local procedure ViewLabel(I: Integer; var Lbl: Codeunit "Mermaid Label")
    begin
        Lbl.Layout(VLabelRaw.Get(I), VLabelMd.Get(I), VLabelSize.Get(I), VLabelMax.Get(I), VLabelStyle.Get(I));
    end;

    local procedure AddView(Raw: Text; Markdown: Boolean; LabelSize: Decimal; MaxWidth: Decimal; LabelStyle: Integer; FontSize: Decimal)
    var
        Lbl: Codeunit "Mermaid Label";
    begin
        Lbl.Layout(Raw, Markdown, LabelSize, MaxWidth, LabelStyle);
        VLabelRaw.Add(Raw);
        VLabelMd.Add(Markdown);
        VLabelSize.Add(LabelSize);
        VLabelMax.Add(MaxWidth);
        VLabelStyle.Add(LabelStyle);
        VLabelW.Add(Lbl.GetWidth());
        VLabelH.Add(Lbl.GetHeight());
        VW.Add(0);
        VH.Add(0);
        VLoops.Add(0);
        VTitleH.Add(0);
        VAttrH.Add(0);
        VFontSize.Add(FontSize);
        VShapeAttr.Add('');
        VTextAttr.Add('');
        VStroke.Add('');
        VAnnCount.Add(0);
        VAttrCount.Add(0);
        VMethCount.Add(0);
    end;

    local procedure AddCNode(W: Decimal; H: Decimal)
    begin
        CNW.Add(W);
        CNH.Add(H);
        CNGroup.Add(false);
        CNPadTop.Add(0);
        CNMinW.Add(0);
    end;

    /// <summary>
    /// A class may carry the declarations of many classDefs many times over. Only the last value of
    /// each property that has an effect is resolved.
    /// </summary>
    local procedure Keep(Decl: Text; var KeptKeys: List of [Text]; var KeptValues: Dictionary of [Text, Text])
    var
        One: List of [Text];
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleSize: Decimal;
        Prop: Text;
    begin
        One.Add(Decl);
        Builder.ResolveStyle(One, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
        if (ShapeAttr = '') and (TextAttr = '') then
            exit;
        Prop := LowerCase(MText.TrimWs(CopyStr(Decl, 1, StrPos(Decl, ':') - 1)));
        if KeptValues.ContainsKey(Prop) then
            KeptValues.Set(Prop, Decl)
        else begin
            KeptValues.Add(Prop, Decl);
            KeptKeys.Add(Prop);
        end;
    end;

    local procedure ClassStyle(K: Integer; var ShapeAttr: Text; var TextAttr: Text; var Stroke: Text; var IsItalic: Boolean; var StyleSize: Decimal)
    var
        KeptKeys: List of [Text];
        KeptValues: Dictionary of [Text, Text];
        Decls: List of [Text];
        CssName: Text;
        Part: Text;
        PropName: Text;
        LineAttr: Text;
        IsBold: Boolean;
        I: Integer;
    begin
        foreach CssName in ClsCss.Get(K).Split(' ') do
            for I := 1 to DefName.Count() do
                if DefName.Get(I) = CssName then
                    foreach Part in DefStyle.Get(I).Split(',') do
                        Keep(Part, KeptKeys, KeptValues);
        for I := 1 to StyClass.Count() do
            if StyClass.Get(I) = K then
                Keep(StyText.Get(I), KeptKeys, KeptValues);
        foreach PropName in KeptKeys do
            Decls.Add(KeptValues.Get(PropName));
        Builder.ResolveStyle(Decls, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
    end;

    local procedure ClassView(I: Integer; K: Integer; HideEmpty: Boolean)
    var
        ShapeAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsItalic: Boolean;
        StyleSize: Decimal;
        FontSize: Decimal;
        MemberSize: Decimal;
        LineHeight: Decimal;
        Generic: Text;
        LabelStyle: Integer;
        Inner: Decimal;
        Line: Text;
        M: Integer;
        Attrs: Integer;
        Methods: Integer;
        Anns: Integer;
        HasSections: Boolean;
        TitleH: Decimal;
        AttrH: Decimal;
        MethH: Decimal;
    begin
        ClassStyle(K, ShapeAttr, TextAttr, Stroke, IsItalic, StyleSize);
        FontSize := Size;
        if StyleSize > 0 then
            FontSize := StyleSize;
        MemberSize := Round(FontSize * 0.875, 1);
        LineHeight := Round(MemberSize * 1.5, 1);
        // The generic type is escaped so that `<T>` is not read as a tag.
        if ClsType.Get(K) <> '' then
            Generic := '&lt;' + GenericTypes(ClsType.Get(K)).Replace('<', '&lt;').Replace('>', '&gt;') + '&gt;';
        LabelStyle := MText.StyleBold();
        if IsItalic then
            LabelStyle += MText.StyleItalic();
        AddView(ClsLabel.Get(K) + Generic, false, FontSize, 4000, LabelStyle, FontSize);
        VShapeAttr.Set(I, ShapeAttr);
        VTextAttr.Set(I, TextAttr);
        VStroke.Set(I, Stroke);
        Inner := VLabelW.Get(I);
        for M := 1 to AnnClass.Count() do
            if AnnClass.Get(M) = K then begin
                // Guillemets, written by code point so the source stays ASCII.
                Line := MText.FromCode(171) + MText.TrimWs(MText.DecodeEntities(AnnText.Get(M))) + MText.FromCode(187);
                AnLineNode.Add(I);
                AnLineText.Add(Line);
                Inner := MText.MaxDec(Inner, MText.Width(Line, Tiny, 0));
                Anns += 1;
            end;
        // Attributes first, then methods, each in the order they were declared.
        for M := 1 to MemClass.Count() do
            if MemClass.Get(M) = K then
                if not MemIsMethod.Get(M) then begin
                    AddLine(I, M, MemberSize, Inner);
                    Attrs += 1;
                end;
        for M := 1 to MemClass.Count() do
            if MemClass.Get(M) = K then
                if MemIsMethod.Get(M) then begin
                    AddLine(I, M, MemberSize, Inner);
                    Methods += 1;
                end;
        HasSections := not (HideEmpty and (Attrs = 0) and (Methods = 0));
        TitleH := 2 * 8 + Anns * TinyHeight + MText.MaxDec(VLabelH.Get(I), Round(FontSize * 1.5, 1));
        AttrH := Section(HasSections, Attrs, LineHeight);
        MethH := Section(HasSections, Methods, LineHeight);
        VAnnCount.Set(I, Anns);
        VAttrCount.Set(I, Attrs);
        VMethCount.Set(I, Methods);
        VTitleH.Set(I, TitleH);
        VAttrH.Set(I, AttrH);
        VW.Set(I, MText.MaxDec(Inner + 2 * 12, 64));
        VH.Set(I, TitleH + AttrH + MethH);
    end;

    local procedure Section(HasSections: Boolean; Lines: Integer; LineHeight: Decimal): Decimal
    begin
        if not HasSections then
            exit(0);
        if Lines > 0 then
            exit(2 * 6 + Lines * LineHeight);
        exit(10);
    end;

    local procedure AddLine(I: Integer; M: Integer; MemberSize: Decimal; var Inner: Decimal)
    var
        Line: Text;
        LineStyle: Integer;
    begin
        Line := MText.TrimWs(MText.DecodeEntities(MemberDisplay(M)));
        LineStyle := 0;
        if MemClassifier.Get(M) = '*' then
            LineStyle := MText.StyleItalic();
        LnNode.Add(I);
        LnIsMethod.Add(MemIsMethod.Get(M));
        LnText.Add(Line);
        LnClassifier.Add(MemClassifier.Get(M));
        Inner := MText.MaxDec(Inner, MText.Width(Line, MemberSize, LineStyle));
    end;

    local procedure Draw(var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Children: List of [Integer];
        Crossed: List of [Boolean];
        Crowd: List of [Decimal];
        Content: TextBuilder;
        HideEmpty: Boolean;
        RootDir: Text;
        Pad: Decimal;
        I: Integer;
        A: Integer;
        B: Integer;
        Slot: Integer;
        N: Integer;
        Need: Decimal;
        Room: Decimal;
        Lettered: Boolean;
        Ox: Decimal;
        Oy: Decimal;
        Width: Decimal;
        Height: Decimal;
        Shift: Decimal;
        Full: Decimal;
        ClustersOut: Text;
        StruckOut: Text;
        NodesOut: Text;
        EdgesOut: Text;
        LabelsOut: Text;
        CardsOut: Text;
        Inner: Text;
    begin
        ClearRenderState();
        Size := MText.FontSize();
        Small := Round(Size * 0.875, 1);
        Tiny := Round(Size * 0.8, 1);
        TinyHeight := Round(Tiny * 1.4, 1);
        Pad := 8;
        HideEmpty := MText.ConfigBool(Config, 'class.hideEmptyMembersBox', false);
        RootDir := Layout.DirectionOf(DiagramDir);
        BuildGraph(MText.ConfigBool(Config, 'class.hierarchicalNamespaces', true));
        N := GId.Count();

        for I := 1 to N do begin
            Children.Add(0);
            Crossed.Add(false);
        end;
        for I := 1 to N do
            if GParent.Get(I) > 0 then
                Children.Set(GParent.Get(I), Children.Get(GParent.Get(I)) + 1);

        // Namespaces that an edge may cross into are made wide enough for the title to sit beside it.
        for I := 1 to GeId.Count() do
            if (GeSource.Get(I) > 0) and (GeTarget.Get(I) > 0) then begin
                A := GParent.Get(GeSource.Get(I));
                B := GParent.Get(GeTarget.Get(I));
                if A <> B then begin
                    MarkCrossed(Crossed, A);
                    MarkCrossed(Crossed, B);
                end;
            end;

        BuildViews(Children, Crossed, HideEmpty);

        // Edges leave one side of a class and arrive at the other, so a class with many of them
        // is widened until they, and the text at their ends, fit side by side.
        for I := 1 to N * 4 do
            Crowd.Add(0);
        BuildEdges(Crowd);

        if (RootDir = 'TB') or (RootDir = 'BT') then
            for I := 1 to N do
                if GClass.Get(I) > 0 then begin
                    Need := 0;
                    Slot := 0;
                    while Slot < 4 do begin
                        A := Round(Crowd.Get((I - 1) * 4 + Slot + 1), 1);
                        Room := Crowd.Get((I - 1) * 4 + Slot + 2);
                        if A > 1 then
                            if Room > 0 then
                                Need := MText.MaxDec(Need, (A - 1) * (Room + 24) + 24)
                            else
                                Need := MText.MaxDec(Need, (A - 1) * 14 + 24);
                        Slot += 2;
                    end;
                    Need := MText.MinDec(Need, 480);
                    if Need > VW.Get(I) then begin
                        CNW.Set(I, CNW.Get(I) + Need - VW.Get(I));
                        VW.Set(I, Need);
                    end;
                end;

        for I := 1 to DEdge.Count() do
            if (DStartRoom.Get(I) > 0) or (DEndRoom.Get(I) > 0) then
                Lettered := true;
        if Lettered then
            Layout.Init(RootDir, NumberOption(Config, 'class.nodeSpacing', 40), 16, NumberOption(Config, 'class.rankSpacing', 56 + 16), 0)
        else
            Layout.Init(RootDir, NumberOption(Config, 'class.nodeSpacing', 40), 16, NumberOption(Config, 'class.rankSpacing', 56), 0);
        for I := 1 to N do begin
            Layout.AddNode(CNW.Get(I), CNH.Get(I), 0);
            if CNGroup.Get(I) then
                Layout.SetGroup(I, 20, CNPadTop.Get(I), 20, CNMinW.Get(I), '');
        end;
        for I := 1 to N do
            if GParent.Get(I) > 0 then
                Layout.SetParent(I, GParent.Get(I));
        for I := 1 to DEdge.Count() do
            Layout.AddEdge(DSrc.Get(I), DDst.Get(I), 1, DLayoutW.Get(I), DLayoutH.Get(I));
        Layout.Execute();
        for I := 1 to DEdge.Count() do
            StoreRoute(I);

        SpreadEnds();

        MinX := 0;
        MinY := 0;
        MaxX := Layout.GetWidth();
        MaxY := Layout.GetHeight();
        PlaceCards();

        Ox := Pad - MinX;
        Oy := Pad - MinY;
        Width := MText.Ceil(MaxX - MinX + 2 * Pad);
        Height := MText.Ceil(MaxY - MinY + 2 * Pad);

        if N > 0 then
            if GIsGroup.Get(1) then
                for I := 1 to DEdge.Count() do
                    MarkCrossings(I);

        DrawNodes(Ox, Oy, ClustersOut, StruckOut, NodesOut);
        DrawEdges(Ox, Oy, EdgesOut, LabelsOut);
        CardsOut := DrawCards(Ox, Oy);

        if ClustersOut <> '' then
            Content.Append('<g class="pele-clusters">' + ClustersOut + '</g>');
        if EdgesOut <> '' then
            Content.Append('<g class="pele-edges" fill="none" stroke="var(--_l)" stroke-linecap="round">' + EdgesOut + '</g>');
        if StruckOut <> '' then
            Content.Append('<g class="pele-cluster-titles">' + StruckOut + '</g>');
        if LabelsOut <> '' then
            Content.Append('<g class="pele-edge-labels" font-size="' + MText.Num(Small) + '">' + LabelsOut + '</g>');
        if CardsOut <> '' then
            Content.Append('<g class="pele-cardinalities" font-size="' + MText.Num(Tiny) + '" fill="var(--_m)">' + CardsOut + '</g>');
        Content.Append('<g class="pele-nodes">' + NodesOut + '</g>');
        Inner := Content.ToText();

        // Puts the diagram title above content that was laid out without one.
        TitleLbl.Layout(DiagramTitle, false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then begin
            Shift := TitleLbl.GetHeight() + 12;
            Full := MText.MaxDec(Width, MText.Ceil(TitleLbl.GetWidth() + 2 * Pad));
            Inner := Builder.TitleSvg(TitleLbl, Full / 2, Pad + TitleLbl.GetHeight() / 2) +
                     '<g transform="translate(' + Builder.P((Full - Width) / 2, Shift) + ')">' + Inner + '</g>';
            Width := Full;
            Height := MText.Ceil(Height + Shift);
        end;
        exit(Builder.Document('class', Width, Height, Size, AccTitle, AccDescr, Inner));
    end;

    /// <summary>Forgets everything a previous Render built, so the model can be drawn again.</summary>
    local procedure ClearRenderState()
    begin
        Clear(GId);
        Clear(GLabel);
        Clear(GShape);
        Clear(GIsGroup);
        Clear(GParent);
        Clear(GClass);
        Clear(GeId);
        Clear(GeSource);
        Clear(GeTarget);
        Clear(GeLabel);
        Clear(GeStartMarker);
        Clear(GeEndMarker);
        Clear(GeStartText);
        Clear(GeEndText);
        Clear(GePattern);
        Clear(VW);
        Clear(VH);
        Clear(VLoops);
        Clear(VTitleH);
        Clear(VAttrH);
        Clear(VFontSize);
        Clear(VLabelRaw);
        Clear(VLabelMd);
        Clear(VLabelSize);
        Clear(VLabelMax);
        Clear(VLabelStyle);
        Clear(VLabelW);
        Clear(VLabelH);
        Clear(VShapeAttr);
        Clear(VTextAttr);
        Clear(VStroke);
        Clear(VAnnCount);
        Clear(VAttrCount);
        Clear(VMethCount);
        Clear(LnNode);
        Clear(LnIsMethod);
        Clear(LnText);
        Clear(LnClassifier);
        Clear(AnLineNode);
        Clear(AnLineText);
        Clear(CNW);
        Clear(CNH);
        Clear(CNGroup);
        Clear(CNPadTop);
        Clear(CNMinW);
        Clear(DEdge);
        Clear(DSrc);
        Clear(DDst);
        Clear(DLabelW);
        Clear(DLayoutW);
        Clear(DLayoutH);
        Clear(DStartRoom);
        Clear(DEndRoom);
        Clear(DLabX);
        Clear(DLabY);
        Clear(DLoopAt);
        Clear(DStartEnd);
        Clear(DEndEnd);
        Clear(Routes);
        Clear(EnEdge);
        Clear(EnAt);
        Clear(EnToward);
        Clear(EnOrder);
        Clear(EnRoom);
        Clear(EnSide);
        Clear(EnAfter);
        Clear(EnKey);
        Clear(CardText);
        Clear(CardX);
        Clear(CardY);
        Clear(CrossKey);
        Clear(CrossX);
    end;

    local procedure MarkCrossed(var Crossed: List of [Boolean]; G: Integer)
    var
        Hops: Integer;
    begin
        Hops := 0;
        while (G > 0) and (Hops <= GId.Count()) do begin
            if Crossed.Get(G) then
                exit;
            Crossed.Set(G, true);
            G := GParent.Get(G);
            Hops += 1;
        end;
    end;

    local procedure BuildViews(var Children: List of [Integer]; var Crossed: List of [Boolean]; HideEmpty: Boolean)
    var
        I: Integer;
        W: Decimal;
        H: Decimal;
        Extra: Decimal;
    begin
        for I := 1 to GId.Count() do
            if GIsGroup.Get(I) then begin
                AddView(GLabel.Get(I), false, Size, 4000, 0, Size);
                if Children.Get(I) > 0 then begin
                    AddCNode(0, 0);
                    CNGroup.Set(I, true);
                    if VLabelH.Get(I) > 0 then
                        CNPadTop.Set(I, VLabelH.Get(I) + 16)
                    else
                        CNPadTop.Set(I, 20);
                    Extra := 0;
                    if Crossed.Get(I) then
                        Extra := MText.MinDec(VLabelW.Get(I) + 24, 240);
                    CNMinW.Set(I, VLabelW.Get(I) + 2 * 20 - 12 + Extra);
                end else begin
                    W := MText.MaxDec(VLabelW.Get(I) + 2 * 20, 80);
                    H := VLabelH.Get(I) + 2 * 20;
                    VW.Set(I, W);
                    VH.Set(I, H);
                    AddCNode(W, H);
                end;
            end else
                if GClass.Get(I) > 0 then begin
                    ClassView(I, GClass.Get(I), HideEmpty);
                    AddCNode(VW.Get(I), VH.Get(I));
                end else
                    if GShape.Get(I) = 'note' then begin
                        AddView(GLabel.Get(I), true, Small, 260, 0, Small);
                        VW.Set(I, MText.MaxDec(VLabelW.Get(I) + 2 * 12, 40));
                        VH.Set(I, VLabelH.Get(I) + 2 * 8);
                        AddCNode(VW.Get(I), VH.Get(I));
                    end else begin
                        AddView(GLabel.Get(I), false, Small, 200, 0, Small);
                        VW.Set(I, MText.MaxDec(VLabelW.Get(I), 12) + 4);
                        VH.Set(I, MText.MaxDec(VLabelH.Get(I), 12));
                        AddCNode(VW.Get(I), VH.Get(I));
                    end;
    end;

    local procedure Meet(var Crowd: List of [Decimal]; Itm: Integer; Slot: Integer; Room: Decimal)
    var
        At: Integer;
    begin
        At := (Itm - 1) * 4 + Slot + 1;
        Crowd.Set(At, Crowd.Get(At) + 1);
        if Room > Crowd.Get(At + 1) then
            Crowd.Set(At + 1, Room);
    end;

    local procedure BuildEdges(var Crowd: List of [Decimal])
    var
        Lbl: Codeunit "Mermaid Label";
        E: Integer;
        Src0: Integer;
        Dst0: Integer;
        StartW: Decimal;
        EndW: Decimal;
        LabelW: Decimal;
        LabelH: Decimal;
    begin
        for E := 1 to GeId.Count() do begin
            Src0 := GeSource.Get(E);
            Dst0 := GeTarget.Get(E);
            if (Src0 > 0) and (Dst0 > 0) then begin
                Lbl.Layout(GeLabel.Get(E), true, Small, 200, 0);
                StartW := 0;
                EndW := 0;
                if GeStartText.Get(E) <> '' then
                    StartW := MText.Width(MText.DecodeEntities(GeStartText.Get(E)), Tiny, 0);
                if GeEndText.Get(E) <> '' then
                    EndW := MText.Width(MText.DecodeEntities(GeEndText.Get(E)), Tiny, 0);
                if Src0 = Dst0 then begin
                    VLoops.Set(Src0, VLoops.Get(Src0) + 1);
                    if Lbl.GetWidth() > 0 then
                        CNW.Set(Src0, CNW.Get(Src0) + 2 * (26 + Lbl.GetWidth() + 12))
                    else
                        CNW.Set(Src0, CNW.Get(Src0) + 2 * 26);
                end else begin
                    Meet(Crowd, Src0, 0, StartW);
                    Meet(Crowd, Dst0, 2, EndW);
                end;
                LabelW := 0;
                LabelH := 0;
                if Lbl.GetWidth() > 0 then
                    LabelW := Lbl.GetWidth() + 12;
                if Lbl.GetHeight() > 0 then
                    LabelH := Lbl.GetHeight() + 4;
                DEdge.Add(E);
                DSrc.Add(Src0);
                DDst.Add(Dst0);
                DLabelW.Add(Lbl.GetWidth());
                DLayoutW.Add(LabelW);
                DLayoutH.Add(LabelH);
                DStartRoom.Add(StartW);
                DEndRoom.Add(EndW);
                DLabX.Add(0);
                DLabY.Add(0);
                DLoopAt.Add(0);
                DStartEnd.Add(0);
                DEndEnd.Add(0);
            end;
        end;
    end;

    /// <summary>Copies an edge's route out of the layout into a list of its own (a new list on every call).</summary>
    local procedure StoreRoute(D: Integer)
    var
        Route: List of [Decimal];
    begin
        Layout.EdgeRoute(D, Route);
        Routes.Add(D, Route);
        DLabX.Set(D, Layout.EdgeLabelX(D));
        DLabY.Set(D, Layout.EdgeLabelY(D));
    end;

    local procedure RouteCount(D: Integer): Integer
    var
        Route: List of [Decimal];
    begin
        Route := Routes.Get(D);
        exit(Route.Count());
    end;

    local procedure RouteGet(D: Integer; At: Integer): Decimal
    var
        Route: List of [Decimal];
    begin
        Route := Routes.Get(D);
        exit(Route.Get(At));
    end;

    local procedure RouteSet(D: Integer; At: Integer; Value: Decimal)
    var
        Route: List of [Decimal];
    begin
        Route := Routes.Get(D);
        Route.Set(At, Value);
        Routes.Set(D, Route);
    end;

    /// <summary>Records where an edge reaches a side of a class; returns the end's number, or 0 off the box.</summary>
    local procedure Attach(D: Integer; AtEndSide: Boolean; Itm: Integer; Room: Decimal; OrderNo: Integer): Integer
    var
        At: Integer;
        Side: Integer;
        Across: Integer;
        NeighbourAt: Integer;
        Slack: Decimal;
        Toward: Decimal;
        Bend: Decimal;
        After: Boolean;
    begin
        if AtEndSide then
            At := RouteCount(D) - 2
        else
            At := 1;
        Side := Layout.SideOf(Itm, RouteGet(D, At), RouteGet(D, At + 1));
        if Side < 0 then
            exit(0);
        Slack := (Layout.NodeW(Itm) - VW.Get(Itm)) / 2;
        if Side = 1 then
            RouteSet(D, At, RouteGet(D, At) - Slack)
        else
            if Side = 3 then
                RouteSet(D, At, RouteGet(D, At) + Slack);
        Across := Side mod 2;
        if At = 1 then
            NeighbourAt := 4
        else
            NeighbourAt := At - 3;
        Toward := RouteGet(D, NeighbourAt + Across);
        Bend := Toward - RouteGet(D, At + Across);
        if Across = 1 then
            After := Bend > 0
        else
            After := Bend >= 0;
        EnEdge.Add(D);
        EnAt.Add(At);
        EnToward.Add(Toward);
        EnOrder.Add(OrderNo);
        EnRoom.Add(Room);
        EnSide.Add(Side);
        EnAfter.Add(After);
        EnKey.Add(Itm * 4 + Side);
        exit(EnEdge.Count());
    end;

    /// <summary>Whether a point lies on the border of one of the namespaces around a node.</summary>
    local procedure OnBorder(Itm: Integer; X: Decimal; Y: Decimal): Boolean
    var
        G: Integer;
        Hops: Integer;
        Dx: Decimal;
        Dy: Decimal;
    begin
        Hops := 0;
        G := Layout.NodeParent(Itm);
        while (G > 0) and (Hops < 10000) do begin
            Dx := Abs(X - Layout.NodeX(G));
            Dy := Abs(Y - Layout.NodeY(G));
            if (Abs(Dy - Layout.NodeH(G) / 2) < 0.5) and (Dx <= Layout.NodeW(G) / 2 + 0.5) then
                exit(true);
            if (Abs(Dx - Layout.NodeW(G) / 2) < 0.5) and (Dy <= Layout.NodeH(G) / 2 + 0.5) then
                exit(true);
            G := Layout.NodeParent(G);
            Hops += 1;
        end;
        exit(false);
    end;

    /// <summary>
    /// Every edge reaches the middle of a side. Where several share a side they are spread along it,
    /// in the order of where they come from. An end with text runs straight for the length of the text,
    /// which sits beside it on the side the line then bends toward. Neighbours are set apart far enough
    /// for the text between them.
    /// </summary>
    local procedure SpreadEnds()
    var
        SideKeys: List of [Integer];
        Members: List of [Integer];
        Gaps: List of [Decimal];
        KeyNo: Integer;
        I: Integer;
        J: Integer;
        Itm: Integer;
        Across: Integer;
        Moving: Boolean;
        Cur: Integer;
        Prev: Integer;
        E1: Integer;
        E2: Integer;
        Len: Decimal;
        Gap: Decimal;
        Total: Decimal;
        Scale: Decimal;
        At: Decimal;
    begin
        for I := 1 to DEdge.Count() do
            if (DSrc.Get(I) <> DDst.Get(I)) and (RouteCount(I) >= 6) then begin
                DStartEnd.Set(I, Attach(I, false, DSrc.Get(I), DStartRoom.Get(I), I));
                DEndEnd.Set(I, Attach(I, true, DDst.Get(I), DEndRoom.Get(I), I));
            end;
        for I := 1 to EnKey.Count() do
            if not SideKeys.Contains(EnKey.Get(I)) then
                SideKeys.Add(EnKey.Get(I));
        foreach KeyNo in SideKeys do begin
            Clear(Members);
            for I := 1 to EnKey.Count() do
                if EnKey.Get(I) = KeyNo then
                    Members.Add(I);
            if Members.Count() >= 2 then begin
                Itm := KeyNo div 4;
                Across := (KeyNo mod 4) mod 2;
                if Across = 1 then
                    Len := VH.Get(Itm)
                else
                    Len := VW.Get(Itm);
                // Sorted by where they come from, then in the order of the edges.
                for I := 2 to Members.Count() do begin
                    Cur := Members.Get(I);
                    J := I - 1;
                    Moving := true;
                    while Moving do
                        if J < 1 then
                            Moving := false
                        else begin
                            Prev := Members.Get(J);
                            if (EnToward.Get(Prev) > EnToward.Get(Cur)) or ((EnToward.Get(Prev) = EnToward.Get(Cur)) and (EnOrder.Get(Prev) > EnOrder.Get(Cur))) then begin
                                Members.Set(J + 1, Prev);
                                J -= 1;
                            end else
                                Moving := false;
                        end;
                    Members.Set(J + 1, Cur);
                end;
                Clear(Gaps);
                Total := 0;
                for J := 1 to Members.Count() - 1 do begin
                    E1 := Members.Get(J);
                    E2 := Members.Get(J + 1);
                    if Across = 1 then
                        Gap := 20
                    else
                        Gap := 24;
                    if (EnRoom.Get(E1) > 0) and EnAfter.Get(E1) then
                        if Across = 1 then
                            Gap += TinyHeight + 6
                        else
                            Gap += EnRoom.Get(E1);
                    if (EnRoom.Get(E2) > 0) and not EnAfter.Get(E2) then
                        if Across = 1 then
                            Gap += TinyHeight + 6
                        else
                            Gap += EnRoom.Get(E2);
                    Gaps.Add(Gap);
                    Total += Gap;
                end;
                Scale := MText.MinDec(1, (Len - 24) / Total);
                if Scale > 0 then begin
                    if Across = 1 then
                        At := Layout.NodeY(Itm) - (Total * Scale) / 2
                    else
                        At := Layout.NodeX(Itm) - (Total * Scale) / 2;
                    for J := 1 to Members.Count() do begin
                        PlaceEnd(Members.Get(J), Itm, Across, At);
                        if J <= Gaps.Count() then
                            At += Gaps.Get(J) * Scale;
                    end;
                end;
            end;
        end;

        for I := 1 to DEdge.Count() do begin
            Straighten(I, DStartEnd.Get(I), DStartRoom.Get(I), true);
            Straighten(I, DEndEnd.Get(I), DEndRoom.Get(I), false);
        end;
    end;

    local procedure PlaceEnd(En: Integer; Itm: Integer; Across: Integer; At: Decimal)
    var
        D: Integer;
        EndAt: Integer;
        StepK: Integer;
        FirstK: Integer;
        K: Integer;
        BorderK: Integer;
        Searching: Boolean;
        Line: Decimal;
    begin
        D := EnEdge.Get(En);
        EndAt := EnAt.Get(En);
        // An edge that crosses the border of the class's namespace close by runs straight to it:
        // the point where it crosses moves into line with its end.
        if EndAt = 1 then
            StepK := 3
        else
            StepK := -3;
        FirstK := EndAt + StepK;
        BorderK := 0;
        if (FirstK >= 1) and (FirstK <= RouteCount(D)) then begin
            Line := RouteGet(D, FirstK + Across);
            K := FirstK;
            Searching := true;
            while Searching do
                if (K < 1) or (K > RouteCount(D)) then
                    Searching := false
                else
                    if Abs(RouteGet(D, K + Across) - Line) >= 0.5 then
                        Searching := false
                    else
                        if OnBorder(Itm, RouteGet(D, K), RouteGet(D, K + 1)) then begin
                            BorderK := K;
                            Searching := false;
                        end else
                            K += StepK;
            if BorderK > 0 then
                if Abs(Line - At) <= 24 then begin
                    K := FirstK;
                    while K <> BorderK + StepK do begin
                        RouteSet(D, K + Across, At);
                        K += StepK;
                    end;
                end;
        end;
        RouteSet(D, EndAt + Across, At);
    end;

    local procedure Straighten(D: Integer; En: Integer; Room: Decimal; IsFirst: Boolean)
    var
        Route: List of [Decimal];
        Across: Integer;
        At: Integer;
        Along: Integer;
        NeighbourAt: Integer;
        Reach: Decimal;
        Len: Decimal;
        Px: Decimal;
        Py: Decimal;
        Pa: Decimal;
        Dir: Decimal;
    begin
        if (En = 0) or (Room <= 0) then
            exit;
        Route := Routes.Get(D);
        Across := EnSide.Get(En) mod 2;
        if IsFirst then
            At := 1
        else
            At := Route.Count() - 2;
        Along := At + 1 - Across;
        if IsFirst then
            NeighbourAt := 4
        else
            NeighbourAt := At - 3;
        Reach := Abs(Route.Get(NeighbourAt + 1 - Across) - Route.Get(Along));
        if Across = 1 then
            Len := MText.MinDec(Room + 10, Reach * 0.35)
        else
            Len := MText.MinDec(TinyHeight + 6, Reach * 0.35);
        if Len < 4 then
            exit;
        Px := Route.Get(At);
        Py := Route.Get(At + 1);
        Pa := Route.Get(At + 2);
        Dir := 1;
        if EnSide.Get(En) in [0, 3] then
            Dir := -1;
        // A left or right end runs straight across, a top or bottom one straight along.
        if Across = 1 then
            Px += Dir * Len
        else
            Py += Dir * Len;
        if IsFirst then
            At := 4;
        Route.Insert(At, Pa);
        Route.Insert(At, Py);
        Route.Insert(At, Px);
        Routes.Set(D, Route);
    end;

    local procedure Card(Raw: Text; Width: Decimal; X: Decimal; Y: Decimal; Side: Integer; After: Boolean)
    var
        Cx: Decimal;
        Cy: Decimal;
    begin
        if Raw = '' then
            exit;
        Cx := X;
        Cy := Y;
        if Side mod 2 = 1 then begin
            if Side = 3 then
                Cx -= 5 + Width / 2
            else
                Cx += 5 + Width / 2;
            if After then
                Cy += 7 + TinyHeight / 2
            else
                Cy -= 7 + TinyHeight / 2;
        end else begin
            if After then
                Cx += 9 + Width / 2
            else
                Cx -= 9 + Width / 2;
            if Side = 0 then
                Cy -= 3 + TinyHeight / 2
            else
                Cy += 3 + TinyHeight / 2;
        end;
        CardText.Add(MText.DecodeEntities(Raw));
        CardX.Add(Cx);
        CardY.Add(Cy);
        MinX := MText.MinDec(MinX, Cx - Width / 2);
        MaxX := MText.MaxDec(MaxX, Cx + Width / 2);
        MinY := MText.MinDec(MinY, Cy - TinyHeight / 2);
        MaxY := MText.MaxDec(MaxY, Cy + TinyHeight / 2);
    end;

    local procedure PlaceCards()
    var
        LoopSeen: Dictionary of [Integer, Integer];
        I: Integer;
        K: Integer;
        S: Integer;
        E: Integer;
        LastAt: Integer;
        StartEnd: Integer;
        EndEnd: Integer;
        X: Decimal;
        Spread: Decimal;
        StartSide: Integer;
        EndSide: Integer;
        StartAfter: Boolean;
        EndAfter: Boolean;
    begin
        for I := 1 to DEdge.Count() do begin
            E := DEdge.Get(I);
            S := DSrc.Get(I);
            if S = DDst.Get(I) then begin
                if not LoopSeen.Get(S, K) then
                    K := 0;
                if LoopSeen.ContainsKey(S) then
                    LoopSeen.Set(S, K + 1)
                else
                    LoopSeen.Add(S, K + 1);
                DLoopAt.Set(I, K);
                X := Layout.NodeX(S) + VW.Get(S) / 2;
                Spread := MText.MinDec(VH.Get(S) / 2 - 4, 8 + K * 6);
                Card(GeStartText.Get(E), DStartRoom.Get(I), X, Layout.NodeY(S) - Spread, 1, false);
                Card(GeEndText.Get(E), DEndRoom.Get(I), X, Layout.NodeY(S) + Spread, 1, true);
            end else
                if RouteCount(I) >= 6 then begin
                    LastAt := RouteCount(I) - 2;
                    StartEnd := DStartEnd.Get(I);
                    EndEnd := DEndEnd.Get(I);
                    StartSide := 2;
                    StartAfter := true;
                    if StartEnd > 0 then begin
                        StartSide := EnSide.Get(StartEnd);
                        StartAfter := EnAfter.Get(StartEnd);
                    end;
                    EndSide := 0;
                    EndAfter := true;
                    if EndEnd > 0 then begin
                        EndSide := EnSide.Get(EndEnd);
                        EndAfter := EnAfter.Get(EndEnd);
                    end;
                    Card(GeStartText.Get(E), DStartRoom.Get(I), RouteGet(I, 1), RouteGet(I, 2), StartSide, StartAfter);
                    Card(GeEndText.Get(E), DEndRoom.Get(I), RouteGet(I, LastAt), RouteGet(I, LastAt + 1), EndSide, EndAfter);
                end;
        end;
    end;

    // ---------------------------------------------------------------- cluster titles (svg/cluster.ts)

    local procedure MarkCrossings(D: Integer)
    var
        Route: List of [Decimal];
        K: Integer;
    begin
        Route := Routes.Get(D);
        K := 1;
        while K + 2 <= Route.Count() do begin
            CrossKey.Add(Round(Route.Get(K + 1), 1));
            CrossX.Add(Route.Get(K));
            K += 3;
        end;
    end;

    /// <summary>Picks where a cluster title sits along the top edge so that edges entering there do not cross it.</summary>
    local procedure ClusterTitleX(I: Integer; TitleWidth: Decimal): Decimal
    var
        Candidates: List of [Decimal];
        Candidate: Decimal;
        TopKey: Integer;
        Left: Decimal;
        W: Decimal;
        HalfW: Decimal;
        Best: Decimal;
        BestGap: Decimal;
        Gap: Decimal;
        K: Integer;
        Found: Boolean;
    begin
        if TitleWidth = 0 then
            exit(Layout.NodeX(I));
        W := Layout.NodeW(I);
        TopKey := Round(Layout.NodeY(I) - Layout.NodeH(I) / 2, 1);
        Left := Layout.NodeX(I) - W / 2;
        HalfW := TitleWidth / 2;
        Candidates.Add(Left + 20 - 6 + HalfW);
        Candidates.Add(Layout.NodeX(I));
        Candidates.Add(Left + W - 20 + 6 - HalfW);
        Found := CrossKey.Contains(TopKey);
        if not Found then
            exit(Candidates.Get(1));
        Best := Candidates.Get(1);
        BestGap := -1;
        foreach Candidate in Candidates do begin
            Gap := 1000000000;
            for K := 1 to CrossKey.Count() do
                if CrossKey.Get(K) = TopKey then
                    if (CrossX.Get(K) > Left) and (CrossX.Get(K) < Left + W) then
                        Gap := MText.MinDec(Gap, Abs(CrossX.Get(K) - Candidate) - HalfW);
            if Gap >= 6 then
                exit(Candidate);
            if Gap > BestGap + 0.5 then begin
                BestGap := Gap;
                Best := Candidate;
            end;
        end;
        exit(Best);
    end;

    /// <summary>Whether an edge that enters at the top runs through a title placed at X.</summary>
    local procedure TitleCrossed(I: Integer; TitleWidth: Decimal; X: Decimal): Boolean
    var
        TopKey: Integer;
        Left: Decimal;
        W: Decimal;
        K: Integer;
    begin
        if TitleWidth <= 0 then
            exit(false);
        W := Layout.NodeW(I);
        TopKey := Round(Layout.NodeY(I) - Layout.NodeH(I) / 2, 1);
        Left := Layout.NodeX(I) - W / 2;
        for K := 1 to CrossKey.Count() do
            if CrossKey.Get(K) = TopKey then
                if (CrossX.Get(K) > Left) and (CrossX.Get(K) < Left + W) and (Abs(CrossX.Get(K) - X) < TitleWidth / 2 + 4) then
                    exit(true);
        exit(false);
    end;

    /// <summary>
    /// A title that an edge runs through, drawn over the edges: the text on an outline in the colour of
    /// the cluster behind it, so that only the line is seen to stop short of the letters.
    /// </summary>
    local procedure StruckTitle(var Lbl: Codeunit "Mermaid Label"; X: Decimal; Y: Decimal; Attrs: Text; Id: Text; I: Integer): Text
    var
        Depth: Integer;
        G: Integer;
        Fill: Text;
    begin
        Depth := 1;
        G := GParent.Get(I);
        while (G > 0) and (Depth < 8) do begin
            Depth += 1;
            G := GParent.Get(G);
        end;
        // Each cluster is half its fill over what is behind it.
        Fill := 'color-mix(in srgb,var(--_a) ' + MText.Num(100 * (1 - Power(0.5, Depth))) + '%,var(--_bg))';
        exit('<g class="pele-cluster-title" data-id="' + Id + '">' +
             Lbl.ToSvg(X, Y, ' fill="none" stroke="' + Fill + '" stroke-width="5" stroke-linejoin="round"') +
             Lbl.ToSvg(X, Y, Attrs) + '</g>');
    end;

    // ---------------------------------------------------------------- drawing

    local procedure DrawNodes(Ox: Decimal; Oy: Decimal; var ClustersOut: Text; var StruckOut: Text; var NodesOut: Text)
    var
        Lbl: Codeunit "Mermaid Label";
        Clusters: TextBuilder;
        Struck: TextBuilder;
        Nodes: TextBuilder;
        I: Integer;
        Id: Text;
        X: Decimal;
        Y: Decimal;
        W: Decimal;
        H: Decimal;
        R: Decimal;
        T: Decimal;
        TitleX: Decimal;
        TitleY: Decimal;
        TitleAttrs: Text;
        At: Text;
        IsStruck: Boolean;
        IsGroupNode: Boolean;
    begin
        TitleAttrs := ' class="pele-cluster-label" fill="var(--_m)"';
        for I := 1 to GId.Count() do begin
            ViewLabel(I, Lbl);
            X := Layout.NodeX(I) + Ox;
            Y := Layout.NodeY(I) + Oy;
            Id := MText.EscText(GId.Get(I));
            IsGroupNode := Layout.IsGroup(I);
            if IsGroupNode then begin
                W := Layout.NodeW(I);
                H := Layout.NodeH(I);
            end else begin
                W := VW.Get(I);
                H := VH.Get(I);
            end;
            if GIsGroup.Get(I) then begin
                if IsGroupNode then
                    TitleX := ClusterTitleX(I, Lbl.GetWidth())
                else
                    TitleX := Layout.NodeX(I);
                TitleY := Y - H / 2 + 8 + Lbl.GetHeight() / 2;
                IsStruck := false;
                if IsGroupNode then
                    IsStruck := TitleCrossed(I, Lbl.GetWidth(), TitleX);
                if IsStruck then
                    Struck.Append(StruckTitle(Lbl, TitleX + Ox, TitleY, TitleAttrs, Id, I));
                Clusters.Append('<g class="pele-cluster pele-namespace" data-id="' + Id + '">' +
                                '<rect x="' + MText.Num(X - W / 2) + '" y="' + MText.Num(Y - H / 2) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) +
                                '" rx="' + Builder.Radius() + '" fill="var(--_a)" fill-opacity="0.5" stroke="var(--_b)"/>');
                if not IsStruck then
                    Clusters.Append(Lbl.ToSvg(TitleX + Ox, TitleY, TitleAttrs));
                Clusters.Append('</g>');
            end else begin
                At := ' transform="translate(' + Builder.P(X, Y) + ')"';
                if GClass.Get(I) > 0 then
                    Nodes.Append(ClassSvg(I, GClass.Get(I), Lbl, Id, At))
                else
                    if GShape.Get(I) = 'note' then begin
                        R := W / 2;
                        T := -H / 2;
                        Nodes.Append('<g class="pele-node pele-note" data-id="' + Id + '"' + At + '>' +
                                     '<path d="M' + Builder.P(-R, T) + 'H' + MText.Num(R - 8) + 'L' + Builder.P(R, T + 8) + 'V' + MText.Num(-T) + 'H' + MText.Num(-R) +
                                     'Z" fill="var(--_a)" stroke="var(--_b)" stroke-linejoin="round"/>' +
                                     '<path d="M' + Builder.P(R - 8, T) + 'V' + MText.Num(T + 8) + 'H' + MText.Num(R) + '" fill="none" stroke="var(--_b)" stroke-linejoin="round"/>' +
                                     Lbl.ToSvg(0, 0, ' class="pele-label" font-size="' + MText.Num(Small) + '"') + '</g>');
                    end else
                        Nodes.Append('<g class="pele-node pele-interface" data-id="' + Id + '"' + At + '>' +
                                     Lbl.ToSvg(0, 0, ' class="pele-label" font-size="' + MText.Num(Small) + '"') + '</g>');
            end;
        end;
        ClustersOut := Clusters.ToText();
        StruckOut := Struck.ToText();
        NodesOut := Nodes.ToText();
    end;

    local procedure ClassSvg(I: Integer; K: Integer; var Lbl: Codeunit "Mermaid Label"; Id: Text; At: Text): Text
    var
        Body: TextBuilder;
        Result: Text;
        W: Decimal;
        H: Decimal;
        Left: Decimal;
        Top: Decimal;
        FirstY: Decimal;
        SecondY: Decimal;
        Y: Decimal;
        MemberSize: Decimal;
        LineHeight: Decimal;
        StrokeAttr: Text;
        TitleSize: Text;
        TextAttr: Text;
        Target: Text;
        Href: Text;
        M: Integer;
    begin
        W := VW.Get(I);
        H := VH.Get(I);
        Left := -W / 2;
        Top := -H / 2;
        MemberSize := Round(VFontSize.Get(I) * 0.875, 1);
        LineHeight := Round(MemberSize * 1.5, 1);
        TextAttr := VTextAttr.Get(I);
        Body.Append('<rect x="' + MText.Num(Left) + '" y="' + MText.Num(Top) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) +
                    '" rx="' + Builder.Radius() + '" fill="var(--_s)" stroke="var(--_b)"' + VShapeAttr.Get(I) + '/>');
        FirstY := Top + VTitleH.Get(I);
        SecondY := FirstY + VAttrH.Get(I);
        if H > VTitleH.Get(I) then begin
            StrokeAttr := '';
            if VStroke.Get(I) <> '' then
                StrokeAttr := ' style="stroke:' + MText.Esc(VStroke.Get(I)) + '"';
            Body.Append('<path class="pele-divider" d="M' + Builder.P(Left, FirstY) + 'H' + MText.Num(-Left) + 'M' + Builder.P(Left, SecondY) + 'H' + MText.Num(-Left) +
                        '" fill="none" stroke="var(--_b)"' + StrokeAttr + '/>');
        end;
        Y := Top + 8;
        for M := 1 to AnLineNode.Count() do
            if AnLineNode.Get(M) = I then begin
                Body.Append('<text class="pele-annotation" x="0" y="' + MText.Num(Y + TinyHeight / 2 + Tiny * 0.35) + '" text-anchor="middle" font-size="' + MText.Num(Tiny) +
                            '" fill="var(--_m)">' + MText.Esc(AnLineText.Get(M)) + '</text>');
                Y += TinyHeight;
            end;
        TitleSize := '';
        if VFontSize.Get(I) <> Size then
            TitleSize := ' font-size="' + MText.Num(VFontSize.Get(I)) + '"';
        Body.Append(Lbl.ToSvg(0, (Y + FirstY - 8) / 2, ' class="pele-label"' + TitleSize + ' font-weight="var(--_hw)"' + TextAttr));
        if (VAttrCount.Get(I) > 0) or (VMethCount.Get(I) > 0) then
            Body.Append('<g class="pele-members" font-size="' + MText.Num(MemberSize) + '">' +
                        MemberLines(I, false, FirstY, Left, MemberSize, LineHeight, TextAttr) +
                        MemberLines(I, true, SecondY, Left, MemberSize, LineHeight, TextAttr) + '</g>');
        Result := Body.ToText();
        if ClsTooltip.Get(K) <> '' then
            Result := '<title>' + MText.EscText(ClsTooltip.Get(K)) + '</title>' + Result;
        Href := LinkUrl(ClsLink.Get(K));
        if Href <> '' then begin
            Target := '';
            if ClsLinkTarget.Get(K) in ['_self', '_blank', '_parent', '_top'] then
                Target := ' target="' + ClsLinkTarget.Get(K) + '"';
            Result := '<a href="' + MText.Esc(Href) + '"' + Target + ' rel="noopener">' + Result + '</a>';
        end;
        exit('<g class="pele-node pele-class' + Builder.ClassNames(CssWithoutDefault(ClsCss.Get(K))) + '" data-id="' + Id + '"' +
             Builder.CallbackAttrs(ClsCallback.Get(K), ClsCallbackArgs.Get(K)) + At + '>' + Result + '</g>');
    end;

    local procedure CssWithoutDefault(Css: Text): Text
    begin
        if not Css.StartsWith('default') then
            exit(Css);
        Css := CopyStr(Css, 8);
        if MText.IsSpace(MText.CharAt(Css, 1)) then
            Css := CopyStr(Css, 2);
        exit(Css);
    end;

    /// <summary>A sanitized link kept only when it is relative or uses a scheme a host allows; empty otherwise.</summary>
    local procedure LinkUrl(Url: Text): Text
    var
        FlowRenderer: Codeunit "Mermaid Flowchart Renderer";
    begin
        if Url = '' then
            exit('');
        if (MText.CharAt(Url, 1) in [47, 92]) and (MText.CharAt(Url, 2) in [47, 92]) then
            exit('');
        if not FlowRenderer.IsSafeLink(Url) then
            exit('');
        exit(Url);
    end;

    local procedure MemberLines(I: Integer; Methods: Boolean; FromY: Decimal; Left: Decimal; MemberSize: Decimal; LineHeight: Decimal; TextAttr: Text): Text
    var
        Out: TextBuilder;
        M: Integer;
        Baseline: Decimal;
        Mark: Text;
        Kind: Text;
    begin
        Kind := 'attribute';
        if Methods then
            Kind := 'method';
        Baseline := FromY + 6 + LineHeight / 2 + MemberSize * 0.35;
        for M := 1 to LnNode.Count() do
            if LnNode.Get(M) = I then
                if LnIsMethod.Get(M) = Methods then begin
                    case LnClassifier.Get(M) of
                        '$':
                            if TextAttr <> '' then
                                Mark := ' pele-static"' + CopyStr(TextAttr, 1, StrLen(TextAttr) - 1) + 'text-decoration:underline"'
                            else
                                Mark := ' pele-static" style="text-decoration:underline"';
                        '*':
                            Mark := ' pele-abstract" font-style="italic"' + TextAttr;
                        else
                            Mark := '"' + TextAttr;
                    end;
                    Out.Append('<text class="pele-member pele-' + Kind + Mark + ' x="' + MText.Num(Left + 12) + '" y="' + MText.Num(Baseline) + '">' +
                               MText.Esc(LnText.Get(M)) + '</text>');
                    Baseline += LineHeight;
                end;
        exit(Out.ToText());
    end;

    local procedure DrawEdges(Ox: Decimal; Oy: Decimal; var EdgesOut: Text; var LabelsOut: Text)
    var
        Lbl: Codeunit "Mermaid Label";
        Edges: TextBuilder;
        Labels: TextBuilder;
        I: Integer;
        E: Integer;
        S: Integer;
        K: Integer;
        StartType: Text;
        EndTypeName: Text;
        StartTrim: Decimal;
        EndTrim: Decimal;
        X: Decimal;
        Y: Decimal;
        Spread: Decimal;
        Reach: Decimal;
        D: Text;
        Sx: Decimal;
        Sy: Decimal;
        Sdx: Decimal;
        Sdy: Decimal;
        Ex: Decimal;
        Ey: Decimal;
        Edx: Decimal;
        Edy: Decimal;
        Attrs: Text;
        EdgeClass: Text;
        Drawn: Boolean;
    begin
        for I := 1 to DEdge.Count() do begin
            E := DEdge.Get(I);
            S := DSrc.Get(I);
            StartType := GeStartMarker.Get(E);
            EndTypeName := GeEndMarker.Get(E);
            StartTrim := ClassMarkerTrim(StartType);
            EndTrim := ClassMarkerTrim(EndTypeName);
            Drawn := false;
            if S = DDst.Get(I) then begin
                K := DLoopAt.Get(I);
                X := Layout.NodeX(S) + Ox + VW.Get(S) / 2;
                Y := Layout.NodeY(S) + Oy;
                Spread := MText.MinDec(VH.Get(S) / 2 - 4, 8 + K * 6);
                Reach := 26 + K * 8;
                D := 'M' + Builder.P(X + StartTrim, Y - Spread) + 'C' + Builder.P(X + Reach + StartTrim, Y - Spread) + ' ' +
                     Builder.P(X + Reach + EndTrim, Y + Spread) + ' ' + Builder.P(X + EndTrim, Y + Spread);
                Sx := X;
                Sy := Y - Spread;
                Sdx := -1;
                Sdy := 0;
                Ex := X;
                Ey := Y + Spread;
                Edx := -1;
                Edy := 0;
                DLabX.Set(I, Layout.NodeX(S) + VW.Get(S) / 2 + Reach + 4 + DLayoutW.Get(I) / 2);
                DLabY.Set(I, Layout.NodeY(S));
                Drawn := true;
            end else
                Drawn := DrawRoute(I, Ox, Oy, StartTrim, EndTrim, D, Sx, Sy, Sdx, Sdy, Ex, Ey, Edx, Edy);
            if Drawn then begin
                Attrs := '';
                if GePattern.Get(E) = 'dashed' then
                    Attrs := ' stroke-dasharray="6 4"'
                else
                    if GePattern.Get(E) = 'dotted' then
                        Attrs := ' stroke-dasharray="2 4"';
                EdgeClass := ' pele-relation';
                if GePattern.Get(E) = 'dotted' then
                    EdgeClass := ' pele-note-edge';
                Edges.Append('<g class="pele-edge' + EdgeClass + '" data-id="' + MText.EscText(GeId.Get(E)) + '">' +
                             '<path d="' + D + '"' + Attrs + '/>' +
                             ClassMarker(StartType, Sx, Sy, Sdx, Sdy, 'var(--_l)') +
                             ClassMarker(EndTypeName, Ex, Ey, Edx, Edy, 'var(--_l)') + '</g>');
            end;
            if DLabelW.Get(I) > 0 then begin
                Lbl.Layout(GeLabel.Get(E), true, Small, 200, 0);
                Labels.Append(Builder.EdgeLabelSvg(GeId.Get(E), Lbl, DLabX.Get(I) + Ox, DLabY.Get(I) + Oy, ''));
            end;
        end;
        EdgesOut := Edges.ToText();
        LabelsOut := Labels.ToText();
    end;

    local procedure DrawRoute(I: Integer; Ox: Decimal; Oy: Decimal; StartTrim: Decimal; EndTrim: Decimal; var D: Text; var Sx: Decimal; var Sy: Decimal; var Sdx: Decimal; var Sdy: Decimal; var Ex: Decimal; var Ey: Decimal; var Edx: Decimal; var Edy: Decimal): Boolean
    var
        Route: List of [Decimal];
        Shifted: List of [Decimal];
        K: Integer;
    begin
        Route := Routes.Get(I);
        if Route.Count() < 6 then
            exit(false);
        K := 1;
        while K + 2 <= Route.Count() do begin
            Shifted.Add(Route.Get(K) + Ox);
            Shifted.Add(Route.Get(K + 1) + Oy);
            Shifted.Add(Route.Get(K + 2));
            K += 3;
        end;
        Builder.RoutePath(Shifted, '', StartTrim, EndTrim, D, Sx, Sy, Sdx, Sdy, Ex, Ey, Edx, Edy);
        exit(D <> '');
    end;

    local procedure DrawCards(Ox: Decimal; Oy: Decimal): Text
    var
        Out: TextBuilder;
        I: Integer;
    begin
        for I := 1 to CardText.Count() do
            Out.Append('<text class="pele-cardinality" x="' + MText.Num(CardX.Get(I) + Ox) + '" y="' + MText.Num(CardY.Get(I) + Oy + Tiny * 0.35) +
                       '" text-anchor="middle">' + MText.Esc(CardText.Get(I)) + '</text>');
        exit(Out.ToText());
    end;
}
