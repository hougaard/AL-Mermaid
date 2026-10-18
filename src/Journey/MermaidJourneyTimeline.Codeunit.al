/// <summary>
/// Port of pele's diagrams/journey and diagrams/timeline (lexer.ts, parser.ts, db.ts and render.ts of each),
/// with the shared lexer rules of diagrams/common/scan.ts and the label fitting of diagrams/common/fit.ts.
/// One instance holds one parsed diagram of either type. Pele's narrowing to a host width (turnToFit) is left out.
/// </summary>
codeunit 68919 "Mermaid Journey Timeline"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Src: Text;
        TokTypes: List of [Integer];
        TokTexts: List of [Text];
        TokStarts: List of [Integer];
        DiagramTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        Sections: List of [Text];
        CurrentSection: Text;
        // journey: one entry per task; the people of all tasks in one list.
        TaskNames: List of [Text];
        TaskScores: List of [Decimal];
        TaskNaN: List of [Boolean];
        TaskSections: List of [Text];
        TaskPeopleFrom: List of [Integer];
        TaskPeopleCount: List of [Integer];
        People: List of [Text];
        // timeline: one entry per period; the events of all periods in one list, in period order.
        Direction: Text;
        PeriodTexts: List of [Text];
        PeriodSections: List of [Text];
        PeriodSectionIndex: List of [Integer];
        PeriodEventFrom: List of [Integer];
        PeriodEventCount: List of [Integer];
        EventTexts: List of [Text];
        // timeline label state of one render
        LabelsFitted: Boolean;
        TSize: Decimal;
        TSmall: Decimal;
        TTextW: Decimal;
        TEventTextW: Decimal;
        TColW: Decimal;
        TEventW: Decimal;
        JourneyNamesTok: Label '$end,EOF,INVALID,NEWLINE,journey,title,acc_title,acc_title_value,acc_descr,acc_descr_value,acc_descr_multiline_value,section,taskName,taskData,:', Locked = true;
        JourneyStatementTok: Label '''EOF'', ''SPACE'', ''NEWLINE'', ''title'', ''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''section'', ''taskName''', Locked = true;
        TimelineNamesTok: Label '$end,EOF,INVALID,NEWLINE,timeline,timeline_lr,timeline_td,title,acc_title,acc_title_value,acc_descr,acc_descr_value,acc_descr_multiline_value,section,period,event', Locked = true;
        TimelineStatementTok: Label '''EOF'', ''SPACE'', ''NEWLINE'', ''title'', ''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''section'', ''period'', ''event''', Locked = true;
        NoPeriodErr: Label 'An event needs a time period before it.';

    local procedure ResetModel()
    begin
        Clear(TokTypes);
        Clear(TokTexts);
        Clear(TokStarts);
        Clear(Sections);
        Clear(TaskNames);
        Clear(TaskScores);
        Clear(TaskNaN);
        Clear(TaskSections);
        Clear(TaskPeopleFrom);
        Clear(TaskPeopleCount);
        Clear(People);
        Clear(PeriodTexts);
        Clear(PeriodSections);
        Clear(PeriodSectionIndex);
        Clear(PeriodEventFrom);
        Clear(PeriodEventCount);
        Clear(EventTexts);
        DiagramTitle := '';
        AccTitle := '';
        AccDescr := '';
        CurrentSection := '';
        Direction := 'LR';
    end;

    // ---------------------------------------------------------------- common/scan.ts

    local procedure LineEnd(From: Integer): Integer
    var
        At: Integer;
    begin
        At := MText.IndexOfFrom(Src, MText.LF(), From);
        if At = 0 then
            exit(StrLen(Src) + 1);
        exit(At);
    end;

    /// <summary>Whether the lowercase ASCII word is at P, ignoring case.</summary>
    local procedure KeywordAt(P: Integer; Word: Text): Boolean
    var
        I: Integer;
        C: Integer;
    begin
        for I := 1 to StrLen(Word) do begin
            C := MText.CharAt(Src, P + I - 1);
            if (C >= 65) and (C <= 90) then
                C += 32;
            if C <> Word[I] then
                exit(false);
        end;
        exit(true);
    end;

    /// <summary>
    /// Skips comments and whitespace. Stops at a line break that starts a token. One percent sign starts a comment,
    /// and any character before %% is taken with it, a line break included (as Jison compiles the rules).
    /// </summary>
    local procedure SkipTrivia(From: Integer): Integer
    var
        N: Integer;
        P: Integer;
        C: Integer;
    begin
        N := StrLen(Src);
        P := From;
        while P <= N do begin
            C := MText.CharAt(Src, P);
            if (C = 37) and (MText.CharAt(Src, P + 1) <> 123) then
                P := LineEnd(P)
            else
                if (C <> 125) and (MText.CharAt(Src, P + 1) = 37) and (MText.CharAt(Src, P + 2) = 37) then
                    P := LineEnd(P + 3)
                else
                    if C = 10 then
                        exit(P)
                    else
                        if MText.IsSpace(C) then begin
                            P += 1;
                            while MText.IsSpace(MText.CharAt(Src, P)) do
                                P += 1;
                        end else
                            if C = 35 then
                                P := LineEnd(P)
                            else
                                exit(P);
        end;
        exit(P);
    end;

    local procedure SkipSpace(From: Integer): Integer
    var
        P: Integer;
    begin
        P := From;
        while MText.IsSpace(MText.CharAt(Src, P)) do
            P += 1;
        exit(P);
    end;

    /// <summary>
    /// Lexes an accTitle or accDescr statement at P and returns where it ends, or P if there is none. The token types
    /// acc_title, acc_title_value, acc_descr, acc_descr_value and acc_descr_multiline_value are numbered from First.
    /// </summary>
    local procedure Accessibility(P: Integer; First: Integer): Integer
    var
        Descr: Boolean;
        N: Integer;
        Q: Integer;
        C: Integer;
        EndPos: Integer;
    begin
        Descr := KeywordAt(P, 'accdescr');
        if not Descr then
            if not KeywordAt(P, 'acctitle') then
                exit(P);
        N := StrLen(Src);
        Q := SkipSpace(P + 8);
        C := MText.CharAt(Src, Q);
        if C = 58 then begin
            Q := SkipSpace(Q + 1);
            EndPos := LineEnd(Q);
            if Descr then begin
                AddToken(First + 2, P, Q);
                AddToken(First + 3, Q, EndPos);
            end else begin
                AddToken(First, P, Q);
                AddToken(First + 1, Q, EndPos);
            end;
            exit(EndPos);
        end;
        if (not Descr) or (C <> 123) then
            exit(P);
        Q := SkipSpace(Q + 1);
        while MText.CharAt(Src, Q) <> 125 do begin
            EndPos := MText.IndexOfFrom(Src, '}', Q);
            if EndPos = 0 then
                EndPos := N + 1;
            AddToken(First + 4, Q, EndPos);
            if Q = N + 1 then
                exit(N + 1);
            Q := EndPos;
        end;
        exit(Q + 1);
    end;

    local procedure AddToken(TokType: Integer; StartPos: Integer; EndPos: Integer)
    begin
        TokTypes.Add(TokType);
        TokTexts.Add(MText.Substr(Src, StartPos, EndPos));
        TokStarts.Add(StartPos);
    end;

    local procedure Emit(TokType: Integer; StartPos: Integer; EndPos: Integer): Integer
    begin
        AddToken(TokType, StartPos, EndPos);
        exit(EndPos);
    end;

    /// <summary>Jison marks its lexer done when a rule runs on empty input, so a value that matches nothing at the very end is followed by no EOF.</summary>
    local procedure FinishTokens()
    var
        N: Integer;
        Last: Integer;
    begin
        N := StrLen(Src);
        Last := TokStarts.Count();
        if Last = 0 then
            AddToken(1, N + 1, N + 1)
        else
            if TokStarts.Get(Last) < N + 1 then
                AddToken(1, N + 1, N + 1);
        AddToken(0, N + 1, N + 1);
    end;

    local procedure FailAt(DiagramType: Text; Names: Text; I: Integer; Expected: Text)
    var
        Got: Text;
    begin
        if TokTypes.Get(I) = 0 then
            Got := '1'
        else
            Got := Names.Split(',').Get(TokTypes.Get(I) + 1);
        MText.SyntaxError(DiagramType, Src, TokStarts.Get(I), 'Expecting ' + Expected + ', got ''' + Got + '''', false);
    end;

    /// <summary>text.replace(/\n\s+/g, '\n')</summary>
    local procedure CollapseIndent(Value: Text): Text
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

    local procedure AddSection(Name: Text)
    begin
        CurrentSection := Name;
        Sections.Add(Name);
    end;

    // ---------------------------------------------------------------- journey lexer and parser

    /// <summary>#, a line break and ; end every kind of text; a colon also ends a task name or a section.</summary>
    local procedure TextEnd(From: Integer; Colon: Boolean): Integer
    var
        N: Integer;
        E: Integer;
        C: Integer;
    begin
        N := StrLen(Src);
        E := From;
        while E <= N do begin
            C := MText.CharAt(Src, E);
            if (C = 35) or (C = 10) or (C = 59) or (Colon and (C = 58)) then
                exit(E);
            E += 1;
        end;
        exit(E);
    end;

    local procedure TokenizeJourney()
    var
        N: Integer;
        P: Integer;
        Done: Boolean;
    begin
        N := StrLen(Src);
        P := 1;
        repeat
            P := SkipTrivia(P);
            if P > N then
                Done := true
            else
                P := JourneyToken(P);
        until Done;
        FinishTokens();
    end;

    // Token types: 0 $end, 1 EOF, 2 INVALID, 3 NEWLINE, 4 journey, 5 title, 6 acc_title, 7 acc_title_value, 8 acc_descr,
    // 9 acc_descr_value, 10 acc_descr_multiline_value, 11 section, 12 taskName, 13 taskData, 14 ':'.
    local procedure JourneyToken(P: Integer): Integer
    var
        C: Integer;
        E: Integer;
    begin
        C := MText.CharAt(Src, P);
        E := P + 1;
        if C = 10 then begin
            while MText.CharAt(Src, E) = 10 do
                E += 1;
            exit(Emit(3, P, E));
        end;
        if KeywordAt(P, 'journey') and not MText.IsWord(MText.CharAt(Src, P + 7)) then
            exit(Emit(4, P, P + 7));
        // \s after a keyword also takes a line break, so title alone on a line takes the next line as its text.
        if KeywordAt(P, 'title') and MText.IsSpace(MText.CharAt(Src, P + 5)) then begin
            E := TextEnd(P + 6, false);
            if E > P + 6 then
                exit(Emit(5, P, E));
        end;
        E := Accessibility(P, 6);
        if E <> P then
            exit(E);
        if KeywordAt(P, 'section') and MText.IsSpace(MText.CharAt(Src, P + 7)) then begin
            E := TextEnd(P + 8, true);
            if E > P + 8 then
                exit(Emit(11, P, E));
        end;
        if C = 58 then begin
            E := TextEnd(P + 1, false);
            if E > P + 1 then
                exit(Emit(13, P, E));
            exit(Emit(14, P, P + 1));
        end;
        if C = 59 then
            exit(Emit(2, P, P + 1));
        exit(Emit(12, P, TextEnd(P + 1, true)));
    end;

    procedure ParseJourney(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    var
        I: Integer;
        TokType: Integer;
        Txt: Text;
        Done: Boolean;
    begin
        ResetModel();
        Src := Source;
        DiagramTitle := FrontTitle;
        TokenizeJourney();
        if TokTypes.Get(1) <> 4 then
            FailAt('journey', JourneyNamesTok, 1, '''journey''');
        I := 1;
        repeat
            I += 1;
            TokType := TokTypes.Get(I);
            Txt := TokTexts.Get(I);
            if TokType <> 3 then
                case TokType of
                    5:
                        DiagramTitle := CopyStr(Txt, 7);
                    6:
                        begin
                            I += 1;
                            AccTitle := MText.TrimWs(TokTexts.Get(I));
                        end;
                    8:
                        begin
                            I += 1;
                            AccDescr := CollapseIndent(MText.TrimWs(TokTexts.Get(I)));
                        end;
                    10:
                        AccDescr := CollapseIndent(MText.TrimWs(Txt));
                    11:
                        AddSection(CopyStr(Txt, 9));
                    12:
                        begin
                            I += 1;
                            if TokTypes.Get(I) <> 13 then
                                FailAt('journey', JourneyNamesTok, I, '''taskData''');
                            AddTask(Txt, TokTexts.Get(I));
                        end;
                    1:
                        Done := true;
                    else
                        FailAt('journey', JourneyNamesTok, I, JourneyStatementTok);
                end;
        until Done;
    end;

    /// <summary>Data is the rest of the line from its first colon: :score or :score:actor, actor.</summary>
    local procedure AddTask(Task: Text; Data: Text)
    var
        Pieces: List of [Text];
        Names: List of [Text];
        Name: Text;
        Score: Decimal;
        IsNaN: Boolean;
    begin
        Pieces := CopyStr(Data, 2).Split(':');
        TaskPeopleFrom.Add(People.Count() + 1);
        if Pieces.Count() = 1 then
            TaskPeopleCount.Add(0)
        else begin
            Names := Pieces.Get(2).Split(',');
            foreach Name in Names do
                People.Add(MText.TrimWs(Name));
            TaskPeopleCount.Add(Names.Count());
        end;
        JsNumber(Pieces.Get(1), Score, IsNaN);
        TaskNames.Add(Task);
        TaskScores.Add(Score);
        TaskNaN.Add(IsNaN);
        TaskSections.Add(CurrentSection);
    end;

    /// <summary>JavaScript's Number(text), with infinities held as a large number.</summary>
    local procedure JsNumber(Value: Text; var Result: Decimal; var IsNaN: Boolean)
    var
        T: Text;
        I: Integer;
        N: Integer;
        C: Integer;
        D: Integer;
        Base: Integer;
        Neg: Boolean;
        ExpNeg: Boolean;
        Digits: Integer;
        Exp10: Integer;
        ExpValue: Integer;
        Mant: Decimal;
        Big: Decimal;
    begin
        Mant := 0;
        ExpValue := 0;
        Result := 0;
        IsNaN := false;
        Big := 100000000000000000000.0;
        T := MText.TrimWs(Value);
        N := StrLen(T);
        if N = 0 then
            exit;
        if (T[1] = 48) and (N > 2) then begin
            case MText.CharAt(T, 2) of
                120, 88:
                    Base := 16;
                111, 79:
                    Base := 8;
                98, 66:
                    Base := 2;
            end;
            if Base > 0 then begin
                for I := 3 to N do begin
                    D := DigitValue(T[I]);
                    if (D < 0) or (D >= Base) then begin
                        IsNaN := true;
                        exit;
                    end;
                    if Result < Big then
                        Result := Result * Base + D;
                end;
                if Result > Big then
                    Result := Big;
                exit;
            end;
        end;
        I := 1;
        if (T[1] = 43) or (T[1] = 45) then begin
            Neg := T[1] = 45;
            I := 2;
        end;
        if CopyStr(T, I) = 'Infinity' then begin
            Result := Big;
            if Neg then
                Result := -Big;
            exit;
        end;
        while MText.IsDigit(MText.CharAt(T, I)) do begin
            if Mant < 1000000000000000000.0 then
                Mant := Mant * 10 + (T[I] - 48)
            else
                Exp10 += 1;
            Digits += 1;
            I += 1;
        end;
        if MText.CharAt(T, I) = 46 then begin
            I += 1;
            while MText.IsDigit(MText.CharAt(T, I)) do begin
                if Mant < 1000000000000000000.0 then begin
                    Mant := Mant * 10 + (T[I] - 48);
                    Exp10 -= 1;
                end;
                Digits += 1;
                I += 1;
            end;
        end;
        if Digits = 0 then begin
            IsNaN := true;
            exit;
        end;
        C := MText.CharAt(T, I);
        if (C = 101) or (C = 69) then begin
            I += 1;
            C := MText.CharAt(T, I);
            if (C = 43) or (C = 45) then begin
                ExpNeg := C = 45;
                I += 1;
            end;
            if not MText.IsDigit(MText.CharAt(T, I)) then begin
                IsNaN := true;
                exit;
            end;
            while MText.IsDigit(MText.CharAt(T, I)) do begin
                if ExpValue < 1000 then
                    ExpValue := ExpValue * 10 + (T[I] - 48);
                I += 1;
            end;
            if ExpNeg then
                ExpValue := -ExpValue;
        end;
        if I <= N then begin
            IsNaN := true;
            exit;
        end;
        Exp10 += ExpValue;
        Result := Mant;
        while (Exp10 > 0) and (Result < Big) do begin
            Result := Result * 10;
            Exp10 -= 1;
        end;
        if Result > Big then
            Result := Big;
        while (Exp10 < 0) and (Result <> 0) do begin
            if Exp10 < -60 then
                Result := 0
            else
                Result := Result / 10;
            Exp10 += 1;
        end;
        if Neg then
            Result := -Result;
    end;

    local procedure DigitValue(C: Integer): Integer
    begin
        if (C >= 48) and (C <= 57) then
            exit(C - 48);
        if (C >= 97) and (C <= 102) then
            exit(C - 87);
        if (C >= 65) and (C <= 70) then
            exit(C - 55);
        exit(-1);
    end;

    // ---------------------------------------------------------------- common/fit.ts

    /// <summary>The length of a &lt;br&gt; tag at I (as /&lt;br\s*\/?&gt;/i), or 0.</summary>
    local procedure BrLength(Value: Text; I: Integer): Integer
    var
        J: Integer;
    begin
        if MText.CharAt(Value, I) <> 60 then
            exit(0);
        if LowerCase(CopyStr(Value, I + 1, 2)) <> 'br' then
            exit(0);
        J := I + 3;
        while MText.IsSpace(MText.CharAt(Value, J)) do
            J += 1;
        if MText.CharAt(Value, J) = 47 then
            J += 1;
        if MText.CharAt(Value, J) <> 62 then
            exit(0);
        exit(J + 1 - I);
    end;

    /// <summary>
    /// Text as Mermaid's journey and timeline draw it: plain, with only &lt;br&gt; read as markup, so other tags
    /// and icon names show as written.
    /// </summary>
    local procedure PlainSource(Raw: Text): Text
    var
        Result: TextBuilder;
        I: Integer;
    begin
        if StrPos(Raw, '<') > 0 then begin
            for I := 1 to StrLen(Raw) do
                if (Raw[I] = 60) and (BrLength(Raw, I) = 0) then
                    Result.Append('&lt;')
                else
                    Result.Append(CopyStr(Raw, I, 1));
            Raw := Result.ToText();
        end;
        if StrPos(Raw, ':fa-') > 0 then
            Raw := Raw.Replace(':fa-', '&colon;fa-');
        exit(Raw);
    end;

    local procedure PlainLayout(var Lbl: Codeunit "Mermaid Label"; Raw: Text; Size: Decimal; MaxW: Decimal; StyleValue: Integer)
    begin
        Lbl.Layout(PlainSource(Raw), false, Size, MaxW, StyleValue);
    end;

    /// <summary>A line break, an encoded entity, a surrogate pair, or one character: the pieces a word can be cut between.</summary>
    local procedure UnitLength(Value: Text; I: Integer): Integer
    var
        J: Integer;
        K: Integer;
        C: Integer;
        Next: Integer;
    begin
        J := BrLength(Value, I);
        if J > 0 then
            exit(J);
        C := MText.CharAt(Value, I);
        if (C = 64258) and (MText.CharAt(Value, I + 1) = 176) then begin
            J := I + 2;
            if MText.CharAt(Value, J) = 176 then
                J += 1;
            K := J;
            while MText.IsWord(MText.CharAt(Value, K)) do
                K += 1;
            if K > J then
                if (MText.CharAt(Value, K) = 182) and (MText.CharAt(Value, K + 1) = 223) then
                    exit(K + 2 - I);
        end;
        if C = 38 then begin
            J := I + 1;
            if MText.CharAt(Value, J) = 35 then
                J += 1;
            K := J;
            while MText.IsWord(MText.CharAt(Value, K)) do
                K += 1;
            if K > J then
                if MText.CharAt(Value, K) = 59 then
                    exit(K + 1 - I);
        end;
        if (C >= 55296) and (C <= 56319) then begin
            Next := MText.CharAt(Value, I + 1);
            if (Next >= 56320) and (Next <= 57343) then
                exit(2);
        end;
        exit(1);
    end;

    /// <summary>The label wraps at spaces only. For a box of fixed width, this also cuts any word too long to fit.</summary>
    local procedure FitLayout(var Lbl: Codeunit "Mermaid Label"; Raw: Text; Size: Decimal; MaxW: Decimal; StyleValue: Integer)
    var
        Result: TextBuilder;
        Unit: Text;
        I: Integer;
        L: Integer;
        Width: Decimal;
        W: Decimal;
    begin
        PlainLayout(Lbl, Raw, Size, MaxW, StyleValue);
        if (Raw = '') or (Lbl.GetWidth() <= MaxW) then
            exit;
        I := 1;
        while I <= StrLen(Raw) do begin
            L := UnitLength(Raw, I);
            Unit := CopyStr(Raw, I, L);
            if (MText.TrimWs(Unit) = '') or ((L > 2) and (Raw[I] = 60)) then
                Width := 0
            else begin
                if L > 2 then
                    W := MText.Width('x', Size, StyleValue)
                else
                    W := MText.Width(Unit, Size, StyleValue);
                if (Width > 0) and (Width + W > MaxW) then begin
                    Result.Append(MText.LF());
                    Width := 0;
                end;
                Width += W;
            end;
            Result.Append(Unit);
            I += L;
        end;
        PlainLayout(Lbl, Result.ToText(), Size, MaxW, StyleValue);
    end;

    // ---------------------------------------------------------------- journey render

    local procedure CompareOrdinal(A: Text; B: Text): Integer
    var
        I: Integer;
        N: Integer;
    begin
        N := StrLen(A);
        if StrLen(B) < N then
            N := StrLen(B);
        for I := 1 to N do
            if A[I] <> B[I] then begin
                if A[I] < B[I] then
                    exit(-1);
                exit(1);
            end;
        if StrLen(A) < StrLen(B) then
            exit(-1);
        if StrLen(A) > StrLen(B) then
            exit(1);
        exit(0);
    end;

    /// <summary>Everyone named on a task, once each, in code unit order, without the empty name.</summary>
    local procedure Actors(var Names: List of [Text])
    var
        Name: Text;
        I: Integer;
        At: Integer;
    begin
        Clear(Names);
        foreach Name in People do
            if (Name <> '') and not Names.Contains(Name) then begin
                At := Names.Count() + 1;
                for I := Names.Count() downto 1 do
                    if CompareOrdinal(Names.Get(I), Name) > 0 then
                        At := I;
                if At > Names.Count() then
                    Names.Add(Name)
                else
                    Names.Insert(At, Name);
            end;
    end;

    local procedure Face(X: Decimal; Y: Decimal; MoodName: Text): Text
    var
        Mouth: Text;
    begin
        case MoodName of
            'happy':
                Mouth := 'M-5,2A6,6 0 0 0 5,2';
            'sad':
                Mouth := 'M-5,6.5A6,6 0 0 1 5,6.5';
            else
                Mouth := 'M-4.5,4.5H4.5';
        end;
        exit('<g class="pele-face pele-face-' + MoodName + '" transform="translate(' + MText.Num(X) + ',' + MText.Num(Y) + ')">' +
             '<circle r="11" fill="var(--_bg)" stroke="var(--_l)"/>' +
             '<g fill="var(--_l)"><circle cx="-3.6" cy="-2.8" r="1.3"/><circle cx="3.6" cy="-2.8" r="1.3"/></g>' +
             '<path d="' + Mouth + '" fill="none" stroke="var(--_l)" stroke-linecap="round"/>' +
             '</g>');
    end;

    local procedure Mood(I: Integer): Text
    begin
        if TaskNaN.Get(I) then
            exit('neutral');
        if TaskScores.Get(I) > 3 then
            exit('happy');
        if TaskScores.Get(I) < 3 then
            exit('sad');
        exit('neutral');
    end;

    local procedure TaskLabel(var Lbl: Codeunit "Mermaid Label"; I: Integer; Fitted: Boolean; Size: Decimal; MaxW: Decimal)
    begin
        if Fitted then
            FitLayout(Lbl, TaskNames.Get(I), Size, MaxW, 0)
        else
            PlainLayout(Lbl, TaskNames.Get(I), Size, MaxW, 0);
    end;

    local procedure SameSection(A: Integer; B: Integer): Boolean
    begin
        if A > TaskNames.Count() then
            exit(false);
        exit(TaskSections.Get(A) = TaskSections.Get(B));
    end;

    procedure RenderJourney(var Config: Dictionary of [Text, Text]): Text
    var
        Lbl: Codeunit "Mermaid Label";
        TitleLbl: Codeunit "Mermaid Label";
        Names: List of [Text];
        ActorIndex: Dictionary of [Text, Integer];
        LegendX: List of [Decimal];
        LegendY: List of [Decimal];
        LegendH: List of [Decimal];
        RunStarts: List of [Integer];
        RunCounts: List of [Integer];
        Cards: List of [Text];
        Body: TextBuilder;
        Grid: TextBuilder;
        Scale: TextBuilder;
        LinePath: TextBuilder;
        Stems: TextBuilder;
        Faces: TextBuilder;
        Items: TextBuilder;
        Members: TextBuilder;
        Dots: Text;
        Name: Text;
        PadX: Decimal;
        PadY: Decimal;
        MinText: Decimal;
        MaxText: Decimal;
        Gap: Decimal;
        BandPad: Decimal;
        Gutter: Decimal;
        LevelH: Decimal;
        FaceR: Decimal;
        DotR: Decimal;
        DotStep: Decimal;
        LegendGap: Decimal;
        Size: Decimal;
        Small: Decimal;
        Tiny: Decimal;
        Pad: Decimal;
        TextW: Decimal;
        Widest: Decimal;
        Fitted: Boolean;
        CardW: Decimal;
        Pitch: Decimal;
        PlotW: Decimal;
        LineH: Decimal;
        Limit: Decimal;
        LegendW: Decimal;
        LegendHeight: Decimal;
        Lx: Decimal;
        W: Decimal;
        Y: Decimal;
        H: Decimal;
        BodyW: Decimal;
        TitleH: Decimal;
        Width: Decimal;
        Left: Decimal;
        Top: Decimal;
        BandH: Decimal;
        TextH: Decimal;
        DotsH: Decimal;
        CardH: Decimal;
        CardsY: Decimal;
        ChartTop: Decimal;
        ChartBottom: Decimal;
        Right: Decimal;
        Bottom: Decimal;
        X: Decimal;
        Cx: Decimal;
        Cy: Decimal;
        ScoreLevel: Decimal;
        StepW: Decimal;
        X0: Decimal;
        Y0: Decimal;
        N: Integer;
        I: Integer;
        K: Integer;
        Score: Integer;
        EndIdx: Integer;
        PCount: Integer;
        Idx: Integer;
        TotalWidth: Integer;
        TotalHeight: Integer;
    begin
        PadX := 10;
        PadY := 8;
        MinText := 124;
        MaxText := 200;
        Gap := 12;
        BandPad := 6;
        Gutter := 24;
        LevelH := 26;
        FaceR := 11;
        DotR := 5;
        DotStep := 13;
        LegendGap := 20;

        Size := MText.FontSize();
        Small := Round(Size * 0.875, 1);
        Tiny := Round(Size * 0.75, 1);
        Pad := 8;
        N := TaskNames.Count();

        // Task: 5: names an actor with no name; Mermaid gives it a dot and an empty legend row.
        Actors(Names);
        for I := 1 to Names.Count() do
            ActorIndex.Add(Names.Get(I), I - 1);

        // Cards widen, up to a point, for a word that would not fit; past that the word is cut.
        TextW := MinText;
        for I := 1 to N do begin
            TaskLabel(Lbl, I, false, Small, TextW);
            Widest := MText.MaxDec(Widest, Lbl.GetWidth());
        end;
        if Widest > TextW then begin
            TextW := MText.MinDec(MText.Ceil(Widest), MaxText);
            Fitted := true;
        end;

        CardW := TextW + 2 * PadX;
        Pitch := CardW + Gap;
        if N > 0 then
            PlotW := N * Pitch - Gap;

        LineH := Round(Small * 1.5, 1);
        Limit := MText.MaxDec(PlotW, 240);
        Lx := 0;
        for I := 1 to Names.Count() do begin
            FitLayout(Lbl, Names.Get(I), Small, Limit - 2 * DotR - 6, 0);
            W := 2 * DotR + 6 + Lbl.GetWidth();
            if (Lx > 0) and (Lx + W > Limit) then begin
                Lx := 0;
                LegendHeight += 4;
            end;
            if Lx > 0 then
                Y := LegendY.Get(LegendY.Count())
            else
                Y := LegendHeight;
            H := MText.MaxDec(Lbl.GetHeight(), LineH);
            LegendX.Add(Lx);
            LegendY.Add(Y);
            LegendH.Add(H);
            Lx += W;
            LegendW := MText.MaxDec(LegendW, Lx);
            LegendHeight := MText.MaxDec(LegendHeight, Y + H);
            Lx += LegendGap;
        end;

        if N > 0 then
            BodyW := Gutter + PlotW;
        FitLayout(TitleLbl, DiagramTitle, Size, MText.MaxDec(BodyW, 320), MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleH := TitleLbl.GetHeight() + 16;
        Width := MText.MaxDec(BodyW, TitleLbl.GetWidth());
        if N > 0 then
            Width := MText.MaxDec(Width, Gutter + LegendW);
        Left := Pad + (Width - BodyW) / 2 + Gutter;
        Top := Pad + TitleH;

        // A band covers a run of tasks that share a section, as in Mermaid; a section with no tasks draws nothing.
        I := 1;
        while I <= N do begin
            EndIdx := I + 1;
            while SameSection(EndIdx, I) do
                EndIdx += 1;
            if TaskSections.Get(I) <> '' then begin
                FitLayout(Lbl, TaskSections.Get(I), Small, (EndIdx - I) * Pitch - Gap - 2 * PadX, MText.StyleBold());
                BandH := MText.MaxDec(BandH, MText.MaxDec(Lbl.GetHeight(), LineH) + 2 * BandPad);
            end;
            RunStarts.Add(I);
            RunCounts.Add(EndIdx - I);
            I := EndIdx;
        end;

        TextH := LineH;
        for I := 1 to N do begin
            TaskLabel(Lbl, I, Fitted, Small, TextW);
            TextH := MText.MaxDec(TextH, Lbl.GetHeight());
        end;
        if Names.Count() > 0 then
            DotsH := 2 * DotR + 6;
        CardH := TextH + DotsH + 2 * PadY;
        CardsY := Top;
        if BandH > 0 then
            CardsY := Top + BandH + BandPad;
        ChartTop := CardsY + CardH + FaceR + 16;
        ChartBottom := ChartTop + 4 * LevelH;
        Right := Left + PlotW;

        Bottom := Top;
        if N > 0 then begin
            for Score := 5 downto 1 do begin
                Y := ChartTop + (5 - Score) * LevelH;
                Grid.Append('M' + MText.Num(Left - 6) + ',' + MText.Num(Y) + 'H' + MText.Num(Right));
                Scale.Append('<text x="' + MText.Num(Left - 12) + '" y="' + MText.Num(Y + Tiny * 0.35) + '">' + MText.IntText(Score) + '</text>');
            end;
            Body.Append('<path class="pele-grid" d="' + Grid.ToText() + '" fill="none" stroke="var(--_a)"/>' +
                        '<g class="pele-scale" font-size="' + MText.Num(Tiny) + '" text-anchor="end" fill="var(--_m)">' + Scale.ToText() + '</g>');

            for I := 1 to N do begin
                X := Left + (I - 1) * Pitch;
                Cx := X + CardW / 2;
                if TaskNaN.Get(I) then
                    ScoreLevel := 3
                else
                    ScoreLevel := MText.MinDec(5, MText.MaxDec(1, TaskScores.Get(I)));
                Y := ChartTop + (5 - ScoreLevel) * LevelH;
                if I = 1 then
                    LinePath.Append('M')
                else
                    LinePath.Append('L');
                LinePath.Append(MText.Num(Cx) + ',' + MText.Num(Y));
                Stems.Append('M' + MText.Num(Cx) + ',' + MText.Num(CardsY + CardH) + 'V' + MText.Num(Y - FaceR));
                Faces.Append(Face(Cx, Y, Mood(I)));

                Dots := '';
                PCount := 0;
                for K := 0 to TaskPeopleCount.Get(I) - 1 do
                    if People.Get(TaskPeopleFrom.Get(I) + K) <> '' then
                        PCount += 1;
                if PCount > 1 then
                    StepW := MText.MinDec(DotStep, (CardW - 2 * PadX - 2 * DotR) / (PCount - 1))
                else
                    StepW := MText.MinDec(DotStep, CardW - 2 * PadX - 2 * DotR);
                Idx := 0;
                for K := 0 to TaskPeopleCount.Get(I) - 1 do begin
                    Name := People.Get(TaskPeopleFrom.Get(I) + K);
                    if Name <> '' then begin
                        Dots += '<circle class="pele-actor" cx="' + MText.Num(Cx + (Idx - (PCount - 1) / 2) * StepW) + '" cy="' + MText.Num(CardsY + CardH - PadY - DotR) +
                                '" r="5" fill="' + Builder.SeriesColor(ActorOf(ActorIndex, Name)) + '" stroke="var(--_s)">' +
                                '<title>' + MText.EscText(Name) + '</title></circle>';
                        Idx += 1;
                    end;
                end;
                TaskLabel(Lbl, I, Fitted, Small, TextW);
                Cards.Add('<g class="pele-node pele-task" data-id="' + MText.EscText(MText.TrimWs(TaskNames.Get(I))) + '">' +
                          '<rect x="' + MText.Num(X) + '" y="' + MText.Num(CardsY) + '" width="' + MText.Num(CardW) + '" height="' + MText.Num(CardH) + '" rx="' + Builder.Radius() + '" fill="var(--_s)" stroke="var(--_b)"/>' +
                          Lbl.ToSvg(Cx, CardsY + PadY + TextH / 2, ' font-size="' + MText.Num(Small) + '"') +
                          Dots +
                          '</g>');
            end;
            Body.Append('<path class="pele-stems" d="' + Stems.ToText() + '" fill="none" stroke="var(--_b)" stroke-dasharray="2 3"/>');
            if N > 1 then
                Body.Append('<path class="pele-edge" d="' + LinePath.ToText() + '" fill="none" stroke="var(--_l)" stroke-linejoin="round"/>');
            Body.Append(Faces.ToText());

            for I := 1 to RunStarts.Count() do begin
                Clear(Members);
                for K := RunStarts.Get(I) to RunStarts.Get(I) + RunCounts.Get(I) - 1 do
                    Members.Append(Cards.Get(K));
                if TaskSections.Get(RunStarts.Get(I)) = '' then
                    Body.Append(Members.ToText())
                else begin
                    X := Left + (RunStarts.Get(I) - 1) * Pitch;
                    W := RunCounts.Get(I) * Pitch - Gap;
                    FitLayout(Lbl, TaskSections.Get(RunStarts.Get(I)), Small, W - 2 * PadX, MText.StyleBold());
                    Body.Append('<g class="pele-cluster pele-section" data-id="' + MText.EscText(MText.TrimWs(TaskSections.Get(RunStarts.Get(I)))) + '">' +
                                '<rect x="' + MText.Num(X) + '" y="' + MText.Num(Top) + '" width="' + MText.Num(W) + '" height="' + MText.Num(BandH) + '" rx="' + Builder.Radius() + '" fill="var(--_a)"/>' +
                                Lbl.ToSvg(X + W / 2, Top + BandH / 2, ' font-size="' + MText.Num(Small) + '" font-weight="var(--_hw)"') +
                                Members.ToText() +
                                '</g>');
                end;
            end;
            Bottom := ChartBottom + FaceR;

            if Names.Count() > 0 then begin
                X0 := Left + (PlotW - LegendW) / 2;
                Y0 := Bottom + 16;
                for I := 1 to Names.Count() do begin
                    FitLayout(Lbl, Names.Get(I), Small, Limit - 2 * DotR - 6, 0);
                    Cy := Y0 + LegendY.Get(I) + LegendH.Get(I) / 2;
                    Items.Append('<g class="pele-legend-item" data-id="' + MText.EscText(Names.Get(I)) + '">' +
                                 '<circle cx="' + MText.Num(X0 + LegendX.Get(I) + DotR) + '" cy="' + MText.Num(Cy) + '" r="5" fill="' + Builder.SeriesColor(I - 1) + '"/>' +
                                 Lbl.ToSvg(X0 + LegendX.Get(I) + 2 * DotR + 6 + Lbl.GetWidth() / 2, Cy, '') +
                                 '</g>');
                end;
                Body.Append('<g class="pele-legend" font-size="' + MText.Num(Small) + '">' + Items.ToText() + '</g>');
                Bottom := Y0 + LegendHeight;
            end;
        end;

        TotalWidth := MText.Ceil(Width + 2 * Pad);
        TotalHeight := MText.Ceil(MText.MaxDec(Bottom, Pad) + Pad);
        exit(Builder.Document('journey', TotalWidth, TotalHeight, Size, AccTitle, AccDescr,
             TitleLbl.ToSvg(Pad + Width / 2, Pad + TitleLbl.GetHeight() / 2, ' class="pele-title" font-weight="var(--_tw)"') + Body.ToText()));
    end;

    local procedure ActorOf(var ActorIndex: Dictionary of [Text, Integer]; Name: Text): Integer
    var
        Idx: Integer;
    begin
        if ActorIndex.Get(Name, Idx) then
            exit(Idx);
        exit(0);
    end;

    // ---------------------------------------------------------------- timeline lexer and parser

    local procedure TokenizeTimeline()
    var
        N: Integer;
        P: Integer;
        Done: Boolean;
    begin
        N := StrLen(Src);
        P := 1;
        repeat
            P := SkipTrivia(P);
            if P > N then
                Done := true
            else
                P := TimelineToken(P);
        until Done;
        FinishTokens();
    end;

    // Token types: 0 $end, 1 EOF, 2 INVALID, 3 NEWLINE, 4 timeline, 5 timeline_lr, 6 timeline_td, 7 title, 8 acc_title,
    // 9 acc_title_value, 10 acc_descr, 11 acc_descr_value, 12 acc_descr_multiline_value, 13 section, 14 period, 15 event.
    local procedure TimelineToken(P: Integer): Integer
    var
        N: Integer;
        C: Integer;
        E: Integer;
        K: Integer;
        Lr: Boolean;
    begin
        N := StrLen(Src);
        C := MText.CharAt(Src, P);
        E := P + 1;
        if C = 10 then begin
            while MText.CharAt(Src, E) = 10 do
                E += 1;
            exit(Emit(3, P, E));
        end;
        if KeywordAt(P, 'timeline') then begin
            E := P + 8;
            while MText.IsBlank(MText.CharAt(Src, E)) do
                E += 1;
            Lr := KeywordAt(E, 'lr');
            if (E > P + 8) and (Lr or KeywordAt(E, 'td')) and not MText.IsWord(MText.CharAt(Src, E + 2)) then begin
                if Lr then
                    exit(Emit(5, P, E + 2));
                exit(Emit(6, P, E + 2));
            end;
            if not MText.IsWord(MText.CharAt(Src, P + 8)) then
                exit(Emit(4, P, P + 8));
        end;
        // \s after a keyword also takes a line break, so title alone on a line takes the next line as its text.
        if KeywordAt(P, 'title') and MText.IsSpace(MText.CharAt(Src, P + 5)) and (P + 6 <= N) and (MText.CharAt(Src, P + 6) <> 10) then
            exit(Emit(7, P, LineEnd(P + 6)));
        E := Accessibility(P, 8);
        if E <> P then
            exit(E);
        if KeywordAt(P, 'section') and MText.IsSpace(MText.CharAt(Src, P + 7)) then begin
            E := P + 8;
            while (E <= N) and (MText.CharAt(Src, E) <> 58) and (MText.CharAt(Src, E) <> 10) do
                E += 1;
            if E > P + 8 then
                exit(Emit(13, P, E));
        end;
        if C <> 58 then begin
            E := P + 1;
            K := MText.CharAt(Src, E);
            while (E <= N) and (K <> 35) and (K <> 58) and (K <> 10) do begin
                E += 1;
                K := MText.CharAt(Src, E);
            end;
            exit(Emit(14, P, E));
        end;
        // An event runs to the end of the line or to a colon that is followed by whitespace.
        if MText.IsSpace(MText.CharAt(Src, P + 1)) then begin
            E := P + 2;
            while E <= N do begin
                K := MText.CharAt(Src, E);
                if (K = 10) or ((K = 58) and MText.IsSpace(MText.CharAt(Src, E + 1))) then
                    break;
                E += 1;
            end;
            if E > P + 2 then
                exit(Emit(15, P, E));
        end;
        exit(Emit(2, P, P + 1));
    end;

    procedure ParseTimeline(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    var
        I: Integer;
        TokType: Integer;
        Head: Integer;
        Txt: Text;
        Done: Boolean;
    begin
        ResetModel();
        Src := Source;
        DiagramTitle := FrontTitle;
        TokenizeTimeline();
        Head := TokTypes.Get(1);
        if not (Head in [4, 5, 6]) then
            FailAt('timeline', TimelineNamesTok, 1, '''timeline'', ''timeline_lr'', ''timeline_td''');
        if Head = 6 then
            Direction := 'TD';
        I := 1;
        repeat
            I += 1;
            TokType := TokTypes.Get(I);
            Txt := TokTexts.Get(I);
            if TokType <> 3 then
                case TokType of
                    7:
                        DiagramTitle := CopyStr(Txt, 7);
                    8:
                        begin
                            I += 1;
                            AccTitle := MText.TrimWs(TokTexts.Get(I));
                        end;
                    10:
                        begin
                            I += 1;
                            AccDescr := CollapseIndent(MText.TrimWs(TokTexts.Get(I)));
                        end;
                    12:
                        AccDescr := CollapseIndent(MText.TrimWs(Txt));
                    13:
                        AddSection(CopyStr(Txt, 9));
                    14:
                        AddPeriod(Txt);
                    15:
                        AddEvent(CopyStr(Txt, 3));
                    1:
                        Done := true;
                    else
                        FailAt('timeline', TimelineNamesTok, I, TimelineStatementTok);
                end;
        until Done;
    end;

    local procedure AddPeriod(Period: Text)
    begin
        PeriodTexts.Add(Period);
        PeriodSections.Add(CurrentSection);
        PeriodSectionIndex.Add(Sections.Count() - 1);
        PeriodEventFrom.Add(EventTexts.Count() + 1);
        PeriodEventCount.Add(0);
    end;

    local procedure AddEvent(EventText: Text)
    var
        Last: Integer;
    begin
        Last := PeriodTexts.Count();
        // Mermaid fails here too, with a TypeError.
        if Last = 0 then
            MText.Fail(NoPeriodErr);
        EventTexts.Add(EventText);
        PeriodEventCount.Set(Last, PeriodEventCount.Get(Last) + 1);
    end;

    // ---------------------------------------------------------------- timeline render

    local procedure PeriodLabel(var Lbl: Codeunit "Mermaid Label"; I: Integer)
    begin
        if LabelsFitted then
            FitLayout(Lbl, PeriodTexts.Get(I), TSize, TTextW, 0)
        else
            PlainLayout(Lbl, PeriodTexts.Get(I), TSize, TTextW, 0);
    end;

    local procedure EventLabel(var Lbl: Codeunit "Mermaid Label"; E: Integer)
    begin
        if LabelsFitted then
            FitLayout(Lbl, EventTexts.Get(E), TSmall, TEventTextW, 0)
        else
            PlainLayout(Lbl, EventTexts.Get(E), TSmall, TEventTextW, 0);
    end;

    local procedure GroupPeriodCount(Section: Integer): Integer
    var
        I: Integer;
        Result: Integer;
    begin
        for I := 1 to PeriodTexts.Count() do
            if PeriodSectionIndex.Get(I) = Section then
                Result += 1;
        exit(Result);
    end;

    local procedure Box(X: Decimal; Y: Decimal; W: Decimal; H: Decimal; Attrs: Text): Text
    begin
        exit('<rect x="' + MText.Num(X) + '" y="' + MText.Num(Y) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) + '" rx="' + Builder.Radius() + '"' + Attrs + '/>');
    end;

    local procedure SectionHeader(Section: Integer; var Lbl: Codeunit "Mermaid Label"; X: Decimal; Y: Decimal; W: Decimal; H: Decimal): Text
    begin
        exit(Box(X, Y, W, H, ' fill="' + Builder.SeriesColor(Section) + '"') +
             Lbl.ToSvg(X + W / 2, Y + H / 2, ' font-weight="var(--_hw)" fill="var(--_bg)"'));
    end;

    local procedure PeriodChip(var Lbl: Codeunit "Mermaid Label"; Color: Text; X: Decimal; Y: Decimal; H: Decimal): Text
    begin
        exit(Box(X, Y, TColW, H, ' fill="' + Color + '"') + Lbl.ToSvg(X + TColW / 2, Y + H / 2, ' fill="var(--_bg)"'));
    end;

    local procedure EventCard(var Lbl: Codeunit "Mermaid Label"; Color: Text; X: Decimal; Y: Decimal; H: Decimal): Text
    begin
        exit('<g class="pele-node pele-event">' +
             Box(X, Y, TEventW, H, ' fill="' + Color + '" fill-opacity="0.16"') +
             Lbl.ToSvg(X + TEventW / 2, Y + H / 2, ' font-size="' + MText.Num(TSmall) + '"') +
             '</g>');
    end;

    local procedure TimelineDot(X: Decimal; Y: Decimal; Color: Text): Text
    begin
        exit('<circle class="pele-dot" cx="' + MText.Num(X) + '" cy="' + MText.Num(Y) + '" r="4" fill="' + Color + '" stroke="var(--_bg)" stroke-width="2"/>');
    end;

    local procedure OpenGroup(Section: Integer): Text
    begin
        if Section < 0 then
            exit('');
        exit('<g class="pele-cluster pele-section" data-id="' + MText.EscText(MText.TrimWs(Sections.Get(Section + 1))) + '">');
    end;

    local procedure OpenPeriod(I: Integer): Text
    begin
        exit('<g class="pele-node pele-period" data-id="' + MText.EscText(MText.TrimWs(PeriodTexts.Get(I))) + '">');
    end;

    local procedure ColorOf(Section: Integer; Period: Integer; Multicolor: Boolean): Text
    begin
        if Section >= 0 then
            exit(Builder.SeriesColor(Section));
        if Sections.Count() > 0 then
            exit('var(--_m)');
        if Multicolor then
            exit(Builder.SeriesColor(Period));
        exit(Builder.SeriesColor(0));
    end;

    procedure RenderTimeline(var Config: Dictionary of [Text, Text]): Text
    var
        Lbl: Codeunit "Mermaid Label";
        EventLbl: Codeunit "Mermaid Label";
        TitleLbl: Codeunit "Mermaid Label";
        Groups: List of [Integer];
        PeriodH: List of [Decimal];
        EventH: List of [Decimal];
        Body: TextBuilder;
        Cards: TextBuilder;
        D: Text;
        Color: Text;
        Prefix: Text;
        PadX: Decimal;
        PadY: Decimal;
        MinText: Decimal;
        MaxText: Decimal;
        EventTextTD: Decimal;
        Gap: Decimal;
        AxisGap: Decimal;
        Spine: Decimal;
        EventGap: Decimal;
        SectionGap: Decimal;
        Tail: Decimal;
        Line: Text;
        Pad: Decimal;
        Multicolor: Boolean;
        Vertical: Boolean;
        HasSections: Boolean;
        HasEvents: Boolean;
        Drawn: Boolean;
        Overflow: Boolean;
        PeriodText: Decimal;
        Widest: Decimal;
        LineHeight: Decimal;
        EventLine: Decimal;
        Slots: Integer;
        Pitch: Decimal;
        BodyW: Decimal;
        TitleH: Decimal;
        Width: Decimal;
        Left: Decimal;
        Top: Decimal;
        AxisX: Decimal;
        SpineX: Decimal;
        EventsX: Decimal;
        Y: Decimal;
        H: Decimal;
        Cy: Decimal;
        Ey: Decimal;
        Eh: Decimal;
        LastY: Decimal;
        Tip: Decimal;
        Height: Decimal;
        HeaderH: Decimal;
        ChipH: Decimal;
        PeriodsY: Decimal;
        AxisY: Decimal;
        EventsY: Decimal;
        Bottom: Decimal;
        Gx: Decimal;
        X: Decimal;
        Cx: Decimal;
        G: Integer;
        Section: Integer;
        Span: Integer;
        Slot: Integer;
        I: Integer;
        E: Integer;
        K: Integer;
        Members: Integer;
        TotalWidth: Integer;
        TotalHeight: Integer;
    begin
        PadX := 12;
        PadY := 8;
        MinText := 152;
        MaxText := 216;
        EventTextTD := 264;
        Gap := 20;
        AxisGap := 20;
        Spine := 14;
        EventGap := 8;
        SectionGap := 8;
        Tail := 12;
        Line := ' fill="none" stroke="var(--_b)"';

        TSize := MText.FontSize();
        TSmall := Round(TSize * 0.875, 1);
        Pad := 8;
        Multicolor := not MText.ConfigBool(Config, 'timeline.disableMulticolor', false);
        Vertical := Direction = 'TD';
        HasSections := Sections.Count() > 0;

        // Mermaid draws nothing for periods that come before the first section; here they lead, in a neutral color.
        if GroupPeriodCount(-1) > 0 then
            Groups.Add(-1);
        for I := 0 to Sections.Count() - 1 do
            Groups.Add(I);

        // Columns widen, up to a point, for a word that would not fit; past that the word is cut.
        // With no host width, the period column starts at its minimum and the event column at its widest.
        PeriodText := MinText;
        TTextW := PeriodText;
        if Vertical then
            TEventTextW := EventTextTD
        else
            TEventTextW := TTextW;
        LabelsFitted := false;
        for I := 1 to PeriodTexts.Count() do begin
            PeriodLabel(Lbl, I);
            Widest := MText.MaxDec(Widest, Lbl.GetWidth());
        end;
        if not Vertical then
            for E := 1 to EventTexts.Count() do begin
                EventLabel(Lbl, E);
                Widest := MText.MaxDec(Widest, Lbl.GetWidth());
            end;
        Overflow := Widest > TTextW;
        if Vertical then
            for E := 1 to EventTexts.Count() do begin
                EventLabel(Lbl, E);
                if Lbl.GetWidth() > EventTextTD then
                    Overflow := true;
            end;
        if Overflow then begin
            TTextW := MText.MinDec(MText.MaxDec(MText.Ceil(Widest), PeriodText), MaxText);
            if not Vertical then
                TEventTextW := TTextW;
            LabelsFitted := true;
        end;
        for I := 1 to PeriodTexts.Count() do begin
            PeriodLabel(Lbl, I);
            PeriodH.Add(Lbl.GetHeight());
        end;
        for E := 1 to EventTexts.Count() do begin
            EventLabel(Lbl, E);
            EventH.Add(Lbl.GetHeight());
        end;

        LineHeight := Round(TSize * 1.5, 1);
        EventLine := Round(TSmall * 1.5, 1);
        TColW := TTextW + 2 * PadX;
        TEventW := TEventTextW + 2 * PadX;

        HasEvents := EventTexts.Count() > 0;
        foreach Section in Groups do begin
            Members := GroupPeriodCount(Section);
            if Members < 1 then
                Members := 1;
            Slots += Members;
        end;

        Pitch := TColW + Gap;
        Drawn := PeriodTexts.Count() > 0;
        if Vertical then begin
            BodyW := TColW;
            if HasEvents then
                BodyW += AxisGap + Spine * 2 + TEventW
            else
                if Drawn then
                    BodyW += AxisGap + Tail;
        end else
            if Slots > 0 then begin
                BodyW := Slots * Pitch - Gap;
                if Drawn then
                    BodyW += Tail + Builder.Arrow();
            end;
        FitLayout(TitleLbl, DiagramTitle, TSize, MText.MaxDec(BodyW, 320), MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleH := TitleLbl.GetHeight() + 16;
        Width := MText.MaxDec(BodyW, TitleLbl.GetWidth());
        Left := Pad + (Width - BodyW) / 2;
        Top := Pad + TitleH;

        if Vertical then begin
            AxisX := Left + TColW + AxisGap;
            SpineX := AxisX + Spine;
            EventsX := SpineX + Spine;
            Y := Top;
            foreach Section in Groups do begin
                Body.Append(OpenGroup(Section));
                if Section >= 0 then begin
                    FitLayout(Lbl, Sections.Get(Section + 1), TSize, BodyW - 2 * PadX, MText.StyleBold());
                    H := MText.MaxDec(Lbl.GetHeight(), LineHeight) + 2 * PadY;
                    Body.Append(SectionHeader(Section, Lbl, Left, Y, BodyW, H));
                    Y += H + SectionGap + 4;
                end;
                for I := 1 to PeriodTexts.Count() do
                    if PeriodSectionIndex.Get(I) = Section then begin
                        Color := ColorOf(Section, I - 1, Multicolor);
                        H := MText.MaxDec(PeriodH.Get(I), LineHeight) + 2 * PadY;
                        Cy := Y + H / 2;
                        D := 'M' + MText.Num(Left + TColW) + ',' + MText.Num(Cy) + 'H' + MText.Num(AxisX);
                        Clear(Cards);
                        Ey := Y;
                        LastY := Cy;
                        for E := PeriodEventFrom.Get(I) to PeriodEventFrom.Get(I) + PeriodEventCount.Get(I) - 1 do begin
                            Eh := MText.MaxDec(EventH.Get(E), EventLine) + 2 * PadY;
                            LastY := Ey + Eh / 2;
                            D += 'M' + MText.Num(SpineX) + ',' + MText.Num(LastY) + 'H' + MText.Num(EventsX);
                            EventLabel(EventLbl, E);
                            Cards.Append(EventCard(EventLbl, Color, EventsX, Ey, Eh));
                            Ey += Eh + EventGap;
                        end;
                        if Cards.Length() > 0 then
                            D += 'M' + MText.Num(AxisX) + ',' + MText.Num(Cy) + 'H' + MText.Num(SpineX) + 'V' + MText.Num(LastY);
                        PeriodLabel(Lbl, I);
                        Body.Append(OpenPeriod(I) +
                                    PeriodChip(Lbl, Color, Left, Y, H) +
                                    '<path class="pele-edge" d="' + D + '"' + Line + '/>' +
                                    TimelineDot(AxisX, Cy, Color) +
                                    Cards.ToText() +
                                    '</g>');
                        Y := MText.MaxDec(Y + H, Ey - EventGap) + Gap;
                    end;
                if GroupPeriodCount(Section) = 0 then
                    Y += Gap - SectionGap - 4;
                if Section >= 0 then
                    Body.Append('</g>');
            end;
            if Groups.Count() > 0 then
                Y -= Gap;
            Prefix := '';
            if Drawn then begin
                Tip := Y + Tail + Builder.Arrow();
                Prefix := '<path class="pele-axis" d="M' + MText.Num(AxisX) + ',' + MText.Num(Top) + 'V' + MText.Num(Tip - Builder.Arrow() + 1) + '" fill="none" stroke="var(--_l)"/>' +
                          Builder.Marker('arrow_point', AxisX, Tip, 0, 1, 'var(--_l)');
                Y := Tip;
            end;
            Height := Y + Pad;
        end else begin
            foreach Section in Groups do
                if Section >= 0 then begin
                    Span := GroupPeriodCount(Section);
                    if Span < 1 then
                        Span := 1;
                    FitLayout(Lbl, Sections.Get(Section + 1), TSize, Span * Pitch - Gap - 2 * PadX, MText.StyleBold());
                    HeaderH := MText.MaxDec(HeaderH, MText.MaxDec(Lbl.GetHeight(), LineHeight) + 2 * PadY);
                end;
            for I := 1 to PeriodTexts.Count() do
                ChipH := MText.MaxDec(ChipH, MText.MaxDec(PeriodH.Get(I), LineHeight) + 2 * PadY);
            PeriodsY := Top;
            if HasSections then
                PeriodsY := Top + HeaderH + SectionGap;
            AxisY := PeriodsY + ChipH;
            if ChipH > 0 then
                AxisY += AxisGap;
            EventsY := AxisY + AxisGap;
            if Drawn then
                Bottom := AxisY + Tail
            else
                Bottom := Top + HeaderH;
            Slot := 0;
            for G := 1 to Groups.Count() do begin
                Section := Groups.Get(G);
                Span := GroupPeriodCount(Section);
                if Span < 1 then
                    Span := 1;
                Gx := Left + Slot * Pitch;
                Body.Append(OpenGroup(Section));
                if Section >= 0 then begin
                    FitLayout(Lbl, Sections.Get(Section + 1), TSize, Span * Pitch - Gap - 2 * PadX, MText.StyleBold());
                    Body.Append(SectionHeader(Section, Lbl, Gx, Top, Span * Pitch - Gap, HeaderH));
                end;
                K := 0;
                for I := 1 to PeriodTexts.Count() do
                    if PeriodSectionIndex.Get(I) = Section then begin
                        Color := ColorOf(Section, I - 1, Multicolor);
                        X := Gx + K * Pitch;
                        Cx := X + TColW / 2;
                        if PeriodEventCount.Get(I) > 0 then
                            D := 'M' + MText.Num(Cx) + ',' + MText.Num(PeriodsY + ChipH) + 'V' + MText.Num(EventsY)
                        else
                            D := 'M' + MText.Num(Cx) + ',' + MText.Num(PeriodsY + ChipH) + 'V' + MText.Num(AxisY);
                        Clear(Cards);
                        Ey := EventsY;
                        for E := PeriodEventFrom.Get(I) to PeriodEventFrom.Get(I) + PeriodEventCount.Get(I) - 1 do begin
                            Eh := MText.MaxDec(EventH.Get(E), EventLine) + 2 * PadY;
                            if Ey > EventsY then
                                D += 'M' + MText.Num(Cx) + ',' + MText.Num(Ey - EventGap) + 'V' + MText.Num(Ey);
                            EventLabel(EventLbl, E);
                            Cards.Append(EventCard(EventLbl, Color, X, Ey, Eh));
                            Ey += Eh + EventGap;
                        end;
                        Bottom := MText.MaxDec(Bottom, Ey - EventGap);
                        PeriodLabel(Lbl, I);
                        Body.Append(OpenPeriod(I) +
                                    PeriodChip(Lbl, Color, X, PeriodsY, ChipH) +
                                    '<path class="pele-edge" d="' + D + '"' + Line + '/>' +
                                    TimelineDot(Cx, AxisY, Color) +
                                    Cards.ToText() +
                                    '</g>');
                        K += 1;
                    end;
                if Section >= 0 then
                    Body.Append('</g>');
                Slot += Span;
            end;
            Prefix := '';
            if Drawn then begin
                Tip := Left + BodyW;
                Prefix := '<path class="pele-axis" d="M' + MText.Num(Left) + ',' + MText.Num(AxisY) + 'H' + MText.Num(Tip - Builder.Arrow() + 1) + '" fill="none" stroke="var(--_l)"/>' +
                          Builder.Marker('arrow_point', Tip, AxisY, 1, 0, 'var(--_l)');
            end;
            Height := Bottom + Pad;
        end;

        TotalWidth := MText.Ceil(Width + 2 * Pad);
        TotalHeight := MText.Ceil(MText.MaxDec(Height, Pad * 2));
        exit(Builder.Document('timeline', TotalWidth, TotalHeight, TSize, AccTitle, AccDescr,
             TitleLbl.ToSvg(TotalWidth / 2, Pad + TitleLbl.GetHeight() / 2, ' class="pele-title" font-weight="var(--_tw)"') + Prefix + Body.ToText()));
    end;
}
