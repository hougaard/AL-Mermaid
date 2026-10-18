/// <summary>
/// Port of pele's diagrams/state: lexer.ts (the grammar's lexer, with its state stack), parser.ts (the grammar),
/// db.ts (Mermaid's StateDB in its version 2 form: docTranslator, regions, classes, styles, links), graph.ts
/// (Mermaid's dataFetcher) and render.ts. Used for both stateDiagram and stateDiagram-v2.
///
/// Supported: states, descriptions (state "x" as y, y : x, several description lines), transitions with labels,
/// [*] start and end states (scoped to their composite), composite states as groups of the compound layout with
/// their own direction, concurrent regions (--) with dashed dividers, fork, join and choice, notes (left of /
/// right of, single line and multi-line), classDef / class / ::: / style, click with href (sanitized links),
/// accTitle / accDescr and the front-matter title. Left out: icons, the narrowing of wide diagrams, callbacks.
/// </summary>
codeunit 68914 "Mermaid State Diagram"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Layout: Codeunit "Mermaid Compound Layout";
        // ---- lexer
        Src: Text;
        LowerSrc: Text;
        N: Integer;
        P: Integer;
        LexState: Integer;
        LexStack: List of [Integer];
        TokType: List of [Integer];
        TokText: List of [Text];
        TokStart: List of [Integer];
        LexError: Text;
        DirAt: array[4] of Integer;
        DirEnd: array[4] of Integer;
        StereoAt: array[6] of Integer;
        DirFrom: Integer;
        DirNext: Integer;
        DirCached: Boolean;
        // ---- parser
        Tk: Integer;
        CurDoc: Integer;
        OuterDocs: List of [Integer];
        DividerCount: Integer;
        DiagramTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        // ---- statements: a statement belongs to the document of the statement SInDoc names (0 the root, -1 none)
        SKind: List of [Text];
        SId: List of [Text];
        SType: List of [Text];
        SDescrMode: List of [Integer];
        SDescr: List of [Text];
        SDescrCnt: List of [Integer];
        SHasDoc: List of [Boolean];
        SInDoc: List of [Integer];
        SHasNote: List of [Boolean];
        SNotePos: List of [Text];
        SNoteText: List of [Text];
        SStart: List of [Integer];
        SClass: List of [Text];
        SHasClass: List of [Boolean];
        SRel1: List of [Integer];
        SRel2: List of [Integer];
        SValue: List of [Text];
        STooltip: List of [Text];
        // ---- the states of the root document, for their classes and styles
        KIndex: Dictionary of [Text, Integer];
        KClasses: List of [Text];
        KClassCnt: List of [Integer];
        KStyles: List of [Text];
        KStyleCnt: List of [Integer];
        ClassStyles: Dictionary of [Text, Text];
        ClassStyleCnt: Dictionary of [Text, Integer];
        LinkUrl: Dictionary of [Text, Text];
        LinkTip: Dictionary of [Text, Text];
        // ---- drafts (dataFetcher's nodeDb)
        DIndex: Dictionary of [Text, Integer];
        DShape: List of [Text];
        DDescrMode: List of [Integer];
        DDescr: List of [Text];
        DDescrCnt: List of [Integer];
        DCss: List of [Text];
        DStyles: List of [Text];
        DStyleCnt: List of [Integer];
        DType: List of [Text];
        DDir: List of [Text];
        // ---- graph nodes
        GIndex: Dictionary of [Text, Integer];
        GId: List of [Text];
        GShape: List of [Text];
        GLabel: List of [Text];
        GDescr: List of [Text];
        GDescrCnt: List of [Integer];
        GCss: List of [Text];
        GCompiled: List of [Text];
        GCompiledCnt: List of [Integer];
        GStyles: List of [Text];
        GStyleCnt: List of [Integer];
        GIsGroup: List of [Boolean];
        GHasParent: List of [Boolean];
        GParentId: List of [Text];
        GDir: List of [Text];
        GPosition: List of [Text];
        GHasNoteFor: List of [Boolean];
        GNoteFor: List of [Text];
        // ---- graph edges
        EId: List of [Text];
        EStart: List of [Text];
        EEnd: List of [Text];
        ELabel: List of [Text];
        EDashed: List of [Boolean];
        Counter: Integer;
        // ---- views, one per layout node
        ViewIndex: Dictionary of [Text, Integer];
        VNode: List of [Integer];
        VKind: List of [Integer];
        VShapeAttr: List of [Text];
        VLineAttr: List of [Text];
        VTextAttr: List of [Text];
        VTextStyle: List of [Integer];
        VLblRaw: List of [Text];
        VLblSize: List of [Decimal];
        VLblWrap: List of [Decimal];
        VLblW: List of [Decimal];
        VLblH: List of [Decimal];
        VW: List of [Decimal];
        VH: List of [Decimal];
        VTitleH: List of [Decimal];
        CPar: List of [Integer];
        CIsGrp: List of [Boolean];
        CDir: List of [Text];
        Logical: List of [Integer];
        Owners: List of [Integer];
        Appear: List of [Decimal];
        Degree: List of [Integer];
        OutCnt: List of [Integer];
        InCnt: List of [Integer];
        Noted: List of [Boolean];
        LoopCount: List of [Integer];
        LoopWidth: List of [Decimal];
        LoopHeight: List of [Decimal];
        LoopSeen: List of [Integer];
        LoopText: List of [Decimal];
        // ---- layout edges
        DGEdge: List of [Integer];
        DSrc: List of [Integer];
        DDst: List of [Integer];
        DLabelW: List of [Decimal];
        Anchors: Dictionary of [Integer, Integer];
        CrossX: List of [Decimal];
        CrossY: List of [Decimal];
        Dividers: TextBuilder;
        RootDir: Text;
        Size: Decimal;
        Small: Decimal;
        WrapWidth: Decimal;
        Pad: Decimal;
        StateCount: Integer;
        SeqNo: Integer;

    // Token types, in the order of pele's tokens.ts:
    // 0 $end, 1 ERROR, 2 NL, 3 SD, 4 DESCR, 5 -->, 6 HIDE_EMPTY, 7 scale, 8 WIDTH, 9 COMPOSIT_STATE, 10 STRUCT_START,
    // 11 STRUCT_STOP, 12 STATE_DESCR, 13 AS, 14 ID, 15 FORK, 16 JOIN, 17 CHOICE, 18 CONCURRENT, 19 note, 20 NOTE_TEXT,
    // 21 acc_title, 22 acc_title_value, 23 acc_descr, 24 acc_descr_value, 25 acc_descr_multiline_value, 26 CLICK,
    // 27 STRING, 28 HREF, 29 classDef, 30 CLASSDEF_ID, 31 DEFAULT_CLASSDEF_ID, 32 CLASSDEF_STYLEOPTS, 33 DEFAULT,
    // 34 style, 35 STYLE_IDS, 36 STYLEDEF_STYLEOPTS, 37 class, 38 CLASSENTITY_IDS, 39 STYLECLASS, 40 direction_tb,
    // 41 direction_bt, 42 direction_rl, 43 direction_lr, 44 EDGE_STATE, 45 STYLE_SEPARATOR, 46 left_of, 47 right_of,
    // 48 INVALID.
    // Lexer states: 0 INITIAL, 1 struct, 2 STATE, 3 STATE_STRING, 4 STATE_ID, 5 SCALE, 6 acc_title, 7 acc_descr,
    // 8 acc_descr_multiline, 9 CLASSDEF, 10 CLASSDEFID, 11 CLASS, 12 CLASS_STYLE, 13 STYLE, 14 STYLEDEF_STYLES,
    // 15 NOTE, 16 NOTE_ID, 17 NOTE_TEXT, 18 FLOATING_NOTE, 19 FLOATING_NOTE_ID.
    // View kinds: 0 State, 1 Described, 2 Start, 3 End, 4 Choice, 5 Fork, 6 Join, 7 Note, 8 Composite, 9 Region, 10 Hidden.

    local procedure TokenName(TokT: Integer): Text
    begin
        case TokT of
            0:
                exit('$end');
            1, 48:
                exit('INVALID');
            2:
                exit('NL');
            3:
                exit('SD');
            4:
                exit('DESCR');
            5:
                exit('-->');
            6:
                exit('HIDE_EMPTY');
            7:
                exit('scale');
            8:
                exit('WIDTH');
            9:
                exit('COMPOSIT_STATE');
            10:
                exit('STRUCT_START');
            11:
                exit('STRUCT_STOP');
            12:
                exit('STATE_DESCR');
            13:
                exit('AS');
            14:
                exit('ID');
            15:
                exit('FORK');
            16:
                exit('JOIN');
            17:
                exit('CHOICE');
            18:
                exit('CONCURRENT');
            19:
                exit('note');
            20:
                exit('NOTE_TEXT');
            21:
                exit('acc_title');
            22:
                exit('acc_title_value');
            23:
                exit('acc_descr');
            24:
                exit('acc_descr_value');
            25:
                exit('acc_descr_multiline_value');
            26:
                exit('CLICK');
            27:
                exit('STRING');
            28:
                exit('HREF');
            29:
                exit('classDef');
            30:
                exit('CLASSDEF_ID');
            31:
                exit('DEFAULT_CLASSDEF_ID');
            32:
                exit('CLASSDEF_STYLEOPTS');
            33:
                exit('DEFAULT');
            34:
                exit('style');
            35:
                exit('STYLE_IDS');
            36:
                exit('STYLEDEF_STYLEOPTS');
            37:
                exit('class');
            38:
                exit('CLASSENTITY_IDS');
            39:
                exit('STYLECLASS');
            40:
                exit('direction_tb');
            41:
                exit('direction_bt');
            42:
                exit('direction_rl');
            43:
                exit('direction_lr');
            44:
                exit('EDGE_STATE');
            45:
                exit('STYLE_SEPARATOR');
            46:
                exit('left_of');
            47:
                exit('right_of');
        end;
        exit('INVALID');
    end;

    // ---------------------------------------------------------------- parse

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    begin
        ClearAll();
        Src := Source;
        LowerSrc := LowerCase(Source);
        N := StrLen(Src);
        DiagramTitle := FrontTitle;
        Tokenize();
        ParseTokens();
        TranslateDoc(0, 'root');
        Extract();
        BuildGraph();
    end;

    // ---------------------------------------------------------------- lexer helpers

    local procedure LowerAscii(C: Integer): Integer
    begin
        if (C >= 65) and (C <= 90) then
            exit(C + 32);
        exit(C);
    end;

    /// <summary>Case-insensitive match of a lowercase ASCII word at Q, as the grammar's /i flag gives.</summary>
    local procedure Word(W: Text; Q: Integer): Boolean
    var
        I: Integer;
        A: Integer;
        C: Integer;
    begin
        for I := 1 to StrLen(W) do begin
            A := W[I];
            C := MText.CharAt(Src, Q + I - 1);
            if C <> A then
                if not ((A >= 97) and (A <= 122) and (C = A - 32)) then
                    exit(false);
        end;
        exit(true);
    end;

    local procedure WsEnd(Q: Integer): Integer
    begin
        while MText.IsSpace(MText.CharAt(Src, Q)) do
            Q += 1;
        exit(Q);
    end;

    /// <summary>Past the spaces at Q that are not line feeds.</summary>
    local procedure BlankEnd(Q: Integer): Integer
    var
        C: Integer;
    begin
        C := MText.CharAt(Src, Q);
        while (C <> 10) and MText.IsSpace(C) do begin
            Q += 1;
            C := MText.CharAt(Src, Q);
        end;
        exit(Q);
    end;

    local procedure WordEnd(Q: Integer): Integer
    begin
        while MText.IsWord(MText.CharAt(Src, Q)) do
            Q += 1;
        exit(Q);
    end;

    local procedure Eol(Q: Integer): Integer
    var
        K: Integer;
    begin
        K := MText.IndexOfFrom(Src, MText.LF(), Q);
        if K = 0 then
            exit(N + 1);
        exit(K);
    end;

    local procedure LineEnd(Q: Integer): Integer
    begin
        if Q < 1 then
            Q := 1;
        while (Q <= N) and not MText.IsLineEnd(MText.CharAt(Src, Q)) do
            Q += 1;
        exit(Q);
    end;

    local procedure OrEnd(Pos: Integer): Integer
    begin
        if Pos = 0 then
            exit(N + 1);
        exit(Pos);
    end;

    local procedure IsComment(C: Integer): Boolean
    begin
        if C = 35 then
            exit(true);
        if C = 37 then
            if MText.CharAt(Src, P + 1) = 37 then
                exit(MText.CharAt(Src, P + 2) <> 123);
        exit(false);
    end;

    local procedure Emit(TokT: Integer; S: Integer; E: Integer)
    begin
        TokType.Add(TokT);
        TokText.Add(MText.Substr(Src, S, E));
        TokStart.Add(S);
        P := E;
    end;

    local procedure EmitText(TokT: Integer; Value: Text; S: Integer; E: Integer)
    begin
        TokType.Add(TokT);
        TokText.Add(Value);
        TokStart.Add(S);
        P := E;
    end;

    local procedure Push(NewState: Integer)
    begin
        LexStack.Add(LexState);
        LexState := NewState;
    end;

    local procedure Pop()
    begin
        if LexStack.Count() > 0 then begin
            LexState := LexStack.Get(LexStack.Count());
            LexStack.RemoveAt(LexStack.Count());
        end;
    end;

    local procedure Finish(TokT: Integer)
    begin
        TokType.Add(TokT);
        TokText.Add('');
        TokStart.Add(P);
    end;

    /// <summary>The grammar's processId(): an id ends at an inline %%, and a text that starts with one is dropped.</summary>
    local procedure EmitId(S: Integer; E: Integer): Boolean
    var
        At: Integer;
    begin
        At := MText.IndexOfFrom(Src, '%%', S);
        if (At = 0) or (At + 2 > E) then begin
            Emit(14, S, E);
            exit(true);
        end;
        if At = S then begin
            P := E;
            exit(false);
        end;
        Emit(14, S, At);
        exit(true);
    end;

    local procedure NextDirection(Q: Integer): Integer
    begin
        if DirCached and (Q >= DirFrom) then
            if (DirNext = 0) or (Q <= DirNext) then
                exit(DirNext);
        DirNext := MText.IndexOfFrom(LowerSrc, 'direction', Q);
        DirFrom := Q;
        DirCached := true;
        exit(DirNext);
    end;

    /// <summary>Rules .*direction\s+TB[^\n]* and its siblings: the first kind, in grammar order, found between Q and the end of its line.</summary>
    local procedure Direction(Q: Integer): Integer
    var
        First: Integer;
        E: Integer;
        D: Integer;
        W: Integer;
        Kind: Integer;
    begin
        for Kind := 1 to 4 do
            DirAt[Kind] := -1;
        First := NextDirection(Q);
        if First = 0 then
            exit(-1);
        E := LineEnd(Q);
        D := First;
        while (D <> 0) and (D < E) do begin
            W := WsEnd(D + 9);
            if W <> D + 9 then begin
                Kind := -1;
                if Word('tb', W) then
                    Kind := 0
                else
                    if Word('bt', W) then
                        Kind := 1
                    else
                        if Word('rl', W) then
                            Kind := 2
                        else
                            if Word('lr', W) then
                                Kind := 3;
                if Kind <> -1 then begin
                    DirAt[Kind + 1] := D;
                    DirEnd[Kind + 1] := W + 2;
                end;
            end;
            D := NextDirection(D + 1);
        end;
        for Kind := 1 to 4 do
            if DirAt[Kind] >= Q then
                exit(Kind - 1);
        exit(-1);
    end;

    /// <summary>The same for &lt;&lt;fork&gt;&gt;, &lt;&lt;join&gt;&gt;, &lt;&lt;choice&gt;&gt; and their [[ ]] spellings.</summary>
    local procedure Stereotype(Q: Integer): Integer
    var
        E: Integer;
        J: Integer;
        Kind: Integer;
        C: Integer;
    begin
        for Kind := 1 to 6 do
            StereoAt[Kind] := -1;
        E := LineEnd(Q);
        for J := Q to E - 1 do begin
            C := MText.CharAt(Src, J);
            if (C = 60) and (MText.CharAt(Src, J + 1) = 60) then begin
                if Word('fork>>', J + 2) then
                    StereoAt[1] := J;
                if Word('join>>', J + 2) then
                    StereoAt[2] := J;
                if Word('choice>>', J + 2) then
                    StereoAt[3] := J;
            end;
            if (C = 91) and (MText.CharAt(Src, J + 1) = 91) then begin
                if Word('fork]]', J + 2) then
                    StereoAt[4] := J;
                if Word('join]]', J + 2) then
                    StereoAt[5] := J;
                if Word('choice]]', J + 2) then
                    StereoAt[6] := J;
            end;
        end;
        for Kind := 1 to 6 do
            if StereoAt[Kind] >= Q then
                exit(Kind - 1);
        exit(-1);
    end;

    // ---------------------------------------------------------------- lexer

    local procedure Tokenize()
    var
        Done: Boolean;
    begin
        P := 1;
        LexState := 0;
        while not Done do
            if P > N then begin
                // Jison tries the current state's rules once more on the empty remainder.
                case LexState of
                    0:
                        Emit(2, N + 1, N + 1);
                    6:
                        Emit(22, N + 1, N + 1);
                    7:
                        Emit(24, N + 1, N + 1);
                    8:
                        Emit(25, N + 1, N + 1);
                    10:
                        Emit(32, N + 1, N + 1);
                    12:
                        Emit(39, N + 1, N + 1);
                    14:
                        Emit(36, N + 1, N + 1);
                    3:
                        Emit(12, N + 1, N + 1);
                    18:
                        Emit(20, N + 1, N + 1);
                    4, 19:
                        Emit(14, N + 1, N + 1);
                end;
                Finish(0);
                Done := true;
            end else
                Done := LexStep();
    end;

    /// <summary>Lexes one token, or skips text; true when lexing stopped on an error.</summary>
    local procedure LexStep(): Boolean
    var
        C: Integer;
        Q: Integer;
        J: Integer;
        K: Integer;
        E: Integer;
        IsDefault: Boolean;
        Stop: Boolean;
    begin
        C := MText.CharAt(Src, P);
        case LexState of
            0, 1:
                exit(LexMain(C));
            2:
                exit(LexStateName(C));
            3:
                begin
                    if C = 34 then begin
                        P += 1;
                        Pop();
                        exit(false);
                    end;
                    Emit(12, P, OrEnd(MText.IndexOfFrom(Src, '"', P)));
                    exit(false);
                end;
            4:
                begin
                    J := P;
                    while (J <= N) and not (MText.CharAt(Src, J) in [10, 123]) do
                        J += 1;
                    if EmitId(P, J) then
                        Pop();
                    exit(false);
                end;
            5:
                begin
                    if MText.IsDigit(C) then begin
                        J := P + 1;
                        while MText.IsDigit(MText.CharAt(Src, J)) do
                            J += 1;
                        Emit(8, P, J);
                        exit(false);
                    end;
                    Q := WsEnd(P);
                    if (Q > P) and Word('width', Q) and not MText.IsWord(MText.CharAt(Src, Q + 5)) then begin
                        P := Q + 5;
                        Pop();
                        exit(false);
                    end;
                    Finish(1);
                    exit(true);
                end;
            6:
                begin
                    Emit(22, P, Eol(P));
                    Pop();
                    exit(false);
                end;
            7:
                begin
                    Emit(24, P, Eol(P));
                    Pop();
                    exit(false);
                end;
            8:
                begin
                    if C = 125 then begin
                        P += 1;
                        Pop();
                        exit(false);
                    end;
                    Emit(25, P, OrEnd(MText.IndexOfFrom(Src, '}', P)));
                    exit(false);
                end;
            9:
                begin
                    IsDefault := Word('default', P) and (WsEnd(P + 7) > P + 7);
                    if IsDefault then
                        J := P + 7
                    else
                        J := WordEnd(P);
                    E := WsEnd(J);
                    if (J = P) or (E = J) then begin
                        Finish(1);
                        exit(true);
                    end;
                    if IsDefault then
                        Emit(31, P, E)
                    else
                        Emit(30, P, E);
                    Pop();
                    Push(10);
                    exit(false);
                end;
            10:
                begin
                    Emit(32, P, Eol(P));
                    Pop();
                    exit(false);
                end;
            11:
                begin
                    J := WordEnd(P);
                    if J = P then begin
                        Finish(1);
                        exit(true);
                    end;
                    Stop := false;
                    while (MText.CharAt(Src, J) = 44) and not Stop do begin
                        K := WsEnd(J + 1);
                        E := WordEnd(K);
                        if E = K then
                            Stop := true
                        else
                            J := E;
                    end;
                    Emit(38, P, J);
                    Pop();
                    Push(12);
                    exit(false);
                end;
            12:
                begin
                    Emit(39, P, Eol(P));
                    Pop();
                    exit(false);
                end;
            13:
                begin
                    J := P;
                    while MText.IsWord(MText.CharAt(Src, J)) or (MText.CharAt(Src, J) = 44) do
                        J += 1;
                    E := WsEnd(J);
                    if (J = P) or (E = J) then begin
                        Finish(1);
                        exit(true);
                    end;
                    Emit(35, P, E);
                    Pop();
                    Push(14);
                    exit(false);
                end;
            14:
                begin
                    Emit(36, P, Eol(P));
                    Pop();
                    exit(false);
                end;
            15:
                exit(LexNote(C));
            16:
                begin
                    Q := WsEnd(P);
                    J := Q;
                    while (J <= N) and not ((MText.CharAt(Src, J) in [58, 45]) or MText.IsSpace(MText.CharAt(Src, J))) do
                        J += 1;
                    if J = Q then begin
                        Finish(1);
                        exit(true);
                    end;
                    if EmitId(P, J) then begin
                        Pop();
                        Push(17);
                    end;
                    exit(false);
                end;
            17:
                exit(LexNoteText());
            18:
                begin
                    Q := WsEnd(P);
                    if Word('as', Q) then begin
                        Emit(13, P, WsEnd(Q + 2));
                        Pop();
                        Push(19);
                        exit(false);
                    end;
                    if C = 34 then begin
                        P += 1;
                        exit(false);
                    end;
                    Emit(20, P, OrEnd(MText.IndexOfFrom(Src, '"', P)));
                    exit(false);
                end;
            19:
                begin
                    if EmitId(P, Eol(P)) then
                        Pop();
                    exit(false);
                end;
        end;
        Finish(1);
        exit(true);
    end;

    /// <summary>The INITIAL and struct states.</summary>
    local procedure LexMain(C: Integer): Boolean
    var
        IsRoot: Boolean;
        IsDef: Boolean;
        IsTitle: Boolean;
        Stop: Boolean;
        LC: Integer;
        J: Integer;
        E: Integer;
        Q: Integer;
        D: Integer;
        Kind: Integer;
        Close: Integer;
        FromPos: Integer;
        After: Integer;
    begin
        IsRoot := LexState = 0;
        LC := LowerAscii(C);
        if IsRoot then begin
            if (LC = 99) and Word('click', P) and not MText.IsWord(MText.CharAt(Src, P + 5)) then begin
                Emit(26, P, P + 5);
                exit(false);
            end;
            if (LC = 104) and Word('href', P) and not MText.IsWord(MText.CharAt(Src, P + 4)) then begin
                Emit(28, P, P + 4);
                exit(false);
            end;
            if C = 34 then begin
                Close := MText.IndexOfFrom(Src, '"', P + 1);
                if Close <> 0 then begin
                    Emit(27, P, Close + 1);
                    exit(false);
                end;
            end;
            if (LC = 100) and Word('default', P) and not MText.IsWord(MText.CharAt(Src, P + 7)) then begin
                Emit(33, P, P + 7);
                exit(false);
            end;
            Kind := Direction(P);
            if Kind <> -1 then begin
                Emit(40 + Kind, P, Eol(DirEnd[Kind + 1]));
                exit(false);
            end;
            if C = 10 then begin
                J := P + 1;
                while MText.CharAt(Src, J) = 10 do
                    J += 1;
                Emit(2, P, J);
                exit(false);
            end;
            if MText.IsSpace(C) then begin
                P := WsEnd(P);
                exit(false);
            end;
        end else
            if (C <> 10) and MText.IsSpace(C) then begin
                P := BlankEnd(P + 1);
                exit(false);
            end;
        if IsComment(C) then begin
            P := Eol(P);
            exit(false);
        end;
        case LC of
            115:
                begin
                    if IsRoot and Word('scale', P) then begin
                        E := WsEnd(P + 5);
                        if E > P + 5 then begin
                            Emit(7, P, E);
                            Push(5);
                            exit(false);
                        end;
                    end;
                    if Word('style', P) then begin
                        E := WsEnd(P + 5);
                        if E > P + 5 then begin
                            Emit(34, P, E);
                            Push(13);
                            exit(false);
                        end;
                    end;
                    if Word('state', P) then begin
                        E := WsEnd(P + 5);
                        if E > P + 5 then begin
                            P := E;
                            Push(2);
                            exit(false);
                        end;
                        if IsRoot and Word('diagram', P + 5) then begin
                            FromPos := P + 12;
                            if Word('-v2', P + 12) then
                                FromPos := P + 15;
                            E := WsEnd(FromPos);
                            if E > FromPos then begin
                                Emit(3, P, E);
                                exit(false);
                            end;
                        end;
                    end;
                end;
            99:
                if Word('class', P) then begin
                    IsDef := Word('def', P + 5);
                    FromPos := P + 5;
                    if IsDef then
                        FromPos := P + 8;
                    E := WsEnd(FromPos);
                    if E > FromPos then begin
                        if IsDef then begin
                            Emit(29, P, E);
                            Push(9);
                        end else begin
                            Emit(37, P, E);
                            Push(11);
                        end;
                        exit(false);
                    end;
                end;
            97:
                if IsRoot then
                    if Word('acctitle', P) or Word('accdescr', P) then begin
                        IsTitle := LowerAscii(MText.CharAt(Src, P + 3)) = 116;
                        Q := WsEnd(P + 8);
                        D := MText.CharAt(Src, Q);
                        if D = 58 then begin
                            if IsTitle then begin
                                Emit(21, P, WsEnd(Q + 1));
                                Push(6);
                            end else begin
                                Emit(23, P, WsEnd(Q + 1));
                                Push(7);
                            end;
                            exit(false);
                        end;
                        if (D = 123) and not IsTitle then begin
                            P := WsEnd(Q + 1);
                            Push(8);
                            exit(false);
                        end;
                    end;
        end;
        if IsRoot then begin
            if C = 123 then begin
                Emit(10, P, P + 1);
                Push(1);
                exit(false);
            end;
        end else begin
            Kind := Direction(P);
            if Kind <> -1 then begin
                Emit(40 + Kind, P, Eol(DirEnd[Kind + 1]));
                exit(false);
            end;
            if C = 125 then begin
                Emit(11, P, P + 1);
                Pop();
                exit(false);
            end;
            if C = 10 then begin
                P += 1;
                exit(false);
            end;
        end;
        if (LC = 110) and Word('note', P) then begin
            E := WsEnd(P + 4);
            if E > P + 4 then begin
                Emit(19, P, E);
                Push(15);
                exit(false);
            end;
        end;
        if IsRoot and (LC = 104) and Word('hide empty description', P) and not MText.IsWord(MText.CharAt(Src, P + 22)) then begin
            Emit(6, P, P + 22);
            exit(false);
        end;
        if (C = 91) and (MText.CharAt(Src, P + 1) = 42) and (MText.CharAt(Src, P + 2) = 93) then begin
            Emit(44, P, P + 3);
            exit(false);
        end;
        J := P;
        Stop := false;
        while (J <= N) and not Stop do begin
            D := MText.CharAt(Src, J);
            if (D = 58) or (D = 45) or (D = 123) or MText.IsSpace(D) then
                Stop := true
            else
                J += 1;
        end;
        if J > P then begin
            EmitId(P, J);
            exit(false);
        end;
        if C = 58 then begin
            J := P + 1;
            Stop := false;
            while (J <= N) and not Stop do begin
                D := MText.CharAt(Src, J);
                if (D = 10) or (D = 59) then
                    Stop := true
                else begin
                    if D = 58 then begin
                        After := MText.CharAt(Src, J + 1);
                        if (J + 1 > N) or (After = 58) or (After = 10) or (After = 59) then
                            Stop := true
                        else
                            J += 1;
                    end;
                    if not Stop then
                        J += 1;
                end;
            end;
            if J > P + 1 then begin
                EmitText(4, MText.TrimWs(MText.Substr(Src, P, J)), P, J);
                exit(false);
            end;
            if (MText.CharAt(Src, P + 1) = 58) and (MText.CharAt(Src, P + 2) = 58) then begin
                Emit(45, P, P + 3);
                exit(false);
            end;
        end else
            if (C = 45) and (MText.CharAt(Src, P + 1) = 45) then begin
                if MText.CharAt(Src, P + 2) = 62 then begin
                    Emit(5, P, P + 3);
                    exit(false);
                end;
                if not IsRoot then begin
                    Emit(18, P, P + 2);
                    exit(false);
                end;
            end;
        if not IsRoot then begin
            Finish(1);
            exit(true);
        end;
        Emit(48, P, P + 1);
        exit(false);
    end;

    /// <summary>The STATE state, after the state keyword.</summary>
    local procedure LexStateName(C: Integer): Boolean
    var
        IsChoice: Boolean;
        Kind: Integer;
        At: Integer;
        Q: Integer;
        E: Integer;
        J: Integer;
        FirstEnd: Integer;
        SecondPos: Integer;
        Brace: Integer;
        TokT: Integer;
    begin
        if (C <> 10) and MText.IsSpace(C) then begin
            P := BlankEnd(P + 1);
            exit(false);
        end;
        if IsComment(C) then begin
            P := Eol(P);
            exit(false);
        end;
        Kind := Stereotype(P);
        if Kind <> -1 then begin
            At := StereoAt[Kind + 1];
            IsChoice := Kind in [2, 5];
            if IsChoice then
                TokT := 17
            else
                if Kind mod 3 = 0 then
                    TokT := 15
                else
                    TokT := 16;
            if IsChoice then
                E := At + 10
            else
                E := At + 8;
            EmitText(TokT, MText.TrimWs(MText.Substr(Src, P, At)), P, E);
            Pop();
            exit(false);
        end;
        if C = 34 then begin
            P += 1;
            Push(3);
            exit(false);
        end;
        Q := P;
        if C = 10 then
            Q := WsEnd(P);
        if Word('as', Q) then begin
            E := WsEnd(Q + 2);
            if E > Q + 2 then begin
                Emit(13, P, E);
                Push(4);
                exit(false);
            end;
        end;
        if C = 10 then begin
            P += 1;
            Pop();
            exit(false);
        end;
        if C = 123 then begin
            Emit(10, P, P + 1);
            Pop();
            Push(1);
            exit(false);
        end;
        if MText.IsWord(C) then begin
            FirstEnd := WordEnd(P);
            SecondPos := WsEnd(FirstEnd);
            if (SecondPos > FirstEnd) and MText.IsWord(MText.CharAt(Src, SecondPos)) then begin
                Brace := MText.IndexOfFrom(Src, '{', SecondPos + 1);
                if Brace <> 0 then
                    if Brace < LineEnd(SecondPos) then begin
                        LexError := 'Error: State name must be a single word. Found: "' + MText.TrimWs(MText.Substr(Src, P, Brace + 1)) + '"';
                        Finish(1);
                        exit(true);
                    end;
            end;
        end;
        J := P + 1;
        while (J <= N) and not ((MText.CharAt(Src, J) = 123) or MText.IsSpace(MText.CharAt(Src, J))) do
            J += 1;
        Emit(9, P, J);
        exit(false);
    end;

    local procedure LexNote(C: Integer): Boolean
    begin
        if Word('left of', P) and not MText.IsWord(MText.CharAt(Src, P + 7)) then begin
            Emit(46, P, P + 7);
            Pop();
            Push(16);
            exit(false);
        end;
        if Word('right of', P) and not MText.IsWord(MText.CharAt(Src, P + 8)) then begin
            Emit(47, P, P + 8);
            Pop();
            Push(16);
            exit(false);
        end;
        if C = 34 then begin
            P += 1;
            Pop();
            Push(18);
            exit(false);
        end;
        Finish(1);
        exit(true);
    end;

    local procedure LexNoteText(): Boolean
    var
        Q: Integer;
        J: Integer;
        K: Integer;
        E: Integer;
        Found: Boolean;
    begin
        Q := WsEnd(P);
        if MText.CharAt(Src, Q) = 58 then begin
            J := Q + 1;
            while (J <= N) and not (MText.CharAt(Src, J) in [58, 10, 59]) do
                J += 1;
            if J > Q + 1 then begin
                // Mermaid drops two characters here, expecting " :"; with no space before the colon
                // the first character of the note goes too.
                EmitText(20, MText.TrimWs(MText.Substr(Src, P + 2, J)), P, J);
                Pop();
                exit(false);
            end;
        end;
        K := MText.IndexOfFrom(Src, MText.LF(), P);
        E := -1;
        while (K <> 0) and not Found do begin
            E := WsEnd(K);
            if Word('end note', E) and not MText.IsWord(MText.CharAt(Src, E + 8)) then
                Found := true
            else
                K := MText.IndexOfFrom(Src, MText.LF(), E);
        end;
        if not Found then begin
            Finish(1);
            exit(true);
        end;
        EmitText(20, MText.TrimWs(MText.Substr(Src, P, E)), P, E + 8);
        Pop();
        exit(false);
    end;

    // ---------------------------------------------------------------- parser

    local procedure TT(I: Integer): Integer
    begin
        if (I < 1) or (I > TokType.Count()) then
            exit(0);
        exit(TokType.Get(I));
    end;

    local procedure TX(I: Integer): Text
    begin
        if (I < 1) or (I > TokText.Count()) then
            exit('');
        exit(TokText.Get(I));
    end;

    local procedure TS(I: Integer): Integer
    begin
        if (I < 1) or (I > TokStart.Count()) then
            exit(N + 1);
        exit(TokStart.Get(I));
    end;

    local procedure StatementList(): Text
    begin
        exit('''NL'', ''ID'', ''HIDE_EMPTY'', ''scale'', ''COMPOSIT_STATE'', ''STATE_DESCR'', ''FORK'', ''JOIN'', ''CHOICE'', ''CONCURRENT'', ''note'', ' +
             '''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''CLICK'', ''classDef'', ''style'', ''class'', ''direction_tb'', ' +
             '''direction_bt'', ''direction_rl'', ''direction_lr'', ''EDGE_STATE''');
    end;

    local procedure ParseFail(Expected: Text)
    var
        TokT: Integer;
    begin
        TokT := TT(Tk);
        if TokT = 1 then begin
            if LexError <> '' then
                MText.Fail(LexError);
            MText.SyntaxError('state', Src, TS(Tk), '', true);
        end;
        MText.SyntaxError('state', Src, TS(Tk), 'Expecting ' + Expected + ', got ''' + TokenName(TokT) + '''', false);
    end;

    local procedure Expect(TokT: Integer): Text
    begin
        if TT(Tk) <> TokT then
            ParseFail('''' + TokenName(TokT) + '''');
        Tk += 1;
        exit(TX(Tk - 1));
    end;

    local procedure TrimColon(Value: Text): Text
    begin
        if Value.StartsWith(':') then
            exit(MText.TrimWs(CopyStr(Value, 2)));
        exit(MText.TrimWs(Value));
    end;

    local procedure NewStmt(Kind: Text): Integer
    begin
        SKind.Add(Kind);
        SId.Add('');
        SType.Add('');
        SDescrMode.Add(0);
        SDescr.Add('');
        SDescrCnt.Add(0);
        SHasDoc.Add(false);
        SInDoc.Add(-1);
        SHasNote.Add(false);
        SNotePos.Add('');
        SNoteText.Add('');
        SStart.Add(0);
        SClass.Add('');
        SHasClass.Add(false);
        SRel1.Add(0);
        SRel2.Add(0);
        SValue.Add('');
        STooltip.Add('');
        exit(SKind.Count());
    end;

    local procedure NewState(Id: Text; StateType: Text): Integer
    var
        S: Integer;
    begin
        S := NewStmt('state');
        SId.Set(S, Id);
        SType.Set(S, StateType);
        exit(S);
    end;

    local procedure SetDescr(S: Integer; Value: Text)
    begin
        SDescrMode.Set(S, 1);
        SDescr.Set(S, Value);
        SDescrCnt.Set(S, 1);
    end;

    local procedure AddToDoc(S: Integer)
    begin
        SInDoc.Set(S, CurDoc);
    end;

    /// <summary>A text statement, which has no effect on the drawing (hide empty description, scale, a floating note...).</summary>
    local procedure AddStr()
    begin
        AddToDoc(NewStmt('str'));
    end;

    local procedure IdStatement(): Integer
    var
        S: Integer;
        TokT: Integer;
    begin
        TokT := TT(Tk);
        if (TokT <> 14) and (TokT <> 44) then
            ParseFail('''ID'', ''EDGE_STATE''');
        S := NewState(MText.TrimWs(TX(Tk)), 'default');
        SetDescr(S, '');
        Tk += 1;
        if TT(Tk) <> 45 then
            exit(S);
        Tk += 1;
        SClass.Set(S, MText.TrimWs(Expect(14)));
        SHasClass.Set(S, true);
        exit(S);
    end;

    local procedure OpenComposite(Id: Text; Description: Text)
    var
        S: Integer;
    begin
        Tk += 1;
        S := NewState(Id, 'default');
        SetDescr(S, Description);
        SHasDoc.Set(S, true);
        AddToDoc(S);
        OuterDocs.Add(CurDoc);
        CurDoc := S;
    end;

    local procedure DividerId(): Text
    begin
        DividerCount += 1;
        exit('divider-id-' + MText.IntText(DividerCount));
    end;

    local procedure CollapseDescr(Value: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
        C: Integer;
    begin
        I := 1;
        while I <= StrLen(Value) do begin
            C := Value[I];
            Result.Append(CopyStr(Value, I, 1));
            I += 1;
            if C = 10 then
                while MText.IsSpace(MText.CharAt(Value, I)) do
                    I += 1;
        end;
        exit(Result.ToText());
    end;

    local procedure ParseTokens()
    var
        Parts: List of [Text];
        First: Integer;
        Second: Integer;
        S: Integer;
        TokT: Integer;
        Descr: Text;
        Id: Text;
        Position: Text;
        Value: Text;
        Url: Text;
        Tip: Text;
        Done: Boolean;
    begin
        Tk := 1;
        CurDoc := 0;
        while TT(Tk) = 2 do
            Tk += 1;
        if TT(Tk) <> 3 then
            ParseFail('''NL'', ''SD''');
        Tk += 1;
        while not Done do begin
            TokT := TT(Tk);
            case TokT of
                2:
                    Tk += 1;
                14, 44:
                    begin
                        First := IdStatement();
                        if TT(Tk) = 4 then begin
                            SetDescr(First, TrimColon(TX(Tk)));
                            Tk += 1;
                            AddToDoc(First);
                        end else
                            if TT(Tk) = 5 then begin
                                Tk += 1;
                                Second := IdStatement();
                                S := NewStmt('relation');
                                SRel1.Set(S, First);
                                SRel2.Set(S, Second);
                                if TT(Tk) = 4 then begin
                                    SValue.Set(S, TrimColon(TX(Tk)));
                                    Tk += 1;
                                end;
                                AddToDoc(S);
                            end else
                                AddToDoc(First);
                    end;
                6:
                    begin
                        Tk += 1;
                        AddStr();
                    end;
                7:
                    begin
                        Tk += 1;
                        Expect(8);
                        AddStr();
                    end;
                9:
                    if TT(Tk + 1) = 10 then begin
                        Tk += 1;
                        OpenComposite(TX(Tk - 1), '');
                    end else begin
                        Tk += 1;
                        AddStr();
                    end;
                12:
                    begin
                        Descr := TX(Tk);
                        Tk += 1;
                        Expect(13);
                        Id := Expect(14);
                        if TT(Tk) = 10 then
                            OpenComposite(Id, Descr)
                        else
                            if Id.Contains(':') then begin
                                Parts := Id.Split(':');
                                S := NewState(Parts.Get(1), 'default');
                                SDescrMode.Set(S, 2);
                                SDescr.Set(S, MText.TrimWs(Descr) + Sep() + Parts.Get(2));
                                SDescrCnt.Set(S, 2);
                                AddToDoc(S);
                            end else begin
                                S := NewState(Id, 'default');
                                SetDescr(S, MText.TrimWs(Descr));
                                AddToDoc(S);
                            end;
                    end;
                15:
                    begin
                        AddToDoc(NewState(TX(Tk), 'fork'));
                        Tk += 1;
                    end;
                16:
                    begin
                        AddToDoc(NewState(TX(Tk), 'join'));
                        Tk += 1;
                    end;
                17:
                    begin
                        AddToDoc(NewState(TX(Tk), 'choice'));
                        Tk += 1;
                    end;
                18:
                    begin
                        Tk += 1;
                        AddToDoc(NewState(DividerId(), 'divider'));
                    end;
                19:
                    begin
                        Tk += 1;
                        if TT(Tk) in [46, 47] then begin
                            Position := MText.TrimWs(TX(Tk));
                            Tk += 1;
                            Id := MText.TrimWs(Expect(14));
                            S := NewState(Id, '');
                            SHasNote.Set(S, true);
                            SNotePos.Set(S, Position);
                            SNoteText.Set(S, MText.TrimWs(Expect(20)));
                            AddToDoc(S);
                        end else begin
                            if TT(Tk) <> 20 then
                                ParseFail('''NOTE_TEXT'', ''left_of'', ''right_of''');
                            Tk += 1;
                            Expect(13);
                            Expect(14);
                            AddStr();
                        end;
                    end;
                40, 41, 42, 43:
                    begin
                        Tk += 1;
                        S := NewStmt('dir');
                        case TokT of
                            40:
                                SValue.Set(S, 'TB');
                            41:
                                SValue.Set(S, 'BT');
                            42:
                                SValue.Set(S, 'RL');
                            43:
                                SValue.Set(S, 'LR');
                        end;
                        AddToDoc(S);
                    end;
                21:
                    begin
                        Tk += 1;
                        AccTitle := MText.TrimStartWs(MText.TrimWs(Expect(22)));
                        AddStr();
                    end;
                23:
                    begin
                        Tk += 1;
                        AccDescr := CollapseDescr(MText.TrimWs(Expect(24)));
                        AddStr();
                    end;
                25:
                    begin
                        AccDescr := CollapseDescr(MText.TrimWs(TX(Tk)));
                        Tk += 1;
                        AddStr();
                    end;
                26:
                    begin
                        Tk += 1;
                        First := IdStatement();
                        Tip := '';
                        if TT(Tk) = 28 then begin
                            Tk += 1;
                            Url := Expect(27);
                        end else begin
                            if TT(Tk) <> 27 then
                                ParseFail('''STRING'', ''HREF''');
                            Url := TX(Tk);
                            Tk += 1;
                            Tip := Expect(27);
                        end;
                        Expect(2);
                        S := NewStmt('click');
                        SId.Set(S, SId.Get(First));
                        SValue.Set(S, Url);
                        STooltip.Set(S, Tip);
                        AddToDoc(S);
                    end;
                29:
                    begin
                        Tk += 1;
                        S := NewStmt('classDef');
                        SId.Set(S, MText.TrimWs(Expect(30)));
                        SValue.Set(S, MText.TrimWs(Expect(32)));
                        AddToDoc(S);
                    end;
                34:
                    begin
                        Tk += 1;
                        S := NewStmt('style');
                        SId.Set(S, MText.TrimWs(Expect(35)));
                        SValue.Set(S, MText.TrimWs(Expect(36)));
                        AddToDoc(S);
                    end;
                37:
                    begin
                        Tk += 1;
                        S := NewStmt('applyClass');
                        SId.Set(S, MText.TrimWs(Expect(38)));
                        SValue.Set(S, MText.TrimWs(Expect(39)));
                        AddToDoc(S);
                    end;
                11:
                    begin
                        if OuterDocs.Count() = 0 then
                            ParseFail('''$end'', ' + StatementList());
                        Tk += 1;
                        CurDoc := OuterDocs.Get(OuterDocs.Count());
                        OuterDocs.RemoveAt(OuterDocs.Count());
                    end;
                0:
                    begin
                        if OuterDocs.Count() > 0 then
                            ParseFail('''STRUCT_STOP'', ' + StatementList());
                        Done := true;
                    end;
                else
                    if OuterDocs.Count() > 0 then
                        ParseFail('''STRUCT_STOP'', ' + StatementList())
                    else
                        ParseFail('''$end'', ' + StatementList());
            end;
        end;
    end;

    // ---------------------------------------------------------------- model (db.ts)

    local procedure Sep(): Text
    begin
        exit(MText.FromCode(31));
    end;

    local procedure ArrAppend(var Arr: Text; var Cnt: Integer; Value: Text)
    begin
        if Cnt > 0 then
            Arr := Arr + Sep() + Value
        else
            Arr := Value;
        Cnt += 1;
    end;

    local procedure ArrGet(Arr: Text; Index: Integer): Text
    var
        Parts: List of [Text];
    begin
        Parts := Arr.Split(Sep());
        if (Index < 1) or (Index > Parts.Count()) then
            exit('');
        exit(Parts.Get(Index));
    end;

    local procedure AddJoined(var Values: List of [Text]; Arr: Text; Cnt: Integer)
    var
        Part: Text;
    begin
        if Cnt = 0 then
            exit;
        foreach Part in Arr.Split(Sep()) do
            Values.Add(Part);
    end;

    /// <summary>The statements of a document, in order.</summary>
    local procedure DocItems(Owner: Integer): List of [Integer]
    var
        Items: List of [Integer];
        S: Integer;
    begin
        for S := 1 to SKind.Count() do
            if SInDoc.Get(S) = Owner then
                Items.Add(S);
        exit(Items);
    end;

    /// <summary>The direction a document is laid out in: its last direction statement, or TB.</summary>
    local procedure DocDirection(Owner: Integer): Text
    var
        S: Integer;
        Dir: Text;
    begin
        Dir := 'TB';
        foreach S in DocItems(Owner) do
            if SKind.Get(S) = 'dir' then
                Dir := SValue.Get(S);
        exit(Dir);
    end;

    /// <summary>Mermaid's docTranslator: gives each [*] an id scoped to its parent, and turns a document split by -- into one region per part.</summary>
    local procedure TranslateDoc(Owner: Integer; OwnerId: Text)
    var
        Items: List of [Integer];
        Current: List of [Integer];
        S: Integer;
        C: Integer;
        R: Integer;
        RegionCount: Integer;
    begin
        Items := DocItems(Owner);
        foreach S in Items do
            if (SKind.Get(S) = 'state') and (SType.Get(S) = 'divider') and not SHasDoc.Get(S) then begin
                RegionCount += 1;
                SHasDoc.Set(S, true);
                foreach C in Current do
                    SInDoc.Set(C, S);
                Clear(Current);
            end else
                Current.Add(S);
        // Mermaid names the region after the last divider with a random id; here it continues the divider numbering.
        if RegionCount > 0 then
            if Current.Count() > 0 then begin
                R := NewState(DividerId(), 'divider');
                SHasDoc.Set(R, true);
                SInDoc.Set(R, Owner);
                foreach C in Current do
                    SInDoc.Set(C, R);
            end;
        foreach S in DocItems(Owner) do
            TranslateNode(S, OwnerId, true);
    end;

    local procedure TranslateNode(S: Integer; ParentId: Text; First: Boolean)
    begin
        case SKind.Get(S) of
            'relation':
                begin
                    TranslateNode(SRel1.Get(S), ParentId, true);
                    TranslateNode(SRel2.Get(S), ParentId, false);
                end;
            'state':
                begin
                    if SId.Get(S) = '[*]' then begin
                        if First then begin
                            SId.Set(S, ParentId + '_start');
                            SStart.Set(S, 1);
                        end else begin
                            SId.Set(S, ParentId + '_end');
                            SStart.Set(S, 2);
                        end;
                    end else
                        SId.Set(S, MText.TrimWs(SId.Get(S)));
                    if SHasDoc.Get(S) then
                        TranslateDoc(S, SId.Get(S));
                end;
        end;
    end;

    local procedure EnsureState(Id: Text): Integer
    var
        K: Integer;
    begin
        if KIndex.Get(Id, K) then
            exit(K);
        KClasses.Add('');
        KClassCnt.Add(0);
        KStyles.Add('');
        KStyleCnt.Add(0);
        K := KClasses.Count();
        KIndex.Add(Id, K);
        exit(K);
    end;

    /// <summary>The states a comma-separated list of ids names, created where they do not exist yet.</summary>
    local procedure Named(Ids: Text): List of [Integer]
    var
        Result: List of [Integer];
        Part: Text;
    begin
        foreach Part in Ids.Split(',') do
            Result.Add(EnsureState(MText.TrimWs(Part)));
        exit(Result);
    end;

    local procedure SetCssClass(Ids: Text; ClassName: Text)
    var
        K: Integer;
        Joined: Text;
        Cnt: Integer;
    begin
        foreach K in Named(Ids) do begin
            Joined := KClasses.Get(K);
            Cnt := KClassCnt.Get(K);
            if Cnt > 0 then
                Joined := Joined + ' ' + ClassName
            else
                Joined := ClassName;
            KClasses.Set(K, Joined);
            KClassCnt.Set(K, Cnt + 1);
        end;
    end;

    local procedure AddStyleClass(Id: Text; Attributes: Text)
    var
        Attrib: Text;
        Joined: Text;
        Cnt: Integer;
        At: Integer;
    begin
        if not ClassStyles.ContainsKey(Id) then begin
            ClassStyles.Add(Id, '');
            ClassStyleCnt.Add(Id, 0);
        end;
        if Attributes = '' then
            exit;
        Joined := ClassStyles.Get(Id);
        Cnt := ClassStyleCnt.Get(Id);
        foreach Attrib in Attributes.Split(',') do begin
            At := StrPos(Attrib, ';');
            if At > 0 then
                Attrib := DelStr(Attrib, At, 1);
            ArrAppend(Joined, Cnt, MText.TrimWs(Attrib));
        end;
        ClassStyles.Set(Id, Joined);
        ClassStyleCnt.Set(Id, Cnt);
    end;

    local procedure AddRelationState(S: Integer)
    var
        Id: Text;
    begin
        Id := MText.TrimWs(SId.Get(S));
        EnsureState(Id);
        if SHasClass.Get(S) then
            SetCssClass(Id, MText.TrimWs(SClass.Get(S)));
    end;

    /// <summary>Only the root document's statements become states, classes, styles and links.</summary>
    local procedure Extract()
    var
        S: Integer;
        K: Integer;
        Part: Text;
        Styles: Text;
        StyleCnt: Integer;
    begin
        foreach S in DocItems(0) do
            case SKind.Get(S) of
                'state':
                    EnsureState(MText.TrimWs(SId.Get(S)));
                'relation':
                    begin
                        AddRelationState(SRel1.Get(S));
                        AddRelationState(SRel2.Get(S));
                    end;
                'classDef':
                    AddStyleClass(MText.TrimWs(SId.Get(S)), SValue.Get(S));
                'style':
                    begin
                        Styles := '';
                        StyleCnt := 0;
                        foreach Part in SValue.Get(S).Split(',') do
                            ArrAppend(Styles, StyleCnt, MText.TrimWs(Part.Replace(';', '')));
                        foreach K in Named(MText.TrimWs(SId.Get(S))) do begin
                            KStyles.Set(K, Styles);
                            KStyleCnt.Set(K, StyleCnt);
                        end;
                    end;
                'applyClass':
                    SetCssClass(MText.TrimWs(SId.Get(S)), SValue.Get(S));
                'click':
                    begin
                        if LinkUrl.ContainsKey(SId.Get(S)) then begin
                            LinkUrl.Set(SId.Get(S), SValue.Get(S));
                            LinkTip.Set(SId.Get(S), STooltip.Get(S));
                        end else begin
                            LinkUrl.Add(SId.Get(S), SValue.Get(S));
                            LinkTip.Add(SId.Get(S), STooltip.Get(S));
                        end;
                    end;
            end;
    end;

    // ---------------------------------------------------------------- graph (graph.ts)

    local procedure BuildGraph()
    var
        G: Integer;
    begin
        WalkDoc(0, true);
        for G := 1 to GId.Count() do
            if GIsGroup.Get(G) and (GDescrCnt.Get(G) > 0) then
                MText.Fail('Group nodes can only have label. Remove the additional description for node [' + GId.Get(G) + ']');
    end;

    local procedure WalkDoc(Owner: Integer; Alt: Boolean)
    var
        S: Integer;
    begin
        foreach S in DocItems(Owner) do
            case SKind.Get(S) of
                'state':
                    begin
                        Visit(Owner, S, Alt);
                        if SHasDoc.Get(S) then
                            WalkDoc(S, not Alt);
                    end;
                'relation':
                    begin
                        Visit(Owner, SRel1.Get(S), Alt);
                        Visit(Owner, SRel2.Get(S), Alt);
                        AddGraphEdge('edge' + MText.IntText(Counter), SId.Get(SRel1.Get(S)), SId.Get(SRel2.Get(S)), SValue.Get(S), false);
                        Counter += 1;
                    end;
            end;
    end;

    local procedure AddGraphEdge(Id: Text; StartId: Text; EndId: Text; LabelText: Text; Dashed: Boolean)
    begin
        EId.Add(Id);
        EStart.Add(StartId);
        EEnd.Add(EndId);
        ELabel.Add(LabelText);
        EDashed.Add(Dashed);
    end;

    local procedure Visit(Parent: Integer; Item: Integer; Alt: Boolean)
    var
        Id: Text;
        ClassStr: Text;
        StylesArr: Text;
        StyleCnt: Integer;
        K: Integer;
        Dr: Integer;
        Shape: Text;
        ItemMode: Integer;
        ItemArr: Text;
        ItemCnt: Integer;
        Arr: Text;
        Cnt: Integer;
        Part: Text;
        LabelText: Text;
        Rest: Text;
        RestCnt: Integer;
        I: Integer;
        HasParent: Boolean;
        ParentId: Text;
        NoteId: Text;
        NoteParent: Text;
        FromId: Text;
        ToId: Text;
    begin
        Id := SId.Get(Item);
        if Id = 'root' then
            exit;
        if KIndex.Get(Id, K) then begin
            ClassStr := KClasses.Get(K);
            StylesArr := KStyles.Get(K);
            StyleCnt := KStyleCnt.Get(K);
        end;

        if not DIndex.Get(Id, Dr) then begin
            Shape := 'rect';
            if SStart.Get(Item) = 1 then
                Shape := 'stateStart'
            else
                if SStart.Get(Item) = 2 then
                    Shape := 'stateEnd';
            if SType.Get(Item) <> 'default' then
                Shape := SType.Get(Item);
            DShape.Add(Shape);
            DDescrMode.Add(1);
            DDescr.Add(Id);
            DDescrCnt.Add(1);
            DCss.Add(ClassStr + ' statediagram-state');
            DStyles.Add(StylesArr);
            DStyleCnt.Add(StyleCnt);
            DType.Add('');
            DDir.Add('');
            Dr := DShape.Count();
            DIndex.Add(Id, Dr);
        end;

        ItemMode := SDescrMode.Get(Item);
        if (ItemMode = 2) or ((ItemMode = 1) and (SDescr.Get(Item) <> '')) then begin
            ItemArr := SDescr.Get(Item);
            ItemCnt := SDescrCnt.Get(Item);
            if DDescrMode.Get(Dr) = 2 then begin
                DShape.Set(Dr, 'rectWithTitle');
                Arr := DDescr.Get(Dr);
                Cnt := DDescrCnt.Get(Dr);
                if ItemCnt > 0 then
                    foreach Part in ItemArr.Split(Sep()) do
                        ArrAppend(Arr, Cnt, Part);
                DDescr.Set(Dr, Arr);
                DDescrCnt.Set(Dr, Cnt);
            end else
                if DDescr.Get(Dr) <> '' then begin
                    DShape.Set(Dr, 'rectWithTitle');
                    Arr := '';
                    Cnt := 0;
                    if DDescr.Get(Dr) <> Id then
                        ArrAppend(Arr, Cnt, DDescr.Get(Dr));
                    if ItemCnt > 0 then
                        foreach Part in ItemArr.Split(Sep()) do
                            ArrAppend(Arr, Cnt, Part);
                    DDescrMode.Set(Dr, 2);
                    DDescr.Set(Dr, Arr);
                    DDescrCnt.Set(Dr, Cnt);
                end else begin
                    DShape.Set(Dr, 'rect');
                    DDescrMode.Set(Dr, ItemMode);
                    DDescr.Set(Dr, ItemArr);
                    DDescrCnt.Set(Dr, ItemCnt);
                end;
        end;
        if (DDescrMode.Get(Dr) = 2) and (DDescrCnt.Get(Dr) = 1) and (DShape.Get(Dr) = 'rectWithTitle') then
            if DType.Get(Dr) = 'group' then
                DShape.Set(Dr, 'roundedWithTitle')
            else
                DShape.Set(Dr, 'rect');

        if (DType.Get(Dr) = '') and SHasDoc.Get(Item) then begin
            DType.Set(Dr, 'group');
            DDir.Set(Dr, DocDirection(Item));
            if SType.Get(Item) = 'divider' then
                DShape.Set(Dr, 'divider')
            else
                DShape.Set(Dr, 'roundedWithTitle');
            if Alt then
                DCss.Set(Dr, DCss.Get(Dr) + ' statediagram-cluster statediagram-cluster-alt')
            else
                DCss.Set(Dr, DCss.Get(Dr) + ' statediagram-cluster ');
        end;

        if DDescrMode.Get(Dr) = 2 then begin
            Arr := DDescr.Get(Dr);
            LabelText := ArrGet(Arr, 1);
            I := 0;
            if DDescrCnt.Get(Dr) > 1 then
                foreach Part in Arr.Split(Sep()) do begin
                    I += 1;
                    if I > 1 then
                        ArrAppend(Rest, RestCnt, Part);
                end;
        end else
            LabelText := DDescr.Get(Dr);
        if DShape.Get(Dr) = 'divider' then
            LabelText := '';
        if Parent <> 0 then
            if SId.Get(Parent) <> 'root' then begin
                HasParent := true;
                ParentId := SId.Get(Parent);
            end;

        if not SHasNote.Get(Item) then begin
            InsertNode(Id, DShape.Get(Dr), LabelText, Rest, RestCnt, DCss.Get(Dr), DStyles.Get(Dr), DStyleCnt.Get(Dr),
                       DType.Get(Dr) = 'group', HasParent, ParentId, DDir.Get(Dr), false, '', false, '');
            exit;
        end;
        // Mermaid puts each note in a group of its own, named after the state. Pele keeps that
        // group in the model and lays the note out beside its state instead.
        NoteId := Id + '----note-' + MText.IntText(Counter);
        Counter += 1;
        NoteParent := Id + '----parent';
        InsertNode(NoteParent, 'noteGroup', SNoteText.Get(Item), '', 0, DCss.Get(Dr), '', 0, true, false, '', '', true, SNotePos.Get(Item), false, '');
        InsertNode(NoteId, 'note', SNoteText.Get(Item), '', 0, 'statediagram-note', '', 0, false, true, NoteParent, '', true, SNotePos.Get(Item), true, Id);
        InsertNode(Id, DShape.Get(Dr), LabelText, Rest, RestCnt, DCss.Get(Dr), DStyles.Get(Dr), DStyleCnt.Get(Dr),
                   DType.Get(Dr) = 'group', HasParent, ParentId, DDir.Get(Dr), false, '', false, '');
        if SNotePos.Get(Item) = 'left of' then begin
            FromId := NoteId;
            ToId := Id;
        end else begin
            FromId := Id;
            ToId := NoteId;
        end;
        AddGraphEdge(FromId + '-' + ToId, FromId, ToId, '', true);
    end;

    local procedure InsertNode(Id: Text; Shape: Text; LabelText: Text; DescrArr: Text; DescrCnt: Integer; Css: Text; StylesArr: Text; StyleCnt: Integer;
                               IsGroup: Boolean; HasParent: Boolean; ParentId: Text; Dir: Text; IsAside: Boolean; Position: Text; HasNoteFor: Boolean; NoteFor: Text)
    var
        Compiled: Text;
        CompiledCnt: Integer;
        Name: Text;
        DefStyles: Text;
        G: Integer;
    begin
        // The two literal ids are what DOMPurify leaves of <<fork>> and <<choice>> in Mermaid; kept for parity.
        if (Id = '') or (Id = '</join></fork>') or (Id = '</choice>') then
            exit;
        if Css <> '' then
            foreach Name in Css.Split(' ') do
                if ClassStyles.Get(Name, DefStyles) then
                    if ClassStyleCnt.Get(Name) > 0 then begin
                        if CompiledCnt > 0 then
                            Compiled := Compiled + Sep() + DefStyles
                        else
                            Compiled := DefStyles;
                        CompiledCnt += ClassStyleCnt.Get(Name);
                    end;
        if not GIndex.Get(Id, G) then begin
            GId.Add(Id);
            GShape.Add('');
            GLabel.Add('');
            GDescr.Add('');
            GDescrCnt.Add(0);
            GCss.Add('');
            GCompiled.Add('');
            GCompiledCnt.Add(0);
            GStyles.Add('');
            GStyleCnt.Add(0);
            GIsGroup.Add(false);
            GHasParent.Add(false);
            GParentId.Add('');
            GDir.Add('');
            GPosition.Add('');
            GHasNoteFor.Add(false);
            GNoteFor.Add('');
            G := GId.Count();
            GIndex.Add(Id, G);
        end;
        GShape.Set(G, Shape);
        GLabel.Set(G, LabelText);
        GDescr.Set(G, DescrArr);
        GDescrCnt.Set(G, DescrCnt);
        GCss.Set(G, Css);
        GCompiled.Set(G, Compiled);
        GCompiledCnt.Set(G, CompiledCnt);
        GStyles.Set(G, StylesArr);
        GStyleCnt.Set(G, StyleCnt);
        GIsGroup.Set(G, IsGroup);
        GDir.Set(G, Dir);
        if HasParent then begin
            GHasParent.Set(G, true);
            GParentId.Set(G, ParentId);
        end;
        if IsAside then
            GPosition.Set(G, Position);
        if HasNoteFor then begin
            GHasNoteFor.Set(G, true);
            GNoteFor.Set(G, NoteFor);
        end;
    end;

    // ---------------------------------------------------------------- render

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

    local procedure Infinity(): Decimal
    begin
        exit(1000000000);
    end;

    local procedure Vertical(Dir: Text): Boolean
    begin
        exit((Dir = 'TB') or (Dir = 'BT'));
    end;

    local procedure Clamp(Value: Decimal; MinV: Decimal; MaxV: Decimal): Decimal
    begin
        if Value < MinV then
            exit(MinV);
        if Value > MaxV then
            exit(MaxV);
        exit(Value);
    end;

    local procedure AddView(G: Integer; Kind: Integer): Integer
    begin
        VNode.Add(G);
        VKind.Add(Kind);
        VShapeAttr.Add('');
        VLineAttr.Add('');
        VTextAttr.Add('');
        VTextStyle.Add(0);
        VLblRaw.Add('');
        VLblSize.Add(0);
        VLblWrap.Add(0);
        VLblW.Add(0);
        VLblH.Add(0);
        VW.Add(0);
        VH.Add(0);
        VTitleH.Add(0);
        CPar.Add(0);
        CIsGrp.Add(false);
        CDir.Add('');
        Logical.Add(0);
        Owners.Add(0);
        Appear.Add(Infinity());
        Degree.Add(0);
        OutCnt.Add(0);
        InCnt.Add(0);
        Noted.Add(false);
        LoopCount.Add(0);
        LoopWidth.Add(0);
        LoopHeight.Add(0);
        LoopSeen.Add(0);
        LoopText.Add(0);
        exit(VNode.Count());
    end;

    local procedure KindOf(G: Integer): Integer
    begin
        if GIsGroup.Get(G) then begin
            if GShape.Get(G) = 'divider' then
                exit(9);
            exit(8);
        end;
        case GShape.Get(G) of
            'rectWithTitle':
                exit(1);
            'stateStart':
                exit(2);
            'stateEnd':
                exit(3);
            'choice':
                exit(4);
            'fork':
                exit(5);
            'join':
                exit(6);
            'note':
                exit(7);
            'divider':
                exit(10);
        end;
        exit(0);
    end;

    local procedure SetViewLabel(V: Integer; Raw: Text; FontSize: Decimal; Wrap: Decimal; TextStyle: Integer)
    var
        Lbl: Codeunit "Mermaid Label";
    begin
        Lbl.Layout(Raw, true, FontSize, Wrap, TextStyle);
        VLblRaw.Set(V, Raw);
        VLblSize.Set(V, FontSize);
        VLblWrap.Set(V, Wrap);
        VTextStyle.Set(V, TextStyle);
        VLblW.Set(V, Lbl.GetWidth());
        VLblH.Set(V, Lbl.GetHeight());
    end;

    local procedure ViewLabel(V: Integer; var Lbl: Codeunit "Mermaid Label")
    begin
        Lbl.Layout(VLblRaw.Get(V), true, VLblSize.Get(V), VLblWrap.Get(V), VTextStyle.Get(V));
    end;

    /// <summary>As in Mermaid, a composite that sets no direction runs top to bottom whatever surrounds it.</summary>
    local procedure InnerDir(V: Integer): Text
    begin
        exit(Layout.DirectionOf(GDir.Get(VNode.Get(V))));
    end;

    /// <summary>Whether the flow around a state runs top to bottom or bottom to top.</summary>
    local procedure Across(V: Integer): Boolean
    begin
        if Logical.Get(V) = 0 then
            exit(Vertical(RootDir));
        exit(Vertical(InnerDir(Logical.Get(V))));
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Content: TextBuilder;
        Clusters: TextBuilder;
        NodesOut: TextBuilder;
        NotesOut: TextBuilder;
        EdgesOut: TextBuilder;
        LabelsOut: TextBuilder;
        RootItems: List of [Integer];
        Order: List of [Integer];
        Route: List of [Decimal];
        Width: Integer;
        Height: Integer;
        FullWidth: Integer;
        Shift: Decimal;
        Inner: Text;
        I: Integer;
        E: Integer;
        K: Integer;
        Q: Integer;
    begin
        Size := MText.FontSize();
        Small := Round(Size * 0.875, 1);
        WrapWidth := NumberOption(Config, 'state.wrappingWidth', 200);
        Pad := 8;
        RootDir := Layout.DirectionOf(DocDirection(0));
        Layout.Init(RootDir, NumberOption(Config, 'state.nodeSpacing', 40), 16, NumberOption(Config, 'state.rankSpacing', 44), Builder.MarkerTrim('arrow_point'));

        BuildViews();
        BuildEdges();
        BuildHiddenGroups();
        for I := 1 to VNode.Count() do
            if CPar.Get(I) <> 0 then
                Layout.SetParent(I, CPar.Get(I));
        SeqNo := 0;
        NumberLevel(0);
        Layout.Execute();

        Width := MText.Ceil(Layout.GetWidth() + 2 * Pad);
        Height := MText.Ceil(Layout.GetHeight() + 2 * Pad);

        // Route points by rounded y, to find the edges that cross a composite's title bar.
        for E := 1 to Layout.EdgeCount() do begin
            Layout.EdgeRoute(E, Route);
            K := 4;
            while K < Route.Count() - 3 do begin
                CrossX.Add(Route.Get(K));
                CrossY.Add(Round(Route.Get(K + 1), 1));
                K += 3;
            end;
        end;

        for I := 1 to VNode.Count() do
            if CPar.Get(I) = 0 then
                RootItems.Add(I);
        Order := CopyList(RootItems);
        Q := 1;
        while Q <= Order.Count() do begin
            foreach I in ChildrenOf(Order.Get(Q)) do
                Order.Add(I);
            Q += 1;
        end;

        Divide(RootItems, Pad / 2, Pad / 2, Width - Pad / 2, Height - Pad / 2);
        foreach I in Order do
            if (VNode.Get(I) <> 0) and (VKind.Get(I) < 9) then
                DrawNode(I, Clusters, NodesOut, NotesOut);
        DrawEdges(EdgesOut, LabelsOut);

        if Clusters.Length() > 0 then
            Content.Append('<g class="pele-clusters">' + Clusters.ToText() + '</g>');
        if Dividers.Length() > 0 then
            Content.Append('<g class="pele-dividers" stroke-dasharray="4 4" fill="none" stroke="var(--_b)">' + Dividers.ToText() + '</g>');
        if EdgesOut.Length() > 0 then
            Content.Append('<g class="pele-edges" fill="none" stroke="var(--_l)" stroke-linecap="round">' + EdgesOut.ToText() + '</g>');
        if LabelsOut.Length() > 0 then
            Content.Append('<g class="pele-edge-labels" font-size="' + MText.Num(Small) + '">' + LabelsOut.ToText() + '</g>');
        Content.Append('<g class="pele-nodes">' + NodesOut.ToText() + NotesOut.ToText() + '</g>');

        // Puts the diagram title above content that was laid out without one.
        Inner := Content.ToText();
        TitleLbl.Layout(DiagramTitle, false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then begin
            Shift := TitleLbl.GetHeight() + 12;
            FullWidth := Width;
            if MText.Ceil(TitleLbl.GetWidth() + 2 * Pad) > FullWidth then
                FullWidth := MText.Ceil(TitleLbl.GetWidth() + 2 * Pad);
            Inner := Builder.TitleSvg(TitleLbl, FullWidth / 2, Pad + TitleLbl.GetHeight() / 2) +
                     '<g transform="translate(' + Builder.P((FullWidth - Width) / 2, Shift) + ')">' + Inner + '</g>';
            Width := FullWidth;
            Height := MText.Ceil(Height + Shift);
        end;
        exit(Builder.Document('state', Width, Height, Size, AccTitle, AccDescr, Inner));
    end;

    local procedure CopyList(Source: List of [Integer]): List of [Integer]
    var
        Result: List of [Integer];
        I: Integer;
    begin
        foreach I in Source do
            Result.Add(I);
        exit(Result);
    end;

    local procedure ChildrenOf(Parent: Integer): List of [Integer]
    var
        Result: List of [Integer];
        I: Integer;
    begin
        for I := 1 to CPar.Count() do
            if CPar.Get(I) = Parent then
                Result.Add(I);
        exit(Result);
    end;

    // ---------------------------------------------------------------- views and sizes

    local procedure BuildViews()
    var
        Lbl: Codeunit "Mermaid Label";
        Styles: List of [Text];
        G: Integer;
        I: Integer;
        V: Integer;
        Owner: Integer;
        SrcV: Integer;
        DstV: Integer;
        Appeared: Integer;
        Kind: Integer;
        C: Integer;
        Line: Text;
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleSize: Decimal;
        FontSize: Decimal;
        TextStyle: Integer;
        W: Decimal;
        H: Decimal;
        Len: Decimal;
        Span: Decimal;
        TitleH: Decimal;
    begin
        for G := 1 to GId.Count() do
            if GShape.Get(G) <> 'noteGroup' then
                if not ViewIndex.ContainsKey(GId.Get(G)) then
                    ViewIndex.Add(GId.Get(G), AddView(G, KindOf(G)));
        StateCount := VNode.Count();

        for I := 1 to StateCount do begin
            G := VNode.Get(I);
            if GHasParent.Get(G) then
                if ViewIndex.Get(GParentId.Get(G), V) then
                    if V <> I then
                        if GIsGroup.Get(VNode.Get(V)) then
                            Logical.Set(I, V);
        end;
        BreakRings();
        for I := 1 to StateCount do begin
            G := VNode.Get(I);
            if GHasNoteFor.Get(G) then
                if ViewIndex.Get(GNoteFor.Get(G), Owner) then begin
                    Owners.Set(I, Owner);
                    Logical.Set(I, Logical.Get(Owner));
                end;
        end;

        // When each state first takes part in a transition. Layout follows this order rather than
        // the order of declaration, so a state declared up front does not become the top of the flow.
        for I := 1 to EId.Count() do
            if ViewIndex.Get(EStart.Get(I), SrcV) and ViewIndex.Get(EEnd.Get(I), DstV) then
                if EDashed.Get(I) then begin
                    if VKind.Get(SrcV) = 7 then
                        Noted.Set(DstV, true)
                    else
                        Noted.Set(SrcV, true);
                end else begin
                    OutCnt.Set(SrcV, OutCnt.Get(SrcV) + 1);
                    if OutCnt.Get(SrcV) > Degree.Get(SrcV) then
                        Degree.Set(SrcV, OutCnt.Get(SrcV));
                    InCnt.Set(DstV, InCnt.Get(DstV) + 1);
                    if InCnt.Get(DstV) > Degree.Get(DstV) then
                        Degree.Set(DstV, InCnt.Get(DstV));
                    if Appear.Get(SrcV) = Infinity() then begin
                        Appear.Set(SrcV, Appeared);
                        Appeared += 1;
                    end;
                    if Appear.Get(DstV) = Infinity() then begin
                        Appear.Set(DstV, Appeared);
                        Appeared += 1;
                    end;
                end;

        for I := 1 to StateCount do begin
            G := VNode.Get(I);
            Kind := VKind.Get(I);
            Clear(Styles);
            AddJoined(Styles, GCompiled.Get(G), GCompiledCnt.Get(G));
            AddJoined(Styles, GStyles.Get(G), GStyleCnt.Get(G));
            Builder.ResolveStyle(Styles, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
            TextStyle := 0;
            if IsBold then
                TextStyle += MText.StyleBold();
            if IsItalic then
                TextStyle += MText.StyleItalic();
            FontSize := Size;
            if StyleSize > 0 then
                FontSize := StyleSize;
            VShapeAttr.Set(I, ShapeAttr);
            VLineAttr.Set(I, LineAttr);
            VTextAttr.Set(I, TextAttr);
            VTextStyle.Set(I, TextStyle);
            W := 0;
            H := 0;
            case Kind of
                8:
                    begin
                        SetViewLabel(I, GLabel.Get(G), FontSize, 4000, TextStyle);
                        TitleH := 0;
                        if VLblH.Get(I) > 0 then
                            TitleH := VLblH.Get(I) + 12;
                        VTitleH.Set(I, TitleH);
                    end;
                2:
                    begin
                        W := 14;
                        H := 14;
                    end;
                3:
                    begin
                        W := 18;
                        H := 18;
                    end;
                4:
                    begin
                        W := 30;
                        H := 30;
                    end;
                5, 6:
                    begin
                        Len := Clamp(40 * Degree.Get(I) + 16, 72, 320);
                        if Across(I) then begin
                            W := Len;
                            H := 8;
                        end else begin
                            W := 8;
                            H := Len;
                        end;
                    end;
                9, 10:
                    ;
                7:
                    begin
                        SetViewLabel(I, GLabel.Get(G), Small, MText.MaxDec(WrapWidth, 320), 0);
                        W := VLblW.Get(I) + 24;
                        H := VLblH.Get(I) + 16;
                    end;
                else begin
                    SetViewLabel(I, GLabel.Get(G), FontSize, WrapWidth, TextStyle);
                    W := VLblW.Get(I);
                    H := VLblH.Get(I) + 2 * 10;
                    if Kind = 1 then begin
                        H += 14;
                        for C := 1 to GDescrCnt.Get(G) do begin
                            Line := ArrGet(GDescr.Get(G), C);
                            if Line = '' then
                                Line := ' ';
                            Lbl.Layout(Line, true, Small, WrapWidth, TextStyle);
                            if Lbl.GetWidth() > W then
                                W := Lbl.GetWidth();
                            H += Lbl.GetHeight();
                        end;
                    end;
                    W := MText.MaxDec(W + 2 * 16, 56);
                end;
            end;
            VW.Set(I, W);
            VH.Set(I, H);
            // The transitions on one side of a state's box spread along it, clear of its corners.
            Span := 0;
            if Kind in [0, 1] then
                if Across(I) then
                    Span := W - 24
                else
                    Span := H - 24;
            Layout.AddNode(W, H, Span);
            if Kind = 8 then begin
                Layout.SetGroup(I, 16, TitleH + 16, 16, VLblW.Get(I) + 2 * 16, InnerDir(I));
                CIsGrp.Set(I, true);
                CDir.Set(I, InnerDir(I));
            end;
            if Kind = 9 then begin
                Layout.SetGroup(I, 10, 10, 10, 0, InnerDir(I));
                CIsGrp.Set(I, true);
                CDir.Set(I, InnerDir(I));
            end;
        end;
    end;

    /// <summary>Composites that are redeclared inside each other form a ring with no way in from the root. One member of each ring moves to the root.</summary>
    local procedure BreakRings()
    var
        Placed: List of [Boolean];
        Queue: List of [Integer];
        Seen: List of [Integer];
        I: Integer;
        Ring: Integer;
        Done: Integer;
    begin
        for I := 1 to StateCount do begin
            Placed.Add(Logical.Get(I) = 0);
            Seen.Add(0);
            if Logical.Get(I) = 0 then
                Queue.Add(I);
        end;
        Done := 1;
        Settle(Placed, Queue, Done);
        for I := 1 to StateCount do
            if not Placed.Get(I) then begin
                Ring := I;
                while Seen.Get(Ring) <> I do begin
                    Seen.Set(Ring, I);
                    Ring := Logical.Get(Ring);
                end;
                Logical.Set(Ring, 0);
                Placed.Set(Ring, true);
                Queue.Add(Ring);
                Settle(Placed, Queue, Done);
            end;
    end;

    local procedure Settle(var Placed: List of [Boolean]; var Queue: List of [Integer]; var Done: Integer)
    var
        Kid: Integer;
        Q: Integer;
    begin
        while Done <= Queue.Count() do begin
            Q := Queue.Get(Done);
            for Kid := 1 to StateCount do
                if Logical.Get(Kid) = Q then
                    if not Placed.Get(Kid) then begin
                        Placed.Set(Kid, true);
                        Queue.Add(Kid);
                    end;
            Done += 1;
        end;
    end;

    local procedure Encloses(Composite: Integer; Item: Integer): Boolean
    var
        Par: Integer;
        Hops: Integer;
    begin
        if not CIsGrp.Get(Composite) then
            exit(false);
        Par := Logical.Get(Item);
        while (Par <> 0) and (Hops <= StateCount) do begin
            if Par = Composite then
                exit(true);
            Par := Logical.Get(Par);
            Hops += 1;
        end;
        exit(false);
    end;

    /// <summary>A point just inside a composite, where a transition between it and a state inside it runs to.</summary>
    local procedure AddAnchor(Composite: Integer; First: Boolean): Integer
    var
        V: Integer;
    begin
        V := AddView(0, 10);
        if First then
            Appear.Set(V, -1);
        Layout.AddNode(0, 0, 0);
        CPar.Set(V, Composite);
        exit(V);
    end;

    local procedure BuildEdges()
    var
        Lbl: Codeunit "Mermaid Label";
        Ge: Integer;
        SrcV: Integer;
        DstV: Integer;
        Anchor: Integer;
        E: Integer;
        LabelW: Decimal;
        LabelH: Decimal;
    begin
        for Ge := 1 to EId.Count() do
            if ViewIndex.Get(EStart.Get(Ge), SrcV) and ViewIndex.Get(EEnd.Get(Ge), DstV) then begin
                Lbl.Layout(ELabel.Get(Ge), true, Small, WrapWidth, 0);
                LabelW := 0;
                LabelH := 0;
                if Lbl.GetWidth() > 0 then
                    LabelW := Lbl.GetWidth() + 12;
                if Lbl.GetHeight() > 0 then
                    LabelH := Lbl.GetHeight() + 4;
                Anchor := 0;
                if SrcV = DstV then begin
                    LoopCount.Set(SrcV, LoopCount.Get(SrcV) + 1);
                    LoopWidth.Set(SrcV, MText.MaxDec(LoopWidth.Get(SrcV), LabelW));
                    LoopHeight.Set(SrcV, LoopHeight.Get(SrcV) + Lbl.GetHeight());
                end else
                    if Encloses(SrcV, DstV) then begin
                        Anchor := SrcV;
                        SrcV := AddAnchor(SrcV, true);
                    end else
                        if Encloses(DstV, SrcV) then begin
                            Anchor := DstV;
                            DstV := AddAnchor(DstV, false);
                        end;
                E := Layout.AddEdge(SrcV, DstV, 1, LabelW, LabelH);
                DGEdge.Add(Ge);
                DSrc.Add(SrcV);
                DDst.Add(DstV);
                DLabelW.Add(LabelW);
                if Anchor <> 0 then
                    Anchors.Add(E, Anchor);
            end;
    end;

    /// <summary>
    /// A state with notes, or a composite with self-transitions, sits in an unseen group of its own: the notes go
    /// beside the state, across the flow, without disturbing its transitions.
    /// </summary>
    local procedure BuildHiddenGroups()
    var
        I: Integer;
        V: Integer;
        Room: Decimal;
        Reach: Decimal;
    begin
        for I := 1 to StateCount do
            if Owners.Get(I) = 0 then begin
                // Loops hang off the right, or below when the flow is horizontal, with their labels beyond them.
                Room := 0;
                if LoopCount.Get(I) > 0 then begin
                    Reach := 26 + (LoopCount.Get(I) - 1) * 8;
                    if Across(I) then
                        Room := Reach + LoopWidth.Get(I)
                    else
                        Room := Reach * 0.75 + 4 + LoopHeight.Get(I);
                    if not CIsGrp.Get(I) then begin
                        if Across(I) then
                            Layout.SetSize(I, Layout.NodeW(I) + 2 * Room, MText.MaxDec(Layout.NodeH(I), LoopHeight.Get(I)))
                        else
                            Layout.SetSize(I, MText.MaxDec(Layout.NodeW(I), LoopWidth.Get(I)), Layout.NodeH(I) + 2 * Room);
                        Room := 0;
                    end;
                end;
                if (not Noted.Get(I)) and (Room = 0) then
                    CPar.Set(I, Logical.Get(I))
                else begin
                    V := AddView(0, 10);
                    Appear.Set(V, Appear.Get(I));
                    Layout.AddNode(0, 0, 0);
                    if Across(I) then begin
                        Layout.SetGroup(V, Room, 0, 0, 0, 'LR');
                        CDir.Set(V, 'LR');
                    end else begin
                        Layout.SetGroup(V, 0, Room, Room, 0, 'TB');
                        CDir.Set(V, 'TB');
                    end;
                    CIsGrp.Set(V, true);
                    CPar.Set(V, Logical.Get(I));
                    CPar.Set(I, V);
                end;
            end;
        for I := 1 to StateCount do
            if Owners.Get(I) <> 0 then
                CPar.Set(I, CPar.Get(Owners.Get(I)));
    end;

    local procedure FlowsBefore(A: Integer; B: Integer): Boolean
    var
        Ia: Integer;
        Ib: Integer;
    begin
        Ia := 1;
        if VKind.Get(A) = 2 then
            Ia := 0;
        Ib := 1;
        if VKind.Get(B) = 2 then
            Ib := 0;
        if Ia <> Ib then
            exit(Ia < Ib);
        if Appear.Get(A) <> Appear.Get(B) then
            exit(Appear.Get(A) < Appear.Get(B));
        exit(A < B);
    end;

    /// <summary>Numbers the tree so that, at every level, initial states come first and the rest follow in the order the transitions introduce them.</summary>
    local procedure NumberLevel(Parent: Integer)
    var
        Items: List of [Integer];
        I: Integer;
        J: Integer;
        Item: Integer;
        Moving: Boolean;
    begin
        Items := ChildrenOf(Parent);
        for I := 2 to Items.Count() do begin
            Item := Items.Get(I);
            J := I - 1;
            Moving := true;
            while Moving do
                if J < 1 then
                    Moving := false
                else
                    if FlowsBefore(Item, Items.Get(J)) then begin
                        Items.Set(J + 1, Items.Get(J));
                        J -= 1;
                    end else
                        Moving := false;
            Items.Set(J + 1, Item);
        end;
        foreach Item in Items do begin
            SeqNo += 1;
            Layout.SetSeq(Item, SeqNo);
            if CIsGrp.Get(Item) then
                NumberLevel(Item);
        end;
    end;

    // ---------------------------------------------------------------- drawing

    local procedure Rect(X: Decimal; Y: Decimal; W: Decimal; H: Decimal; Rest: Text): Text
    begin
        exit('<rect x="' + MText.Num(X) + '" y="' + MText.Num(Y) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) + '"' + Rest + '/>');
    end;

    local procedure Lo(I: Integer; AlongX: Boolean): Decimal
    begin
        if AlongX then
            exit(Layout.NodeX(I) - Layout.NodeW(I) / 2);
        exit(Layout.NodeY(I) - Layout.NodeH(I) / 2);
    end;

    local procedure Hi(I: Integer; AlongX: Boolean): Decimal
    begin
        if AlongX then
            exit(Layout.NodeX(I) + Layout.NodeW(I) / 2);
        exit(Layout.NodeY(I) + Layout.NodeH(I) / 2);
    end;

    /// <summary>Draws the dashed lines between the regions among a composite's members.</summary>
    local procedure Divide(Items: List of [Integer]; Left: Decimal; Top: Decimal; Right: Decimal; Bottom: Decimal)
    var
        Regions: List of [Integer];
        Sorted: List of [Integer];
        I: Integer;
        J: Integer;
        K: Integer;
        Item: Integer;
        Pass: Integer;
        AlongX: Boolean;
        Apart: Boolean;
        Moving: Boolean;
        At: Text;
    begin
        foreach I in Items do
            if VKind.Get(I) = 9 then
                Regions.Add(I);
        if Regions.Count() < 2 then
            exit;
        for Pass := 1 to 2 do begin
            AlongX := Pass = 1;
            Sorted := CopyList(Regions);
            for I := 2 to Sorted.Count() do begin
                Item := Sorted.Get(I);
                J := I - 1;
                Moving := true;
                while Moving do
                    if J < 1 then
                        Moving := false
                    else
                        if (Lo(Sorted.Get(J), AlongX) > Lo(Item, AlongX)) or ((Lo(Sorted.Get(J), AlongX) = Lo(Item, AlongX)) and (Sorted.Get(J) > Item)) then begin
                            Sorted.Set(J + 1, Sorted.Get(J));
                            J -= 1;
                        end else
                            Moving := false;
                Sorted.Set(J + 1, Item);
            end;
            Apart := true;
            for K := 2 to Sorted.Count() do
                if Hi(Sorted.Get(K - 1), AlongX) > Lo(Sorted.Get(K), AlongX) + 0.5 then
                    Apart := false;
            if Apart then begin
                for K := 2 to Sorted.Count() do begin
                    At := MText.Num((Hi(Sorted.Get(K - 1), AlongX) + Lo(Sorted.Get(K), AlongX)) / 2 + Pad);
                    if AlongX then
                        Dividers.Append('<path class="pele-divider" d="M' + At + ',' + MText.Num(Top) + 'V' + MText.Num(Bottom) + '"/>')
                    else
                        Dividers.Append('<path class="pele-divider" d="M' + MText.Num(Left) + ',' + At + 'H' + MText.Num(Right) + '"/>');
                end;
                exit;
            end;
        end;
        // Regions that sit neither side by side nor in a stack each get an outline.
        foreach I in Regions do
            Dividers.Append(Rect(Layout.NodeX(I) - Layout.NodeW(I) / 2 + Pad, Layout.NodeY(I) - Layout.NodeH(I) / 2 + Pad, Layout.NodeW(I), Layout.NodeH(I), ' class="pele-divider" rx="10"'));
    end;

    /// <summary>Picks where a composite's title sits in its title bar so that edges entering from above do not cross it.</summary>
    local procedure TitleX(I: Integer; TitleWidth: Decimal): Decimal
    var
        Xs: List of [Decimal];
        Candidates: List of [Decimal];
        K: Integer;
        Top: Decimal;
        Left: Decimal;
        W: Decimal;
        Half: Decimal;
        Candidate: Decimal;
        Gap: Decimal;
        Best: Decimal;
        BestGap: Decimal;
        Cx: Decimal;
    begin
        if TitleWidth = 0 then
            exit(Layout.NodeX(I));
        Top := Round(Layout.NodeY(I) - Layout.NodeH(I) / 2, 1);
        for K := 1 to CrossY.Count() do
            if CrossY.Get(K) = Top then
                Xs.Add(CrossX.Get(K));
        if Xs.Count() = 0 then
            exit(Layout.NodeX(I));
        W := Layout.NodeW(I);
        Left := Layout.NodeX(I) - W / 2;
        Half := TitleWidth / 2;
        Candidates.Add(Layout.NodeX(I));
        Candidates.Add(Left + 16 + Half);
        Candidates.Add(Left + W - 16 - Half);
        Best := Layout.NodeX(I);
        BestGap := -1;
        foreach Candidate in Candidates do begin
            Gap := Infinity();
            foreach Cx in Xs do
                if (Cx > Left) and (Cx < Left + W) then
                    Gap := MText.MinDec(Gap, Abs(Cx - Candidate) - Half);
            if Gap >= 6 then
                exit(Candidate);
            if Gap > BestGap + 0.5 then begin
                BestGap := Gap;
                Best := Candidate;
            end;
        end;
        exit(Best);
    end;

    local procedure StripMermaidClasses(Css: Text): Text
    var
        Result: Text;
        Part: Text;
    begin
        foreach Part in Css.Split(' ') do
            if not (Part in ['statediagram-state', 'statediagram-cluster-alt', 'statediagram-cluster', 'statediagram-note']) then
                Result += ' ' + Part;
        exit(Result);
    end;

    local procedure KindClass(Kind: Integer): Text
    begin
        case Kind of
            0, 1:
                exit('pele-node pele-state');
            2:
                exit('pele-node pele-state-start');
            3:
                exit('pele-node pele-state-end');
            4:
                exit('pele-node pele-state-choice');
            5:
                exit('pele-node pele-state-fork');
            6:
                exit('pele-node pele-state-join');
            7:
                exit('pele-note');
            8:
                exit('pele-cluster pele-state-composite');
        end;
        exit('');
    end;

    /// <summary>Mermaid keeps the quotes of a click statement's strings and strips them when it draws.</summary>
    local procedure Unquote(Value: Text): Text
    var
        FromPos: Integer;
        ToPos: Integer;
    begin
        FromPos := 1;
        ToPos := StrLen(Value);
        while (FromPos <= ToPos) and (MText.CharAt(Value, FromPos) = 34) do
            FromPos += 1;
        while (ToPos >= FromPos) and (MText.CharAt(Value, ToPos) = 34) do
            ToPos -= 1;
        exit(MText.Substr(Value, FromPos, ToPos + 1));
    end;

    /// <summary>A click target, kept only when it is relative or its scheme is http, https, mailto or tel; otherwise empty.</summary>
    local procedure SafeUrl(Url: Text): Text
    var
        Cleaned: TextBuilder;
        Value: Text;
        Scheme: Text;
        I: Integer;
        C: Integer;
    begin
        Value := MText.DecodeEntities(Url);
        for I := 1 to StrLen(Value) do begin
            C := Value[I];
            if not ((C < 32) or ((C >= 127) and (C <= 159)) or (C = 8203) or (C = 8204) or (C = 8205) or (C = 65279)) then
                Cleaned.Append(CopyStr(Value, I, 1));
        end;
        Value := MText.TrimWs(Cleaned.ToText());
        if Value = '' then
            exit('');
        if (MText.CharAt(Value, 1) in [47, 92]) and (MText.CharAt(Value, 2) in [47, 92]) then
            exit('');
        if MText.CharAt(Value, 1) in [46, 47] then
            exit(Value);
        if not MText.IsLetter(MText.CharAt(Value, 1)) then
            exit(Value);
        I := 2;
        while MText.IsLetter(MText.CharAt(Value, I)) or MText.IsDigit(MText.CharAt(Value, I)) or (MText.CharAt(Value, I) in [43, 46, 45]) do
            I += 1;
        if MText.CharAt(Value, I) <> 58 then
            exit(Value);
        Scheme := LowerCase(CopyStr(Value, 1, I - 1));
        if Scheme in ['http', 'https', 'mailto', 'tel'] then
            exit(Value);
        exit('');
    end;

    local procedure DrawNode(I: Integer; var Clusters: TextBuilder; var NodesOut: TextBuilder; var NotesOut: TextBuilder)
    var
        Lbl: Codeunit "Mermaid Label";
        LineLbl: Codeunit "Mermaid Label";
        G: Integer;
        Kind: Integer;
        C: Integer;
        X: Decimal;
        Y: Decimal;
        W: Decimal;
        H: Decimal;
        Cw: Decimal;
        Ch: Decimal;
        Left: Decimal;
        Top: Decimal;
        At: Decimal;
        TitleH: Decimal;
        Shape: Text;
        LineA: Text;
        TextA: Text;
        LabelAttrs: Text;
        Body: Text;
        R: Text;
        B: Text;
        Fold: Text;
        Corner: Text;
        Line: Text;
        Url: Text;
        Tip: Text;
        Href: Text;
        Open: Text;
    begin
        G := VNode.Get(I);
        Kind := VKind.Get(I);
        X := Layout.NodeX(I) + Pad;
        Y := Layout.NodeY(I) + Pad;
        W := VW.Get(I);
        H := VH.Get(I);
        Shape := VShapeAttr.Get(I);
        LineA := VLineAttr.Get(I);
        TextA := VTextAttr.Get(I);
        LabelAttrs := ' class="pele-label"' + TextA;
        case Kind of
            8:
                begin
                    Cw := Layout.NodeW(I);
                    Ch := Layout.NodeH(I);
                    Left := X - Cw / 2;
                    Top := Y - Ch / 2;
                    TitleH := VTitleH.Get(I);
                    Body := Rect(Left, Top, Cw, Ch, ' rx="10" fill="var(--_a)" fill-opacity="0.5" stroke="var(--_b)"' + Shape);
                    if TitleH > 0 then begin
                        ViewLabel(I, Lbl);
                        Body += '<path d="M' + MText.Num(Left) + ',' + MText.Num(Top + TitleH) + 'H' + MText.Num(Left + Cw) + '" fill="none" stroke="var(--_b)"' + LineA + '/>' +
                                Lbl.ToSvg(TitleX(I, Lbl.GetWidth()) + Pad, Top + TitleH / 2, ' class="pele-cluster-label"' + TextA);
                    end;
                    Divide(ChildrenOf(I), Left, Top + TitleH, Left + Cw, Top + Ch);
                end;
            2:
                Body := '<circle r="7" fill="var(--_l)"' + Shape + '/>';
            3:
                Body := '<circle r="8.5" fill="var(--_bg)" stroke="var(--_l)"' + LineA + '/><circle r="5" fill="var(--_l)"' + Shape + '/>';
            4:
                Body := '<polygon points="0,' + MText.Num(-H / 2) + ' ' + MText.Num(W / 2) + ',0 0,' + MText.Num(H / 2) + ' ' + MText.Num(-W / 2) + ',0" fill="var(--_s)" stroke="var(--_b)"' + Shape + '/>';
            5, 6:
                Body := Rect(-W / 2, -H / 2, W, H, ' rx="2" fill="var(--_l)"' + Shape);
            7:
                begin
                    R := MText.Num(W / 2);
                    B := MText.Num(H / 2);
                    Fold := MText.Num(W / 2 - 8);
                    Corner := MText.Num(8 - H / 2);
                    ViewLabel(I, Lbl);
                    Body := '<path d="M-' + R + ',-' + B + 'H' + Fold + 'L' + R + ',' + Corner + 'V' + B + 'H-' + R + 'Z" fill="var(--_bg)" stroke="var(--_b)"/>' +
                            '<path d="M' + Fold + ',-' + B + 'V' + Corner + 'H' + R + '" fill="none" stroke="var(--_b)"/>' +
                            Lbl.ToSvg(0, 0, ' class="pele-label" font-size="' + MText.Num(Small) + '" fill="var(--_m)"');
                end;
            else begin
                Body := Rect(-W / 2, -H / 2, W, H, ' rx="' + MText.Num(MText.MinDec(10, H / 2)) + '" fill="var(--_s)" stroke="var(--_b)"' + Shape);
                ViewLabel(I, Lbl);
                if Kind = 0 then
                    Body += Lbl.ToSvg(0, 0, LabelAttrs)
                else begin
                    At := 10 - H / 2 + Lbl.GetHeight();
                    Body += '<path d="M' + MText.Num(-W / 2) + ',' + MText.Num(At + 6) + 'H' + MText.Num(W / 2) + '" fill="none" stroke="var(--_b)"' + LineA + '/>' +
                            Lbl.ToSvg(0, At - Lbl.GetHeight() / 2, LabelAttrs);
                    At += 14;
                    for C := 1 to GDescrCnt.Get(G) do begin
                        Line := ArrGet(GDescr.Get(G), C);
                        if Line = '' then
                            Line := ' ';
                        LineLbl.Layout(Line, true, Small, WrapWidth, VTextStyle.Get(I));
                        Body += LineLbl.ToSvg(0, At + LineLbl.GetHeight() / 2, ' class="pele-state-description" font-size="' + MText.Num(Small) + '"' + TextA);
                        At += LineLbl.GetHeight();
                    end;
                end;
            end;
        end;

        if LinkUrl.Get(GId.Get(G), Url) then begin
            // Entity codes are resolved first, so the URL is checked in the form a browser would follow.
            Tip := MText.DecodeEntities(Unquote(LinkTip.Get(GId.Get(G))));
            if Tip <> '' then
                Body := '<title>' + MText.Esc(Tip) + '</title>' + Body;
            Href := SafeUrl(Unquote(Url));
            if Href <> '' then
                Body := '<a href="' + MText.Esc(Href) + '" target="_blank" rel="noopener">' + Body + '</a>';
        end;
        Open := '<g class="' + KindClass(Kind) + Builder.ClassNames(StripMermaidClasses(GCss.Get(G))) + '" data-id="' + MText.EscText(GId.Get(G)) + '"';
        case Kind of
            8:
                Clusters.Append(Open + '>' + Body + '</g>');
            7:
                NotesOut.Append(Open + ' transform="translate(' + Builder.P(X, Y) + ')">' + Body + '</g>');
            else
                NodesOut.Append(Open + ' transform="translate(' + Builder.P(X, Y) + ')">' + Body + '</g>');
        end;
    end;

    /// <summary>Moves a route end from the layout box onto the drawn shape, and spreads the ends along a bar.</summary>
    local procedure Attach(var Route: List of [Decimal]; At: Integer; I: Integer)
    var
        Bar: Boolean;
        Other: Integer;
        Step: Integer;
        Axis: Integer;
        Extent: Decimal;
        DrawnExtent: Decimal;
        Breadth: Decimal;
        Center: Decimal;
        Cross: Decimal;
        Delta: Decimal;
    begin
        if CIsGrp.Get(I) then
            exit;
        Bar := VKind.Get(I) in [5, 6];
        if At = 1 then
            Other := 4
        else
            Other := At - 3;
        // Axis 0 is x and 1 is y; the end sits on a side that faces along it.
        for Step := 1 to 2 do begin
            Axis := 2 - Step;
            if Axis = 1 then begin
                Extent := Layout.NodeH(I);
                DrawnExtent := VH.Get(I);
                Breadth := VW.Get(I);
                Center := Layout.NodeY(I) + Pad;
                Cross := Layout.NodeX(I) + Pad;
            end else begin
                Extent := Layout.NodeW(I);
                DrawnExtent := VW.Get(I);
                Breadth := VH.Get(I);
                Center := Layout.NodeX(I) + Pad;
                Cross := Layout.NodeY(I) + Pad;
            end;
            Delta := Route.Get(At + Axis) - Center;
            if Abs(Abs(Delta) - Extent / 2) < 0.5 then begin
                Route.Set(At + Axis, Route.Get(At + Axis) - MText.Sign(Delta) * (Extent - DrawnExtent) / 2);
                if Bar and (Breadth > DrawnExtent) then
                    Route.Set(At + 1 - Axis, Clamp(Route.Get(Other + 1 - Axis), Cross - Breadth / 2 + 6, Cross + Breadth / 2 - 6));
                exit;
            end;
        end;
    end;

    local procedure LoopX(Ax: Decimal; Side: Boolean; OutV: Decimal; Dx: Decimal; Dy: Decimal): Decimal
    begin
        if Side then
            exit(Ax + OutV + Dx);
        exit(Ax - Dy);
    end;

    local procedure LoopY(Ay: Decimal; Side: Boolean; OutV: Decimal; Dx: Decimal; Dy: Decimal): Decimal
    begin
        if Side then
            exit(Ay + Dy);
        exit(Ay + OutV + Dx);
    end;

    local procedure LoopPt(Ax: Decimal; Ay: Decimal; Side: Boolean; OutV: Decimal; Dx: Decimal; Dy: Decimal): Text
    begin
        exit(Builder.P(LoopX(Ax, Side, OutV, Dx, Dy), LoopY(Ay, Side, OutV, Dx, Dy)));
    end;

    local procedure DrawEdges(var EdgesOut: TextBuilder; var LabelsOut: TextBuilder)
    var
        Lbl: Codeunit "Mermaid Label";
        Route: List of [Decimal];
        E: Integer;
        Ge: Integer;
        SrcV: Integer;
        DstV: Integer;
        K: Integer;
        At: Integer;
        Comp: Integer;
        IsNote: Boolean;
        Side: Boolean;
        Inward: Boolean;
        Near: Boolean;
        EndType: Text;
        D: Text;
        GroupDir: Text;
        Sx: Decimal;
        Sy: Decimal;
        Sdx: Decimal;
        Sdy: Decimal;
        Ex: Decimal;
        Ey: Decimal;
        Edx: Decimal;
        Edy: Decimal;
        Ax: Decimal;
        Ay: Decimal;
        Wl: Decimal;
        Hl: Decimal;
        OutV: Decimal;
        Spread: Decimal;
        Reach: Decimal;
        Trim: Decimal;
        Len: Decimal;
        Furthest: Decimal;
        Below: Decimal;
        LabelX: Decimal;
        LabelY: Decimal;
        Px: Decimal;
        Py: Decimal;
        PAxis: Decimal;
    begin
        for E := 1 to DGEdge.Count() do begin
            Ge := DGEdge.Get(E);
            SrcV := DSrc.Get(E);
            DstV := DDst.Get(E);
            IsNote := EDashed.Get(Ge);
            EndType := 'arrow_point';
            if IsNote then
                EndType := 'none';
            Lbl.Layout(ELabel.Get(Ge), true, Small, WrapWidth, 0);
            D := '';
            if SrcV = DstV then begin
                K := LoopSeen.Get(SrcV);
                LoopSeen.Set(SrcV, K + 1);
                // The loop hangs off a side the flow does not use: the right, or below when the flow is horizontal.
                Side := Across(SrcV);
                if CIsGrp.Get(SrcV) then begin
                    Wl := Layout.NodeW(SrcV);
                    Hl := Layout.NodeH(SrcV);
                end else begin
                    Wl := VW.Get(SrcV);
                    Hl := VH.Get(SrcV);
                end;
                if Side then begin
                    OutV := Wl / 2;
                    Spread := MText.MaxDec(MText.MinDec(Hl / 2 - 4, 8 + K * 6), 2);
                end else begin
                    OutV := Hl / 2;
                    Spread := MText.MaxDec(MText.MinDec(Wl / 2 - 4, 8 + K * 6), 2);
                end;
                Reach := 26 + K * 8;
                Len := MText.Hypot(Reach, Spread);
                if Len = 0 then
                    Len := 1;
                Trim := Builder.MarkerTrim(EndType) / Len;
                Ax := Layout.NodeX(SrcV) + Pad;
                Ay := Layout.NodeY(SrcV) + Pad;
                D := 'M' + LoopPt(Ax, Ay, Side, OutV, 0, -Spread) + 'C' + LoopPt(Ax, Ay, Side, OutV, Reach, -2 * Spread) + ' ' +
                     LoopPt(Ax, Ay, Side, OutV, Reach, 2 * Spread) + ' ' + LoopPt(Ax, Ay, Side, OutV, Reach * Trim, Spread + Spread * Trim);
                Ex := LoopX(Ax, Side, OutV, 0, Spread);
                Ey := LoopY(Ay, Side, OutV, 0, Spread);
                Edx := LoopX(Ax, Side, OutV, -Reach, -Spread) - LoopX(Ax, Side, OutV, 0, 0);
                Edy := LoopY(Ay, Side, OutV, -Reach, -Spread) - LoopY(Ay, Side, OutV, 0, 0);
                Len := MText.Hypot(Edx, Edy);
                if Len = 0 then
                    Len := 1;
                Edx := Edx / Len;
                Edy := Edy / Len;
                // Labels stack beyond the outermost loop, in the order of their transitions.
                Furthest := 26 + (LoopCount.Get(SrcV) - 1) * 8;
                Below := LoopText.Get(SrcV) + Lbl.GetHeight() / 2;
                LoopText.Set(SrcV, LoopText.Get(SrcV) + Lbl.GetHeight());
                if Side then begin
                    LabelX := Layout.NodeX(SrcV) + OutV + Furthest + 4 + DLabelW.Get(E) / 2;
                    LabelY := Layout.NodeY(SrcV) - LoopHeight.Get(SrcV) / 2 + Below;
                end else begin
                    LabelX := Layout.NodeX(SrcV);
                    LabelY := Layout.NodeY(SrcV) + OutV + Furthest * 0.75 + 4 + Below;
                end;
            end else begin
                Layout.EdgeRoute(E, Route);
                LabelX := Layout.EdgeLabelX(E);
                LabelY := Layout.EdgeLabelY(E);
                if Route.Count() >= 6 then begin
                    K := 1;
                    while K < Route.Count() do begin
                        Route.Set(K, Route.Get(K) + Pad);
                        Route.Set(K + 1, Route.Get(K + 1) + Pad);
                        K += 3;
                    end;
                    Attach(Route, 1, SrcV);
                    Attach(Route, Route.Count() - 2, DstV);
                    if Anchors.Get(E, Comp) then begin
                        Inward := VKind.Get(SrcV) = 10;
                        if Inward then
                            At := 1
                        else
                            At := Route.Count() - 2;
                        GroupDir := CDir.Get(Comp);
                        Near := ((GroupDir = 'TB') or (GroupDir = 'LR')) = Inward;
                        if Vertical(GroupDir) then begin
                            Px := Route.Get(At);
                            if Near then
                                Py := Layout.NodeY(Comp) + Pad + VTitleH.Get(Comp) - Layout.NodeH(Comp) / 2
                            else
                                Py := Layout.NodeY(Comp) + Pad + Layout.NodeH(Comp) / 2;
                            PAxis := 0;
                        end else begin
                            if Near then
                                Px := Layout.NodeX(Comp) + Pad - Layout.NodeW(Comp) / 2
                            else
                                Px := Layout.NodeX(Comp) + Pad + Layout.NodeW(Comp) / 2;
                            Py := Route.Get(At + 1);
                            PAxis := 1;
                        end;
                        if Inward then begin
                            Route.Insert(1, PAxis);
                            Route.Insert(1, Py);
                            Route.Insert(1, Px);
                        end else begin
                            Route.Add(Px);
                            Route.Add(Py);
                            Route.Add(PAxis);
                        end;
                    end;
                    Builder.RoutePath(Route, '', 0, Builder.MarkerTrim(EndType), D, Sx, Sy, Sdx, Sdy, Ex, Ey, Edx, Edy);
                end;
            end;
            if D <> '' then begin
                if IsNote then
                    EdgesOut.Append('<g class="pele-edge pele-note-edge" stroke="var(--_b)" stroke-dasharray="3 4" data-id="' + MText.EscText(EId.Get(Ge)) + '">')
                else
                    EdgesOut.Append('<g class="pele-edge pele-transition" data-id="' + MText.EscText(EId.Get(Ge)) + '">');
                EdgesOut.Append('<path d="' + D + '"/>' + Builder.Marker(EndType, Ex, Ey, Edx, Edy, 'var(--_l)') + '</g>');
            end;
            if Lbl.GetWidth() > 0 then
                LabelsOut.Append(Builder.EdgeLabelSvg(EId.Get(Ge), Lbl, LabelX + Pad, LabelY + Pad, ''));
        end;
    end;
}
