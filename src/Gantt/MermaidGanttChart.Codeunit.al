/// <summary>
/// Port of pele's diagrams/gantt: lexer.ts, parser.ts, db.ts (scheduling), dates.ts (the dayjs subset),
/// axis.ts (the d3 time axis subset) and render.ts.
/// Times are BigInteger milliseconds since 1970-01-01 00:00 on a wall clock without a time zone or daylight
/// saving time: pele's local time with a zero UTC offset. NaNT() stands for both an undefined time and an
/// invalid Date.
/// </summary>
codeunit 68916 "Mermaid Gantt Chart"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        // Lexer
        Src: Text;
        TokTypes: List of [Integer];
        TokTexts: List of [Text];
        TokStarts: List of [Integer];
        LexPos: Integer;
        // Model
        GTitle: Text;
        GAccTitle: Text;
        GAccDescr: Text;
        GDateFormat: Text;
        GAxisFormat: Text;
        GTickInterval: Text;
        GTodayMarker: Text;
        GIncludes: List of [Text];
        GExcludes: List of [Text];
        GInclusiveEndDates: Boolean;
        GTopAxis: Boolean;
        GDisplayMode: Text;
        GWeekday: Text;
        GHasWeekday: Boolean;
        GWeekend: Text;
        GSections: List of [Text];
        GLinks: Dictionary of [Text, Text];
        // Tasks, one entry per task in source order
        TId: List of [Text];
        TName: List of [Text];
        TSection: List of [Text];
        TStart: List of [BigInteger];
        TEnd: List of [BigInteger];
        TRenderEnd: List of [BigInteger];
        TManualEnd: List of [Boolean];
        TProcessed: List of [Boolean];
        TActive: List of [Boolean];
        TDone: List of [Boolean];
        TCrit: List of [Boolean];
        TMilestone: List of [Boolean];
        TVert: List of [Boolean];
        TOrder: List of [Integer];
        TClickable: List of [Boolean];
        TPrevId: List of [Text];
        THasPrev: List of [Boolean];
        TRawStart: List of [Text];
        THasRawStart: List of [Boolean];
        TRawEnd: List of [Text];
        ById: Dictionary of [Text, Integer];
        CurrentSection: Text;
        TaskCount: Integer;
        LastOrder: Integer;
        LastTaskId: Text;
        HasLastTask: Boolean;
        // Scheduling
        NowMs: BigInteger;
        Work: Decimal;
        ExcludedDays: array[7] of Boolean;
        DatedTokens: Boolean;
        // Compiled parse format (dates.ts compile)
        CompiledFormat: Text;
        CompiledDone: Boolean;
        CompiledOk: Boolean;
        StepReader: List of [Text];
        StepLiteral: List of [Text];
        // Parsed fields (dates.ts Fields)
        FYear: Decimal;
        FMonth: Decimal;
        FDay: Decimal;
        FHours: Decimal;
        FMinutes: Decimal;
        FSeconds: Decimal;
        FMs: Decimal;
        FWeek: Decimal;
        FOffset: Decimal;
        FAfternoon: Boolean;
        HasYear: Boolean;
        HasMonth: Boolean;
        HasDay: Boolean;
        DayGiven: Boolean;
        HasHours: Boolean;
        HasMinutes: Boolean;
        HasSeconds: Boolean;
        HasMs: Boolean;
        HasWeek: Boolean;
        HasOffset: Boolean;
        HasAfternoon: Boolean;
        // Tick calendar (axis.ts every): unit 0 millisecond, 1 second, 2 minute, 3 hour, 4 day, 5 week, 6 month, 7 year
        CalUnit: Integer;
        CalStep: Decimal;
        CalWeekStart: Integer;

    // ================================================================ public contract

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    begin
        ResetModel();
        if FrontTitle <> '' then
            GTitle := FrontTitle;
        if Config.ContainsKey('gantt.displayMode') then
            GDisplayMode := Config.Get('gantt.displayMode');
        Src := Source;
        Tokenize();
        ParseTokens();
    end;

    local procedure ResetModel()
    begin
        GTitle := '';
        GAccTitle := '';
        GAccDescr := '';
        GDateFormat := '';
        GAxisFormat := '';
        GTickInterval := '';
        GTodayMarker := '';
        Clear(GIncludes);
        Clear(GExcludes);
        GInclusiveEndDates := false;
        GTopAxis := false;
        GDisplayMode := '';
        GWeekday := '';
        GHasWeekday := false;
        GWeekend := 'saturday';
        Clear(GSections);
        Clear(GLinks);
        Clear(TId);
        Clear(TName);
        Clear(TSection);
        Clear(TStart);
        Clear(TEnd);
        Clear(TRenderEnd);
        Clear(TManualEnd);
        Clear(TProcessed);
        Clear(TActive);
        Clear(TDone);
        Clear(TCrit);
        Clear(TMilestone);
        Clear(TVert);
        Clear(TOrder);
        Clear(TClickable);
        Clear(TPrevId);
        Clear(THasPrev);
        Clear(TRawStart);
        Clear(THasRawStart);
        Clear(TRawEnd);
        Clear(ById);
        CurrentSection := '';
        TaskCount := 0;
        LastOrder := 0;
        LastTaskId := '';
        HasLastTask := false;
        CompiledDone := false;
    end;

    // ================================================================ lexer (lexer.ts)
    // Token types follow pele's T enum: 0 END, 1 ERROR, 2 open_directive, 3 acc_title, 4 acc_title_value,
    // 5 acc_descr, 6 acc_descr_value, 7 acc_descr_multiline_value, 8 NL, 9 href, 10 callbackname,
    // 11 callbackargs, 12 click, 13 gantt, 14 dateFormat, 15 inclusiveEndDates, 16 topAxis, 17 axisFormat,
    // 18 tickInterval, 19 includes, 20 excludes, 21 todayMarker, 22..28 weekday_monday..weekday_sunday,
    // 29 weekend_friday, 30 weekend_saturday, 31 date, 32 title, 33 accDescription, 34 section, 35 taskTxt,
    // 36 taskData, 37 COLON, 38 EOF.
    // Lexer states: 0 INITIAL, 1 acc_title, 2 acc_descr, 3 acc_descr_multiline, 4 href, 5 callbackname,
    // 6 callbackargs, 7 click.

    local procedure Tokenize()
    var
        N: Integer;
        State: Integer;
        C: Integer;
        D: Integer;
        E: Integer;
        EndType: Integer;
    begin
        Clear(TokTypes);
        Clear(TokTexts);
        Clear(TokStarts);
        N := StrLen(Src);
        LexPos := 1;
        State := 0;
        while true do begin
            if LexPos > N then begin
                case State of
                    1:
                        EndType := 4;
                    2:
                        EndType := 6;
                    3:
                        EndType := 7;
                    4:
                        EndType := 9;
                    5:
                        EndType := 10;
                    6:
                        EndType := 11;
                    7:
                        EndType := 12;
                    else
                        EndType := 38;
                end;
                Emit(EndType, N + 1, N + 1);
                break;
            end;
            C := MText.CharAt(Src, LexPos);
            case State of
                0:
                    begin
                        D := MText.CharAt(Src, LexPos + 1);
                        if C = 37 then begin
                            if D <> 37 then begin
                                E := UntilChar(10, LexPos + 1);
                                while MText.CharAt(Src, E) = 10 do
                                    E += 1;
                                LexPos := E;
                            end else
                                if MText.CharAt(Src, LexPos + 2) = 123 then begin
                                    // The grammar enters a lexer state it never defines, so nothing can follow.
                                    Emit(2, LexPos, LexPos + 3);
                                    Emit(1, LexPos, LexPos);
                                    exit;
                                end else
                                    LexPos := UntilChar(10, LexPos + 2);
                        end else
                            if (C <> 125) and (D = 37) then
                                LexPos := UntilChar(10, LexPos + 2)
                            else
                                if C = 10 then begin
                                    E := LexPos + 1;
                                    while MText.CharAt(Src, E) = 10 do
                                        E += 1;
                                    Emit(8, LexPos, E);
                                end else
                                    if MText.IsSpace(C) then begin
                                        LexPos += 1;
                                        while MText.IsSpace(MText.CharAt(Src, LexPos)) do
                                            LexPos += 1;
                                    end else
                                        if not Keyword(C, State) then
                                            if MText.IsDigit(C) and AtDate() then
                                                Emit(31, LexPos, LexPos + 10)
                                            else
                                                if C <> 58 then begin
                                                    E := LexPos + 1;
                                                    while (E <= N) and (MText.CharAt(Src, E) <> 58) and (MText.CharAt(Src, E) <> 10) do
                                                        E += 1;
                                                    Emit(35, LexPos, E);
                                                end else begin
                                                    E := LexPos + 1;
                                                    while (E <= N) and (MText.CharAt(Src, E) <> 35) and (MText.CharAt(Src, E) <> 10) and (MText.CharAt(Src, E) <> 59) do
                                                        E += 1;
                                                    if E > LexPos + 1 then
                                                        Emit(36, LexPos, E)
                                                    else
                                                        Emit(37, LexPos, E);
                                                end;
                    end;
                1, 2:
                    begin
                        if State = 1 then
                            E := 4
                        else
                            E := 6;
                        State := 0;
                        Emit(E, LexPos, UntilChar(10, LexPos));
                    end;
                3:
                    if C = 125 then begin
                        State := 0;
                        LexPos += 1;
                    end else
                        Emit(7, LexPos, UntilChar(125, LexPos));
                4:
                    if C = 34 then begin
                        State := 0;
                        LexPos += 1;
                    end else
                        Emit(9, LexPos, UntilChar(34, LexPos));
                5:
                    if C = 40 then begin
                        E := AtEmptyCall();
                        if E > 0 then begin
                            State := 0;
                            LexPos := E;
                        end else begin
                            State := 6;
                            LexPos += 1;
                        end;
                    end else
                        Emit(10, LexPos, UntilChar(40, LexPos));
                6:
                    if C = 41 then begin
                        State := 0;
                        LexPos += 1;
                    end else
                        Emit(11, LexPos, UntilChar(41, LexPos));
                7:
                    if MText.IsSpace(C) then begin
                        State := 0;
                        LexPos += 1;
                    end else begin
                        E := LexPos + 1;
                        while (E <= N) and not MText.IsSpace(MText.CharAt(Src, E)) do
                            E += 1;
                        Emit(12, LexPos, E);
                    end;
            end;
        end;
        TokTypes.Add(0);
        TokTexts.Add('');
        TokStarts.Add(N + 1);
    end;

    local procedure Emit(TokenType: Integer; StartPos: Integer; EndPos: Integer)
    begin
        TokTypes.Add(TokenType);
        TokTexts.Add(MText.Substr(Src, StartPos, EndPos));
        TokStarts.Add(StartPos);
        LexPos := EndPos;
    end;

    local procedure UntilChar(Ch: Integer; FromPos: Integer): Integer
    var
        P: Integer;
    begin
        P := FromPos;
        while (P <= StrLen(Src)) and (MText.CharAt(Src, P) <> Ch) do
            P += 1;
        exit(P);
    end;

    /// <summary>Statements that start with a keyword, tried in the grammar's rule order.</summary>
    local procedure Keyword(C: Integer; var State: Integer): Boolean
    var
        E: Integer;
        Day: Integer;
    begin
        if (C >= 65) and (C <= 90) then
            C += 32;
        case C of
            97:
                begin
                    E := AtAcc('acctitle', 58);
                    if E > 0 then begin
                        State := 1;
                        Emit(3, LexPos, E);
                        exit(true);
                    end;
                    E := AtAcc('accdescr', 58);
                    if E > 0 then begin
                        State := 2;
                        Emit(5, LexPos, E);
                        exit(true);
                    end;
                    E := AtAcc('accdescr', 123);
                    if E > 0 then begin
                        State := 3;
                        LexPos := E;
                        exit(true);
                    end;
                end;
            104:
                begin
                    E := AtWordSpaces('href');
                    if E > 0 then
                        if MText.CharAt(Src, E) = 34 then begin
                            State := 4;
                            LexPos := E + 1;
                            exit(true);
                        end;
                end;
            99:
                begin
                    E := AtWordSpaces('call');
                    if E > 0 then begin
                        State := 5;
                        LexPos := E;
                        exit(true);
                    end;
                    E := AtWordSpaces('click');
                    if E > 0 then begin
                        State := 7;
                        LexPos := E;
                        exit(true);
                    end;
                end;
            119:
                begin
                    E := AtWeekday(Day);
                    if E > 0 then begin
                        Emit(22 + Day, LexPos, E);
                        exit(true);
                    end;
                    E := AtWeekend(Day);
                    if E > 0 then begin
                        Emit(Day, LexPos, E);
                        exit(true);
                    end;
                end;
        end;
        case C of
            97:
                begin
                    if EmitRest('axisformat', 1, 17) then
                        exit(true);
                    exit(EmitRest('accdescription', 1, 33));
                end;
            103:
                exit(EmitBound('gantt', 13));
            100:
                exit(EmitRest('dateformat', 1, 14));
            105:
                begin
                    if EmitBound('inclusiveenddates', 15) then
                        exit(true);
                    exit(EmitRest('includes', 1, 19));
                end;
            116:
                begin
                    if EmitBound('topaxis', 16) then
                        exit(true);
                    if EmitRest('tickinterval', 1, 18) then
                        exit(true);
                    if EmitRest('todaymarker', 2, 21) then
                        exit(true);
                    exit(EmitRest('title', 3, 32));
                end;
            101:
                exit(EmitRest('excludes', 1, 20));
            115:
                exit(EmitRest('section', 3, 34));
        end;
        exit(false);
    end;

    local procedure WordCI(P: Integer; Word: Text): Boolean
    begin
        if (P < 1) or (P + StrLen(Word) - 1 > StrLen(Src)) then
            exit(false);
        exit(LowerCase(CopyStr(Src, P, StrLen(Word))) = Word);
    end;

    local procedure SkipWsFrom(P: Integer): Integer
    begin
        while MText.IsSpace(MText.CharAt(Src, P)) do
            P += 1;
        exit(P);
    end;

    /// <summary>/word\s*X\s*/i at the cursor, for accTitle: and accDescr: or accDescr {.</summary>
    local procedure AtAcc(Word: Text; Delim: Integer): Integer
    var
        P: Integer;
    begin
        if not WordCI(LexPos, Word) then
            exit(0);
        P := SkipWsFrom(LexPos + StrLen(Word));
        if MText.CharAt(Src, P) <> Delim then
            exit(0);
        exit(SkipWsFrom(P + 1));
    end;

    /// <summary>/word\s+/i at the cursor.</summary>
    local procedure AtWordSpaces(Word: Text): Integer
    var
        P: Integer;
    begin
        if not WordCI(LexPos, Word) then
            exit(0);
        P := LexPos + StrLen(Word);
        if not MText.IsSpace(MText.CharAt(Src, P)) then
            exit(0);
        exit(SkipWsFrom(P));
    end;

    local procedure AtWeekday(var Day: Integer): Integer
    var
        P: Integer;
        I: Integer;
        Name: Text;
    begin
        P := AtWordSpaces('weekday');
        if P = 0 then
            exit(0);
        for I := 0 to 6 do begin
            Name := LowerCase(WeekdayName((I + 1) mod 7));
            if WordCI(P, Name) then
                if not MText.IsWord(MText.CharAt(Src, P + StrLen(Name))) then begin
                    Day := I;
                    exit(P + StrLen(Name));
                end;
        end;
        exit(0);
    end;

    local procedure AtWeekend(var TokenType: Integer): Integer
    var
        P: Integer;
    begin
        P := AtWordSpaces('weekend');
        if P = 0 then
            exit(0);
        if WordCI(P, 'friday') then
            if not MText.IsWord(MText.CharAt(Src, P + 6)) then begin
                TokenType := 29;
                exit(P + 6);
            end;
        if WordCI(P, 'saturday') then
            if not MText.IsWord(MText.CharAt(Src, P + 8)) then begin
                TokenType := 30;
                exit(P + 8);
            end;
        exit(0);
    end;

    /// <summary>/word\s[^...]+/i at the cursor; Mode 1 stops at # newline ;, 2 at newline ;, 3 at newline.</summary>
    local procedure AtRest(Word: Text; Mode: Integer): Integer
    var
        P: Integer;
        StartPos: Integer;
        C: Integer;
        Stop: Boolean;
    begin
        if not WordCI(LexPos, Word) then
            exit(0);
        P := LexPos + StrLen(Word);
        if not MText.IsSpace(MText.CharAt(Src, P)) then
            exit(0);
        P += 1;
        StartPos := P;
        Stop := false;
        while not Stop do begin
            C := MText.CharAt(Src, P);
            if (C = -1) or (C = 10) then
                Stop := true
            else
                if (C = 59) and (Mode < 3) then
                    Stop := true
                else
                    if (C = 35) and (Mode = 1) then
                        Stop := true
                    else
                        P += 1;
        end;
        if P = StartPos then
            exit(0);
        exit(P);
    end;

    local procedure EmitRest(Word: Text; Mode: Integer; TokenType: Integer): Boolean
    var
        E: Integer;
    begin
        E := AtRest(Word, Mode);
        if E = 0 then
            exit(false);
        Emit(TokenType, LexPos, E);
        exit(true);
    end;

    local procedure EmitBound(Word: Text; TokenType: Integer): Boolean
    begin
        if not WordCI(LexPos, Word) then
            exit(false);
        if MText.IsWord(MText.CharAt(Src, LexPos + StrLen(Word))) then
            exit(false);
        Emit(TokenType, LexPos, LexPos + StrLen(Word));
        exit(true);
    end;

    local procedure AtDate(): Boolean
    var
        I: Integer;
    begin
        for I := 0 to 9 do
            if (I = 4) or (I = 7) then begin
                if MText.CharAt(Src, LexPos + I) <> 45 then
                    exit(false);
            end else
                if not MText.IsDigit(MText.CharAt(Src, LexPos + I)) then
                    exit(false);
        exit(not MText.IsWord(MText.CharAt(Src, LexPos + 10)));
    end;

    local procedure AtEmptyCall(): Integer
    var
        P: Integer;
    begin
        P := SkipWsFrom(LexPos + 1);
        if MText.CharAt(Src, P) = 41 then
            exit(P + 1);
        exit(0);
    end;

    // ================================================================ parser (parser.ts)

    local procedure TokType(I: Integer): Integer
    begin
        if I > TokTypes.Count() then
            exit(0);
        exit(TokTypes.Get(I));
    end;

    local procedure TokText(I: Integer): Text
    begin
        if I > TokTexts.Count() then
            exit('');
        exit(TokTexts.Get(I));
    end;

    local procedure TokenName(TokenType: Integer): Text
    var
        Names: List of [Text];
    begin
        Names := ('$end,INVALID,open_directive,acc_title,acc_title_value,acc_descr,acc_descr_value,acc_descr_multiline_value,' +
                  'NL,href,callbackname,callbackargs,click,gantt,dateFormat,inclusiveEndDates,topAxis,axisFormat,tickInterval,' +
                  'includes,excludes,todayMarker,weekday_monday,weekday_tuesday,weekday_wednesday,weekday_thursday,' +
                  'weekday_friday,weekday_saturday,weekday_sunday,weekend_friday,weekend_saturday,date,title,accDescription,' +
                  'section,taskTxt,taskData,:,EOF').Split(',');
        if (TokenType < 0) or (TokenType >= Names.Count()) then
            exit('INVALID');
        exit(Names.Get(TokenType + 1));
    end;

    local procedure LineTokens(): Text
    begin
        exit('''EOF'', ''SPACE'', ''NL'', ''weekday_monday'', ''weekday_tuesday'', ''weekday_wednesday'', ''weekday_thursday'', ' +
             '''weekday_friday'', ''weekday_saturday'', ''weekday_sunday'', ''weekend_friday'', ''weekend_saturday'', ''dateFormat'', ' +
             '''inclusiveEndDates'', ''topAxis'', ''axisFormat'', ''tickInterval'', ''excludes'', ''includes'', ''todayMarker'', ''title'', ' +
             '''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''section'', ''taskTxt'', ''click''');
    end;

    /// <summary>Tokens that can start a line, which are also the only ones that can follow a complete statement.</summary>
    local procedure StartsLine(TokenType: Integer): Boolean
    begin
        exit(TokenType in [3, 5, 7, 8, 12, 14 .. 30, 32, 34, 35, 38]);
    end;

    local procedure FailAt(I: Integer; Expected: Text)
    var
        T: Integer;
        Got: Text;
        StartPos: Integer;
    begin
        T := TokType(I);
        if T = 0 then
            Got := '1'
        else
            Got := TokenName(T);
        if I <= TokStarts.Count() then
            StartPos := TokStarts.Get(I)
        else
            StartPos := StrLen(Src) + 1;
        MText.SyntaxError('gantt', Src, StartPos, 'Expecting ' + Expected + ', got ''' + Got + '''', false);
    end;

    /// <summary>Mermaid's parser runs a statement's action only after seeing that the next token can follow it.</summary>
    local procedure EndStmt(I: Integer; Also: Text)
    begin
        if not StartsLine(TokType(I)) then
            FailAt(I, LineTokens() + Also);
    end;

    local procedure SliceFrom(Value: Text; ZeroBased: Integer): Text
    begin
        exit(MText.Substr(Value, ZeroBased + 1, StrLen(Value) + 1));
    end;

    local procedure ParseTokens()
    var
        I: Integer;
        T: Integer;
        Txt: Text;
        Value: Text;
        HrefText: Text;
        HasName: Boolean;
        HasArgs: Boolean;
        HasHref: Boolean;
        Data: Text;
    begin
        I := 1;
        if TokType(I) <> 13 then
            FailAt(I, '''gantt''');
        I += 1;
        while true do begin
            T := TokType(I);
            Txt := TokText(I);
            if not StartsLine(T) then
                FailAt(I, LineTokens());
            I += 1;
            case T of
                38:
                    begin
                        if TokType(I) = 0 then
                            exit;
                        EndStmt(I, '');
                    end;
                8:
                    ;
                14:
                    begin
                        EndStmt(I, '');
                        GDateFormat := SliceFrom(Txt, 11);
                    end;
                15:
                    begin
                        EndStmt(I, '');
                        GInclusiveEndDates := true;
                    end;
                16:
                    begin
                        EndStmt(I, '');
                        GTopAxis := true;
                    end;
                17:
                    begin
                        EndStmt(I, '');
                        GAxisFormat := SliceFrom(Txt, 11);
                    end;
                18:
                    begin
                        EndStmt(I, '');
                        GTickInterval := SliceFrom(Txt, 13);
                    end;
                20:
                    begin
                        EndStmt(I, '');
                        MergeTokens(GExcludes, SliceFrom(Txt, 9));
                    end;
                19:
                    begin
                        EndStmt(I, '');
                        MergeTokens(GIncludes, SliceFrom(Txt, 9));
                    end;
                21:
                    begin
                        EndStmt(I, '');
                        GTodayMarker := SliceFrom(Txt, 12);
                    end;
                29:
                    begin
                        EndStmt(I, '');
                        GWeekend := 'friday';
                    end;
                30:
                    begin
                        EndStmt(I, '');
                        GWeekend := 'saturday';
                    end;
                32:
                    begin
                        EndStmt(I, '');
                        GTitle := SliceFrom(Txt, 6);
                    end;
                3:
                    begin
                        if TokType(I) <> 4 then
                            FailAt(I, '''acc_title_value''');
                        Value := TokText(I);
                        I += 1;
                        EndStmt(I, '');
                        GAccTitle := MText.TrimWs(Value);
                    end;
                5:
                    begin
                        if TokType(I) <> 6 then
                            FailAt(I, '''acc_descr_value''');
                        Value := TokText(I);
                        I += 1;
                        EndStmt(I, '');
                        GAccDescr := CollapseDescr(MText.TrimWs(Value));
                    end;
                7:
                    begin
                        EndStmt(I, '');
                        GAccDescr := CollapseDescr(MText.TrimWs(Txt));
                    end;
                34:
                    begin
                        EndStmt(I, '');
                        CurrentSection := SliceFrom(Txt, 8);
                        GSections.Add(CurrentSection);
                    end;
                35:
                    begin
                        if TokType(I) <> 36 then
                            FailAt(I, '''taskData''');
                        Data := TokText(I);
                        I += 1;
                        EndStmt(I, '');
                        AddTask(Txt, Data);
                    end;
                12:
                    begin
                        HasName := false;
                        HasArgs := false;
                        HasHref := false;
                        if TokType(I) = 10 then begin
                            HasName := true;
                            I += 1;
                            if TokType(I) = 11 then begin
                                HasArgs := true;
                                I += 1;
                            end;
                            if TokType(I) = 9 then begin
                                HrefText := TokText(I);
                                HasHref := true;
                                I += 1;
                                EndStmt(I, '');
                            end else
                                if HasArgs then
                                    EndStmt(I, ', ''href''')
                                else
                                    EndStmt(I, ', ''callbackargs'', ''href''');
                        end else
                            if TokType(I) = 9 then begin
                                HrefText := TokText(I);
                                HasHref := true;
                                I += 1;
                                if TokType(I) = 10 then begin
                                    HasName := true;
                                    I += 1;
                                    if TokType(I) = 11 then begin
                                        I += 1;
                                        EndStmt(I, '');
                                    end else
                                        EndStmt(I, ', ''callbackargs''');
                                end else
                                    EndStmt(I, ', ''callbackname''');
                            end else
                                FailAt(I, '''callbackname'', ''href''');
                        // Callbacks are recognized and never run; the task is only marked clickable, as in Mermaid.
                        if HasName then
                            SetClickable(Txt);
                        if HasHref then
                            SetLink(Txt, HrefText);
                    end;
                22 .. 28:
                    begin
                        EndStmt(I, '');
                        GWeekday := LowerCase(WeekdayName((T - 22 + 1) mod 7));
                        GHasWeekday := true;
                    end;
            end;
        end;
    end;

    local procedure CollapseDescr(Value: Text): Text
    var
        Out: TextBuilder;
        I: Integer;
    begin
        // txt.replace(/\n\s+/g, '\n')
        I := 1;
        while I <= StrLen(Value) do begin
            if Value[I] = 10 then begin
                if MText.IsSpace(MText.CharAt(Value, I + 1)) then begin
                    Out.Append(MText.LF());
                    I += 1;
                    while MText.IsSpace(MText.CharAt(Value, I)) do
                        I += 1;
                end else begin
                    Out.Append(MText.LF());
                    I += 1;
                end;
            end else begin
                Out.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        end;
        exit(Out.ToText());
    end;

    local procedure MergeTokens(var Existing: List of [Text]; Txt: Text)
    var
        Token: TextBuilder;
        Lower: Text;
        I: Integer;
        C: Integer;
    begin
        Lower := LowerCase(Txt);
        for I := 1 to StrLen(Lower) + 1 do begin
            C := MText.CharAt(Lower, I);
            if (C = -1) or (C = 44) or MText.IsSpace(C) then begin
                if Token.Length() > 0 then
                    if not Existing.Contains(Token.ToText()) then
                        Existing.Add(Token.ToText());
                Clear(Token);
            end else
                Token.Append(CopyStr(Lower, I, 1));
        end;
    end;

    // ================================================================ model (db.ts)

    local procedure AddTask(Descr: Text; DataStr: Text)
    var
        Data: List of [Text];
        Body: Text;
        Tag: Text;
        Id: Text;
        IsActive: Boolean;
        IsDone: Boolean;
        IsCrit: Boolean;
        IsMilestone: Boolean;
        IsVert: Boolean;
        Searching: Boolean;
        I: Integer;
        N: Integer;
    begin
        if DataStr.StartsWith(':') then
            Body := CopyStr(DataStr, 2)
        else
            Body := DataStr;
        Data := Body.Split(',');
        Searching := true;
        while Searching do begin
            Searching := false;
            if Data.Count() > 0 then begin
                Tag := MText.TrimWs(Data.Get(1));
                if Tag = 'active' then
                    IsActive := true
                else
                    if Tag = 'done' then
                        IsDone := true
                    else
                        if Tag = 'crit' then
                            IsCrit := true
                        else
                            if Tag = 'milestone' then
                                IsMilestone := true
                            else
                                if Tag = 'vert' then
                                    IsVert := true
                                else
                                    Tag := '';
                if Tag <> '' then begin
                    Data.RemoveAt(1);
                    Searching := true;
                end;
            end;
        end;
        // Mermaid fails with a TypeError on both of these.
        if Data.Count() = 0 then
            MText.Fail('Task "' + MText.TrimWs(Descr) + '" needs a duration or an end date.');
        if Data.Count() > 3 then
            MText.Fail('Task "' + MText.TrimWs(Descr) + '" has too many fields. A task takes an id, a start, and an end or duration.');
        N := Data.Count();
        for I := 1 to N do
            Data.Set(I, MText.TrimWs(Data.Get(I)));
        if N = 3 then
            Id := Data.Get(1)
        else begin
            TaskCount += 1;
            Id := 'task' + MText.IntText(TaskCount);
        end;

        TId.Add(Id);
        TName.Add(Descr);
        TSection.Add(CurrentSection);
        TStart.Add(NaNT());
        TEnd.Add(NaNT());
        TRenderEnd.Add(NaNT());
        TManualEnd.Add(false);
        TProcessed.Add(false);
        TActive.Add(IsActive);
        TDone.Add(IsDone);
        TCrit.Add(IsCrit);
        TMilestone.Add(IsMilestone);
        TVert.Add(IsVert);
        if IsVert then
            TOrder.Add(-1)
        else begin
            TOrder.Add(LastOrder);
            LastOrder += 1;
        end;
        TClickable.Add(false);
        TPrevId.Add(LastTaskId);
        THasPrev.Add(HasLastTask);
        if N > 1 then begin
            TRawStart.Add(Data.Get(N - 1));
            THasRawStart.Add(true);
        end else begin
            TRawStart.Add('');
            THasRawStart.Add(false);
        end;
        TRawEnd.Add(Data.Get(N));
        LastTaskId := Id;
        HasLastTask := true;
        if ById.ContainsKey(Id) then
            ById.Set(Id, TId.Count())
        else
            ById.Add(Id, TId.Count());
    end;

    local procedure SetClickable(Ids: Text)
    var
        Id: Text;
    begin
        foreach Id in Ids.Split(',') do
            if ById.ContainsKey(Id) then
                TClickable.Set(ById.Get(Id), true);
    end;

    local procedure SetLink(Ids: Text; Link: Text)
    var
        Href: Text;
        Id: Text;
    begin
        Href := SafeUrl(Link);
        foreach Id in Ids.Split(',') do
            if ById.ContainsKey(Id) then
                if GLinks.ContainsKey(Id) then
                    GLinks.Set(Id, Href)
                else
                    GLinks.Add(Id, Href);
        SetClickable(Ids);
    end;

    // ================================================================ scheduling (db.ts getTasks)

    /// <summary>The current local wall-clock time, the one place it is read.</summary>
    local procedure Clock(): BigInteger
    var
        Moment: DateTime;
        D: Date;
        Tm: Time;
        Ms: BigInteger;
    begin
        Moment := CurrentDateTime();
        D := DT2Date(Moment);
        Tm := DT2Time(Moment);
        Ms := Tm - 000000T;
        exit(DaysFromCivil(Date2DMY(D, 3), Date2DMY(D, 2), Date2DMY(D, 1)) * DayMs() + Ms);
    end;

    /// <summary>Resolves every task's start and end, from scratch, with up to eleven passes as Mermaid makes.</summary>
    local procedure GetTasks()
    var
        Day: Integer;
        Iso: Integer;
        WeekendStart: Integer;
        Weekends: Boolean;
        Token: Text;
        I: Integer;
        AllProcessed: Boolean;
    begin
        NowMs := Clock();
        Work := 0;
        WeekendStart := 6;
        if GWeekend = 'friday' then
            WeekendStart := 5;
        Weekends := GExcludes.Contains('weekends');
        for Day := 0 to 6 do begin
            Iso := Day;
            if Iso = 0 then
                Iso := 7;
            ExcludedDays[Day + 1] := (Weekends and ((Iso = WeekendStart) or (Iso = WeekendStart + 1))) or
                                     GExcludes.Contains(LowerCase(WeekdayName(Day)));
        end;
        // A date written with only these tokens and separators can never read as a weekday name.
        DatedTokens := (GIncludes.Count() > 0) or not IsNumericFormat(MText.TrimWs(GDateFormat));
        foreach Token in GExcludes do
            if (Token <> 'weekends') and not IsDayName(Token) then
                DatedTokens := true;

        for I := 1 to TId.Count() do begin
            TStart.Set(I, NaNT());
            TEnd.Set(I, NaNT());
            TRenderEnd.Set(I, NaNT());
            TProcessed.Set(I, false);
            TManualEnd.Set(I, false);
        end;

        AllProcessed := CompileTasks();
        I := 0;
        while (not AllProcessed) and (I < 10) do begin
            AllProcessed := CompileTasks();
            I += 1;
        end;
    end;

    local procedure IsNumericFormat(Value: Text): Boolean
    var
        I: Integer;
    begin
        for I := 1 to StrLen(Value) do
            if StrPos('YMDHhmsSZXx-/.:, T', CopyStr(Value, I, 1)) = 0 then
                exit(false);
        exit(true);
    end;

    local procedure IsDayName(Value: Text): Boolean
    var
        Day: Integer;
    begin
        for Day := 0 to 6 do
            if LowerCase(WeekdayName(Day)) = Value then
                exit(true);
        exit(false);
    end;

    /// <summary>Whether a day is excluded: by its weekday name, by its date as YYYY-MM-DD, or by its date in the chart's format.</summary>
    local procedure IsInvalidDate(T: BigInteger): Boolean
    var
        Weekday: Boolean;
        Template: Text;
        DateOnly: Text;
        Formatted: Text;
        HasFormatted: Boolean;
    begin
        Weekday := ExcludedDays[TDay(T) + 1];
        if not DatedTokens then
            exit(Weekday);
        Template := MText.TrimWs(GDateFormat);
        DateOnly := IsoDate(T);
        Formatted := DateOnly;
        HasFormatted := true;
        Spend(200);
        if Template <> 'YYYY-MM-DD' then begin
            Spend(400 + StrLen(Template) * 8);
            Formatted := FormatT(T, Template, HasFormatted);
        end;
        if Listed(GIncludes, DateOnly, Formatted, HasFormatted) then
            exit(false);
        exit(Weekday or Listed(GExcludes, DateOnly, Formatted, HasFormatted));
    end;

    local procedure Listed(var Tokens: List of [Text]; DateOnly: Text; Formatted: Text; HasFormatted: Boolean): Boolean
    begin
        if Tokens.Contains(DateOnly) then
            exit(true);
        if HasFormatted then
            exit(Tokens.Contains(Formatted));
        exit(false);
    end;

    /// <summary>Bounds the work, in rough character operations, so a hostile diagram fails instead of hanging.</summary>
    local procedure Spend(Units: Decimal)
    begin
        Work += Units;
        if Work > 400000000 then
            MText.Fail('The gantt chart takes too much work to schedule.');
    end;

    local procedure ParseWith(Str: Text; Template: Text): BigInteger
    begin
        Spend((StrLen(Template) + 1) * (StrLen(Str) + 1));
        exit(ParseStrict(Str, Template, NowMs));
    end;

    local procedure TodayT(): BigInteger
    begin
        exit(StartOfDay(NowMs));
    end;

    local procedure CompileTasks(): Boolean
    var
        I: Integer;
        AllProcessed: Boolean;
    begin
        AllProcessed := true;
        for I := 1 to TId.Count() do begin
            CompileTask(I);
            AllProcessed := AllProcessed and TProcessed.Get(I);
        end;
        exit(AllProcessed);
    end;

    local procedure CompileTask(I: Integer)
    var
        Prev: Integer;
        S: BigInteger;
        E: BigInteger;
    begin
        if not THasRawStart.Get(I) then begin
            // Mermaid fails with a TypeError when the first task has no start. It starts today here.
            Prev := 0;
            if THasPrev.Get(I) then
                if ById.ContainsKey(TPrevId.Get(I)) then
                    Prev := ById.Get(TPrevId.Get(I));
            if Prev > 0 then
                TStart.Set(I, TEnd.Get(Prev))
            else
                TStart.Set(I, TodayT());
        end else begin
            S := GetStartDate(TRawStart.Get(I));
            if IsValidT(S) then
                TStart.Set(I, S);
        end;
        if not IsValidT(TStart.Get(I)) then
            exit;
        E := GetEndDate(TStart.Get(I), TRawEnd.Get(I));
        TEnd.Set(I, E);
        if not IsValidT(E) then
            exit;
        TProcessed.Set(I, true);
        TManualEnd.Set(I, IsValidT(ParseWith(TRawEnd.Get(I), 'YYYY-MM-DD')));
        CheckTaskDates(I);
    end;

    /// <summary>/^keyword\s+([\d\w- ]+)/: the ids an after or until refers to, or false when the text is not one.</summary>
    local procedure MatchRef(Str: Text; Kw: Text; var Ids: Text): Boolean
    var
        P: Integer;
        WsStart: Integer;
        RunStart: Integer;
        K: Integer;
    begin
        Ids := '';
        if not Str.StartsWith(Kw) then
            exit(false);
        P := StrLen(Kw) + 1;
        WsStart := P;
        while MText.IsSpace(MText.CharAt(Str, P)) do
            P += 1;
        if P = WsStart then
            exit(false);
        RunStart := P;
        while IsRefChar(MText.CharAt(Str, P)) do
            P += 1;
        if P > RunStart then begin
            Ids := MText.Substr(Str, RunStart, P);
            exit(true);
        end;
        // Backtracking can hand a space of the gap to the group, which then holds no ids.
        for K := WsStart + 1 to RunStart - 1 do
            if MText.CharAt(Str, K) = 32 then
                exit(true);
        exit(false);
    end;

    local procedure IsRefChar(C: Integer): Boolean
    begin
        exit(MText.IsWord(C) or (C = 45) or (C = 32));
    end;

    local procedure References(Ids: Text; var Found: List of [Integer])
    var
        Id: Text;
    begin
        Clear(Found);
        foreach Id in Ids.Split(' ') do
            if Id <> '' then
                if ById.ContainsKey(Id) then
                    Found.Add(ById.Get(Id));
    end;

    local procedure GetStartDate(Raw: Text): BigInteger
    var
        Found: List of [Integer];
        Str: Text;
        Template: Text;
        Ids: Text;
        Idx: Integer;
        Latest: Integer;
        Parsed: BigInteger;
    begin
        Str := MText.TrimWs(Raw);
        Template := MText.TrimWs(GDateFormat);

        if ((Template = 'x') or (Template = 'X')) and IsAllDigits(Str) then begin
            Parsed := DigitsTime(Str, Template = 'X');
            if not IsValidT(Parsed) then
                MText.Fail('Invalid date:' + Str);
            exit(Parsed);
        end;

        if MatchRef(Str, 'after', Ids) then begin
            References(Ids, Found);
            Latest := 0;
            foreach Idx in Found do
                if Latest = 0 then
                    Latest := Idx
                else
                    if IsValidT(TEnd.Get(Idx)) and IsValidT(TEnd.Get(Latest)) then
                        if TEnd.Get(Idx) > TEnd.Get(Latest) then
                            Latest := Idx;
            if Latest > 0 then
                exit(TEnd.Get(Latest));
            exit(TodayT());
        end;

        Parsed := ParseWith(Str, Template);
        if IsValidT(Parsed) then
            exit(Parsed);

        // What does not fit the format gets a second chance with the JavaScript date parser, as in Mermaid.
        Parsed := JsDateParse(Str);
        if not IsValidT(Parsed) then
            MText.Fail('Invalid date:' + Str);
        if (TYear(Parsed) < -10000) or (TYear(Parsed) > 10000) then
            MText.Fail('Invalid date:' + Str);
        exit(Parsed);
    end;

    local procedure GetEndDate(StartTime: BigInteger; Raw: Text): BigInteger
    var
        Found: List of [Integer];
        Str: Text;
        Template: Text;
        Ids: Text;
        Idx: Integer;
        Earliest: Integer;
        Parsed: BigInteger;
        Value: Decimal;
        DurUnit: Text;
        EndT: BigInteger;
    begin
        Str := MText.TrimWs(Raw);

        if MatchRef(Str, 'until', Ids) then begin
            References(Ids, Found);
            Earliest := 0;
            foreach Idx in Found do
                if Earliest = 0 then
                    Earliest := Idx
                else
                    if IsValidT(TStart.Get(Idx)) and IsValidT(TStart.Get(Earliest)) then
                        if TStart.Get(Idx) < TStart.Get(Earliest) then
                            Earliest := Idx;
            if Earliest > 0 then
                exit(TStart.Get(Earliest));
            exit(TodayT());
        end;

        Template := MText.TrimWs(GDateFormat);
        Parsed := ParseWith(Str, Template);
        if IsValidT(Parsed) then begin
            if GInclusiveEndDates then
                exit(AddDaysT(Parsed, 1));
            exit(Parsed);
        end;

        if not ParseDuration(Str, Value, DurUnit) then
            exit(StartTime);
        EndT := AddT(StartTime, Value, DurUnit);
        if IsValidT(EndT) then
            exit(EndT);
        exit(StartTime);
    end;

    /// <summary>/^(\d+(?:\.\d+)?)([Mdhmswy]|ms)$/ on the trimmed text.</summary>
    local procedure ParseDuration(Raw: Text; var Value: Decimal; var DurUnit: Text): Boolean
    var
        Str: Text;
        P: Integer;
        NumEnd: Integer;
    begin
        Str := MText.TrimWs(Raw);
        P := 1;
        while MText.IsDigit(MText.CharAt(Str, P)) do
            P += 1;
        if P = 1 then
            exit(false);
        if (MText.CharAt(Str, P) = 46) and MText.IsDigit(MText.CharAt(Str, P + 1)) then begin
            P += 1;
            while MText.IsDigit(MText.CharAt(Str, P)) do
                P += 1;
        end;
        NumEnd := P;
        DurUnit := CopyStr(Str, NumEnd);
        if not ((DurUnit = 'M') or (DurUnit = 'd') or (DurUnit = 'h') or (DurUnit = 'm') or (DurUnit = 's') or
                (DurUnit = 'w') or (DurUnit = 'y') or (DurUnit = 'ms')) then
            exit(false);
        if NumEnd > 19 then
            Value := 1000000000000000000.0
        else
            if not Evaluate(Value, MText.Substr(Str, 1, NumEnd), 9) then
                Value := 1000000000000000000.0;
        exit(true);
    end;

    /// <summary>Pushes the end of a task out by one day for every excluded day it covers.</summary>
    local procedure CheckTaskDates(I: Integer)
    var
        Cursor: BigInteger;
        EndT: BigInteger;
        MaxEnd: BigInteger;
        RenderEnd: BigInteger;
        HasRender: Boolean;
        Invalid: Boolean;
    begin
        if (GExcludes.Count() = 0) or TManualEnd.Get(I) then
            exit;
        Cursor := AddDaysT(TStart.Get(I), 1);
        EndT := TEnd.Get(I);
        MaxEnd := AddDaysT(EndT, 10000);
        Invalid := false;
        HasRender := false;
        while IsValidT(Cursor) and IsValidT(EndT) and (Cursor <= EndT) do begin
            Spend(400);
            if not Invalid then begin
                RenderEnd := EndT;
                HasRender := true;
            end;
            Invalid := IsInvalidDate(Cursor);
            if Invalid then begin
                EndT := AddDaysT(EndT, 1);
                if IsValidT(EndT) and IsValidT(MaxEnd) then
                    if EndT > MaxEnd then
                        MText.Fail('Failed to find a valid date that was not excluded by `excludes` after 10,000 iterations.');
            end;
            Cursor := AddDaysT(Cursor, 1);
        end;
        TEnd.Set(I, EndT);
        if HasRender then
            TRenderEnd.Set(I, RenderEnd)
        else
            TRenderEnd.Set(I, NaNT());
    end;

    local procedure IsAllDigits(Value: Text): Boolean
    var
        I: Integer;
    begin
        if Value = '' then
            exit(false);
        for I := 1 to StrLen(Value) do
            if not MText.IsDigit(MText.CharAt(Value, I)) then
                exit(false);
        exit(true);
    end;

    /// <summary>new Date(Number(digits)).</summary>
    local procedure DigitsTime(Digits: Text; Seconds: Boolean): BigInteger
    var
        Value: Decimal;
    begin
        while (StrLen(Digits) > 1) and (CopyStr(Digits, 1, 1) = '0') do
            Digits := CopyStr(Digits, 2);
        if StrLen(Digits) > 17 then
            exit(NaNT());
        if not Evaluate(Value, Digits, 9) then
            exit(NaNT());
        if Seconds then
            Value := Value * 1000;
        exit(ClipT(Value));
    end;

    // ================================================================ time arithmetic

    local procedure DayMs(): BigInteger
    begin
        exit(86400000);
    end;

    local procedure WeekMs(): BigInteger
    begin
        exit(604800000);
    end;

    local procedure MaxTime(): BigInteger
    var
        Value: BigInteger;
    begin
        Value := 86400000;
        exit(Value * 100000000);
    end;

    local procedure NaNT(): BigInteger
    begin
        exit(-MaxTime() * 10);
    end;

    local procedure IsValidT(T: BigInteger): Boolean
    begin
        exit((T >= -MaxTime()) and (T <= MaxTime()));
    end;

    local procedure TruncDec(Value: Decimal): Decimal
    begin
        if Value >= 0 then
            exit(Round(Value, 1, '<'));
        exit(Round(Value, 1, '>'));
    end;

    local procedure FloorDec(Value: Decimal): Decimal
    begin
        exit(Round(Value, 1, '<'));
    end;

    /// <summary>JavaScript's TimeClip: an integral time, or NaNT() outside the range a Date can hold.</summary>
    local procedure ClipT(Value: Decimal): BigInteger
    var
        Result: BigInteger;
    begin
        if (Value > MaxTime()) or (Value < -MaxTime()) then
            exit(NaNT());
        Result := TruncDec(Value);
        exit(Result);
    end;

    local procedure FloorDivB(A: BigInteger; B: BigInteger): BigInteger
    var
        Q: BigInteger;
    begin
        Q := A div B;
        if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
            Q -= 1;
        exit(Q);
    end;

    local procedure PosModB(A: BigInteger; B: BigInteger): BigInteger
    begin
        exit(A - FloorDivB(A, B) * B);
    end;

    local procedure DaysFromCivil(Y: BigInteger; M: BigInteger; D: BigInteger): BigInteger
    var
        Era: BigInteger;
        Yoe: BigInteger;
        Mp: BigInteger;
        Doy: BigInteger;
        Doe: BigInteger;
    begin
        if M <= 2 then
            Y := Y - 1;
        if Y >= 0 then
            Era := Y div 400
        else
            Era := (Y - 399) div 400;
        Yoe := Y - Era * 400;
        if M > 2 then
            Mp := M - 3
        else
            Mp := M + 9;
        Doy := (153 * Mp + 2) div 5 + D - 1;
        Doe := Yoe * 365 + Yoe div 4 - Yoe div 100 + Doy;
        exit(Era * 146097 + Doe - 719468);
    end;

    local procedure CivilFromDays(Z: BigInteger; var Y: Integer; var M: Integer; var D: Integer)
    var
        Era: BigInteger;
        Doe: BigInteger;
        Yoe: BigInteger;
        Yr: BigInteger;
        Doy: BigInteger;
        Mp: BigInteger;
        Mo: BigInteger;
        Dy: BigInteger;
    begin
        Z := Z + 719468;
        if Z >= 0 then
            Era := Z div 146097
        else
            Era := (Z - 146096) div 146097;
        Doe := Z - Era * 146097;
        Yoe := (Doe - Doe div 1460 + Doe div 36524 - Doe div 146096) div 365;
        Yr := Yoe + Era * 400;
        Doy := Doe - (365 * Yoe + Yoe div 4 - Yoe div 100);
        Mp := (5 * Doy + 2) div 153;
        Dy := Doy - (153 * Mp + 2) div 5 + 1;
        if Mp < 10 then
            Mo := Mp + 3
        else
            Mo := Mp - 9;
        if Mo <= 2 then
            Yr += 1;
        Y := Yr;
        M := Mo;
        D := Dy;
    end;

    /// <summary>The local fields of a time: month 0-based, weekday 0 for Sunday.</summary>
    local procedure Parts(T: BigInteger; var Y: Integer; var Mo: Integer; var D: Integer; var H: Integer; var Mi: Integer; var S: Integer; var Ms: Integer; var Wd: Integer)
    var
        Days: BigInteger;
        Rem: BigInteger;
        M1: Integer;
    begin
        Days := FloorDivB(T, DayMs());
        Rem := T - Days * DayMs();
        H := Rem div 3600000;
        Mi := (Rem div 60000) mod 60;
        S := (Rem div 1000) mod 60;
        Ms := Rem mod 1000;
        CivilFromDays(Days, Y, M1, D);
        Mo := M1 - 1;
        Wd := PosModB(Days + 4, 7);
    end;

    local procedure TYear(T: BigInteger): Integer
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
    begin
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        exit(Y);
    end;

    local procedure TMonth(T: BigInteger): Integer
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
    begin
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        exit(Mo);
    end;

    local procedure TDate(T: BigInteger): Integer
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
    begin
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        exit(D);
    end;

    local procedure TDay(T: BigInteger): Integer
    begin
        exit(PosModB(FloorDivB(T, DayMs()) + 4, 7));
    end;

    local procedure THours(T: BigInteger): Integer
    begin
        exit(PosModB(T, DayMs()) div 3600000);
    end;

    local procedure TMinutes(T: BigInteger): Integer
    begin
        exit((PosModB(T, DayMs()) div 60000) mod 60);
    end;

    local procedure TSeconds(T: BigInteger): Integer
    begin
        exit((PosModB(T, DayMs()) div 1000) mod 60);
    end;

    local procedure TMillis(T: BigInteger): Integer
    begin
        exit(PosModB(T, 1000));
    end;

    /// <summary>new Date(y, m, d, h, mi, s, ms) without the two-digit year rule: fields overflow into the next ones.</summary>
    local procedure MakeT(Y: Decimal; M0: Decimal; D: Decimal; H: Decimal; Mi: Decimal; S: Decimal; Ms: Decimal): BigInteger
    var
        Ym: BigInteger;
        Mn: BigInteger;
        Mb: BigInteger;
        Yb: BigInteger;
        Days: BigInteger;
        Total: Decimal;
    begin
        if (Abs(Y) > 400000) or (Abs(M0) > 4800000) or (Abs(D) > 200000000) or (Abs(H) > 10000000000.0) or
           (Abs(Mi) > 1000000000000.0) or (Abs(S) > 100000000000000.0) or (Abs(Ms) > 100000000000000000.0) then
            exit(NaNT());
        Yb := TruncDec(Y);
        Mb := TruncDec(M0);
        Ym := Yb + FloorDivB(Mb, 12);
        Mn := PosModB(Mb, 12);
        Days := DaysFromCivil(Ym, Mn + 1, 1);
        Total := Days;
        Total := (Total + TruncDec(D) - 1) * 86400000 + TruncDec(H) * 3600000 + TruncDec(Mi) * 60000 + TruncDec(S) * 1000 + TruncDec(Ms);
        exit(ClipT(Total));
    end;

    local procedure StartOfDay(T: BigInteger): BigInteger
    begin
        if not IsValidT(T) then
            exit(NaNT());
        exit(T - PosModB(T, DayMs()));
    end;

    local procedure AddDaysT(T: BigInteger; N: Decimal): BigInteger
    var
        Value: Decimal;
    begin
        if not IsValidT(T) then
            exit(NaNT());
        if Abs(N) > 1000000000 then
            exit(NaNT());
        Value := T;
        exit(ClipT(Value + N * 86400000));
    end;

    local procedure AddMsT(T: BigInteger; Amount: Decimal): BigInteger
    var
        Value: Decimal;
    begin
        if not IsValidT(T) then
            exit(NaNT());
        if Abs(Amount) > 100000000000000000000.0 then
            exit(NaNT());
        Value := T;
        exit(ClipT(Value + Amount));
    end;

    local procedure IsLeap(Y: Integer): Boolean
    begin
        exit(((Y mod 4 = 0) and (Y mod 100 <> 0)) or (Y mod 400 = 0));
    end;

    local procedure DaysInMonth(Y: Integer; M1: Integer): Integer
    begin
        case M1 of
            2:
                if IsLeap(Y) then
                    exit(29)
                else
                    exit(28);
            4, 6, 9, 11:
                exit(30);
        end;
        exit(31);
    end;

    /// <summary>dayjs add: months and years keep the day of the month unless the new month is shorter.</summary>
    local procedure AddT(T: BigInteger; Amount: Decimal; DurUnit: Text): BigInteger
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
        Idx: BigInteger;
        NewY: BigInteger;
        NewM: BigInteger;
        Dd: Integer;
    begin
        if not IsValidT(T) then
            exit(NaNT());
        case DurUnit of
            'M', 'y':
                begin
                    if Abs(Amount) > 10000000 then
                        exit(NaNT());
                    Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
                    if DurUnit = 'M' then begin
                        Idx := TruncDec(Mo + Amount);
                        NewY := Y + FloorDivB(Idx, 12);
                        NewM := PosModB(Idx, 12);
                    end else begin
                        NewY := TruncDec(Y + Amount);
                        NewM := Mo;
                    end;
                    if Abs(NewY) > 400000 then
                        exit(NaNT());
                    Dd := DaysInMonth(NewY, NewM + 1);
                    if D < Dd then
                        Dd := D;
                    exit(MakeT(NewY, NewM, Dd, H, Mi, S, Ms));
                end;
            'd':
                exit(AddDaysT(T, Round(Amount, 1)));
            'w':
                exit(AddDaysT(T, Round(7 * Amount, 1)));
            'h':
                exit(AddMsT(T, Amount * 3600000));
            'm':
                exit(AddMsT(T, Amount * 60000));
            's':
                exit(AddMsT(T, Amount * 1000));
        end;
        exit(AddMsT(T, Amount));
    end;

    // ================================================================ dayjs formatting and parsing (dates.ts)

    local procedure MonthName(M0: Integer): Text
    begin
        exit('January,February,March,April,May,June,July,August,September,October,November,December'.Split(',').Get(M0 + 1));
    end;

    local procedure WeekdayName(Day: Integer): Text
    begin
        exit('Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday'.Split(',').Get(Day + 1));
    end;

    local procedure PadNum(Value: BigInteger; Len: Integer): Text
    var
        S: Text;
    begin
        S := Format(Value, 0, 9);
        if StrLen(S) < Len then
            S := MText.RepeatText('0', Len - StrLen(S)) + S;
        exit(S);
    end;

    local procedure BigText(Value: BigInteger): Text
    begin
        exit(Format(Value, 0, 9));
    end;

    local procedure Ordinal(N: Integer): Text
    var
        V: Integer;
        K: Integer;
        Suffix: Text;
    begin
        V := N mod 100;
        Suffix := 'th';
        if V >= 20 then begin
            K := (V - 20) mod 10;
            case K of
                1:
                    Suffix := 'st';
                2:
                    Suffix := 'nd';
                3:
                    Suffix := 'rd';
            end;
        end else
            case V of
                1:
                    Suffix := 'st';
                2:
                    Suffix := 'nd';
                3:
                    Suffix := 'rd';
            end;
        exit(MText.IntText(N) + Suffix);
    end;

    local procedure IsoWeekday(T: BigInteger): Integer
    var
        Day: Integer;
    begin
        Day := TDay(T);
        if Day = 0 then
            exit(7);
        exit(Day);
    end;

    local procedure WeekThursday(T: BigInteger): BigInteger
    begin
        exit(AddDaysT(T, 4 - IsoWeekday(T)));
    end;

    local procedure IsoWeek(T: BigInteger): Integer
    var
        Thursday: BigInteger;
        Jan1: BigInteger;
        First: BigInteger;
        Weekday: Integer;
        Shift: Integer;
        Weeks: Decimal;
        Result: Integer;
    begin
        Thursday := WeekThursday(T);
        Jan1 := MakeT(TYear(Thursday), 0, 1, 0, 0, 0, 0);
        Weekday := IsoWeekday(Jan1);
        Shift := 4 - Weekday;
        if Weekday > 4 then
            Shift += 7;
        First := AddDaysT(Jan1, Shift);
        Weeks := (Thursday - First) / WeekMs();
        if Weeks < 0 then
            Result := Round(Weeks, 1, '>')
        else
            Result := Round(Weeks, 1, '<');
        exit(Result + 1);
    end;

    local procedure IsoDate(T: BigInteger): Text
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
        Result: Text;
    begin
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        if (Y >= 1000) and (Y <= 9999) then
            Result := MText.IntText(Y)
        else
            Result := PadNum(Y, 4);
        if Mo + 1 < 10 then
            Result += '-0'
        else
            Result += '-';
        Result += MText.IntText(Mo + 1);
        if D < 10 then
            Result += '-0'
        else
            Result += '-';
        exit(Result + MText.IntText(D));
    end;

    local procedure ZoneText(Colon: Boolean): Text
    begin
        // Times here carry no UTC offset.
        if Colon then
            exit('+00:00');
        exit('+0000');
    end;

    local procedure RunLength(Str: Text; P: Integer; Ch: Integer; MaxLen: Integer): Integer
    var
        L: Integer;
    begin
        while (L < MaxLen) and (MText.CharAt(Str, P + L) = Ch) do
            L += 1;
        exit(L);
    end;

    /// <summary>The end of a [literal] at P (a bracket, at least one character other than ], and the closing bracket), or 0.</summary>
    local procedure LiteralEnd(Str: Text; P: Integer): Integer
    var
        J: Integer;
    begin
        if MText.CharAt(Str, P) <> 91 then
            exit(0);
        J := P + 1;
        while (J <= StrLen(Str)) and (MText.CharAt(Str, J) <> 93) do
            J += 1;
        if (J > StrLen(Str)) or (J = P + 1) then
            exit(0);
        exit(J + 1);
    end;

    /// <summary>dayjs format with the advanced format and ISO week plugins. Ok is false for the tokens that fail in Mermaid.</summary>
    local procedure FormatT(T: BigInteger; Template: Text; var Ok: Boolean): Text
    var
        Adv: TextBuilder;
        Out: TextBuilder;
        Str: Text;
        AdvText: Text;
        I: Integer;
        E: Integer;
        L: Integer;
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
        H12: Integer;
        Unsupported: Boolean;
        YearText: Text;
    begin
        Ok := true;
        if not IsValidT(T) then
            exit('Invalid Date');
        Str := Template;
        if Str = '' then
            Str := 'YYYY-MM-DDTHH:mm:ssZ';
        if Str = 'YYYY-MM-DD' then
            exit(IsoDate(T));
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);

        // First pass: the advanced format tokens.
        I := 1;
        while I <= StrLen(Str) do begin
            E := LiteralEnd(Str, I);
            if E > 0 then begin
                Adv.Append(MText.Substr(Str, I, E));
                I := E;
            end else
                if MText.StartsWithAt(Str, 'Q', I) then begin
                    Adv.Append(MText.IntText(Round((Mo + 1) / 3, 1, '>')));
                    I += 1;
                end else
                    if MText.StartsWithAt(Str, 'wo', I) or MText.StartsWithAt(Str, 'ww', I) then begin
                        Unsupported := true;
                        Adv.Append(CopyStr(Str, I, 2));
                        I += 2;
                    end else
                        if MText.StartsWithAt(Str, 'w', I) then begin
                            Unsupported := true;
                            Adv.Append('w');
                            I += 1;
                        end else
                            if MText.StartsWithAt(Str, 'WW', I) then begin
                                Adv.Append(PadNum(IsoWeek(T), 2));
                                I += 2;
                            end else
                                if MText.StartsWithAt(Str, 'W', I) then begin
                                    Adv.Append(MText.IntText(IsoWeek(T)));
                                    I += 1;
                                end else
                                    if MText.StartsWithAt(Str, 'zzz', I) then begin
                                        Unsupported := true;
                                        Adv.Append('zzz');
                                        I += 3;
                                    end else
                                        if MText.StartsWithAt(Str, 'z', I) then begin
                                            Unsupported := true;
                                            Adv.Append('z');
                                            I += 1;
                                        end else
                                            if MText.StartsWithAt(Str, 'gggg', I) then begin
                                                Unsupported := true;
                                                Adv.Append('gggg');
                                                I += 4;
                                            end else
                                                if MText.StartsWithAt(Str, 'GGGG', I) then begin
                                                    Adv.Append(MText.IntText(TYear(WeekThursday(T))));
                                                    I += 4;
                                                end else
                                                    if MText.StartsWithAt(Str, 'Do', I) then begin
                                                        Adv.Append('[' + Ordinal(D) + ']');
                                                        I += 2;
                                                    end else
                                                        if MText.StartsWithAt(Str, 'X', I) then begin
                                                            Adv.Append(BigText(FloorDivB(T, 1000)));
                                                            I += 1;
                                                        end else
                                                            if MText.StartsWithAt(Str, 'x', I) then begin
                                                                Adv.Append(BigText(T));
                                                                I += 1;
                                                            end else
                                                                if MText.StartsWithAt(Str, 'k', I) then begin
                                                                    H12 := H;
                                                                    if H12 = 0 then
                                                                        H12 := 24;
                                                                    if MText.StartsWithAt(Str, 'kk', I) then begin
                                                                        Adv.Append(PadNum(H12, 2));
                                                                        I += 2;
                                                                    end else begin
                                                                        Adv.Append(MText.IntText(H12));
                                                                        I += 1;
                                                                    end;
                                                                end else begin
                                                                    Adv.Append(CopyStr(Str, I, 1));
                                                                    I += 1;
                                                                end;
        end;
        if Unsupported then begin
            Ok := false;
            exit('');
        end;

        // Second pass: the core tokens.
        AdvText := Adv.ToText();
        I := 1;
        while I <= StrLen(AdvText) do begin
            E := LiteralEnd(AdvText, I);
            if E > 0 then begin
                Out.Append(MText.Substr(AdvText, I + 1, E - 1));
                I := E;
            end else
                case MText.CharAt(AdvText, I) of
                    89: // Y
                        begin
                            L := RunLength(AdvText, I, 89, 4);
                            if L = 4 then begin
                                Out.Append(PadNum(Y, 4));
                                I += 4;
                            end else
                                if L >= 2 then begin
                                    YearText := MText.IntText(Y);
                                    if StrLen(YearText) > 2 then
                                        YearText := CopyStr(YearText, StrLen(YearText) - 1);
                                    Out.Append(YearText);
                                    I += 2;
                                end else begin
                                    Out.Append('Y');
                                    I += 1;
                                end;
                        end;
                    77: // M
                        begin
                            L := RunLength(AdvText, I, 77, 4);
                            case L of
                                1:
                                    Out.Append(MText.IntText(Mo + 1));
                                2:
                                    Out.Append(PadNum(Mo + 1, 2));
                                3:
                                    Out.Append(CopyStr(MonthName(Mo), 1, 3));
                                4:
                                    Out.Append(MonthName(Mo));
                            end;
                            I += L;
                        end;
                    68: // D
                        begin
                            L := RunLength(AdvText, I, 68, 2);
                            if L = 2 then
                                Out.Append(PadNum(D, 2))
                            else
                                Out.Append(MText.IntText(D));
                            I += L;
                        end;
                    100: // d
                        begin
                            L := RunLength(AdvText, I, 100, 4);
                            case L of
                                1:
                                    Out.Append(MText.IntText(Wd));
                                2:
                                    Out.Append(CopyStr(WeekdayName(Wd), 1, 2));
                                3:
                                    Out.Append(CopyStr(WeekdayName(Wd), 1, 3));
                                4:
                                    Out.Append(WeekdayName(Wd));
                            end;
                            I += L;
                        end;
                    72: // H
                        begin
                            L := RunLength(AdvText, I, 72, 2);
                            if L = 2 then
                                Out.Append(PadNum(H, 2))
                            else
                                Out.Append(MText.IntText(H));
                            I += L;
                        end;
                    104: // h
                        begin
                            L := RunLength(AdvText, I, 104, 2);
                            H12 := H mod 12;
                            if H12 = 0 then
                                H12 := 12;
                            if L = 2 then
                                Out.Append(PadNum(H12, 2))
                            else
                                Out.Append(MText.IntText(H12));
                            I += L;
                        end;
                    97: // a
                        begin
                            if H < 12 then
                                Out.Append('am')
                            else
                                Out.Append('pm');
                            I += 1;
                        end;
                    65: // A
                        begin
                            if H < 12 then
                                Out.Append('AM')
                            else
                                Out.Append('PM');
                            I += 1;
                        end;
                    109: // m
                        begin
                            L := RunLength(AdvText, I, 109, 2);
                            if L = 2 then
                                Out.Append(PadNum(Mi, 2))
                            else
                                Out.Append(MText.IntText(Mi));
                            I += L;
                        end;
                    115: // s
                        begin
                            L := RunLength(AdvText, I, 115, 2);
                            if L = 2 then
                                Out.Append(PadNum(S, 2))
                            else
                                Out.Append(MText.IntText(S));
                            I += L;
                        end;
                    90: // Z
                        begin
                            L := RunLength(AdvText, I, 90, 2);
                            Out.Append(ZoneText(L = 1));
                            I += L;
                        end;
                    83: // S
                        if RunLength(AdvText, I, 83, 3) = 3 then begin
                            Out.Append(PadNum(Ms, 3));
                            I += 3;
                        end else begin
                            Out.Append('S');
                            I += 1;
                        end;
                    else begin
                        Out.Append(CopyStr(AdvText, I, 1));
                        I += 1;
                    end;
                end;
        end;
        exit(Out.ToText());
    end;

    local procedure IsFormatSep(C: Integer): Boolean
    begin
        exit((C = 45) or (C = 95) or (C = 58) or (C = 47) or (C = 46) or (C = 44) or (C = 40) or (C = 41) or MText.IsSpace(C));
    end;

    /// <summary>Splits a parse format into steps the way dayjs's customParseFormat does; false when dayjs fails on it.</summary>
    local procedure CompileFormat(Template: Text): Boolean
    var
        Stripped: TextBuilder;
        Tokens: List of [Text];
        Token: Text;
        I: Integer;
        J: Integer;
        K: Integer;
        E: Integer;
        C: Integer;
        L: Integer;
        N: Integer;
    begin
        if CompiledDone and (Template = CompiledFormat) then
            exit(CompiledOk);
        CompiledDone := true;
        CompiledFormat := Template;
        CompiledOk := false;
        Clear(StepReader);
        Clear(StepLiteral);
        N := StrLen(Template);

        // dayjs expands localized tokens through a locale table the English locale does not have, and fails.
        I := 1;
        while I <= N do begin
            E := LiteralEnd(Template, I);
            if E > 0 then
                I := E
            else begin
                Stripped.Append(CopyStr(Template, I, 1));
                I += 1;
            end;
        end;
        if Stripped.ToText().Contains('L') or Stripped.ToText().Contains('l') then
            exit(false);

        I := 1;
        while I <= N do begin
            C := MText.CharAt(Template, I);
            Token := '';
            if C = 91 then begin
                // \[[^[]*\]
                J := I + 1;
                K := 0;
                while (J <= N) and (MText.CharAt(Template, J) <> 91) do begin
                    if MText.CharAt(Template, J) = 93 then
                        K := J;
                    J += 1;
                end;
                if K > 0 then
                    Token := MText.Substr(Template, I, K + 1);
            end else
                if IsFormatSep(C) then begin
                    J := I;
                    while IsFormatSep(MText.CharAt(Template, J)) do
                        J += 1;
                    Token := MText.Substr(Template, I, J);
                end else
                    case C of
                        65, 97, 81, 122: // A a Q z
                            Token := CopyStr(Template, I, 1);
                        89: // YYYY|YY?
                            begin
                                L := RunLength(Template, I, 89, 4);
                                if L = 4 then
                                    Token := 'YYYY'
                                else
                                    if L >= 2 then
                                        Token := 'YY'
                                    else
                                        Token := 'Y';
                            end;
                        119: // ww?
                            Token := CopyStr(Template, I, RunLength(Template, I, 119, 2));
                        77: // MM?M?M?
                            Token := CopyStr(Template, I, RunLength(Template, I, 77, 4));
                        68: // Do|DD?
                            if MText.CharAt(Template, I + 1) = 111 then
                                Token := 'Do'
                            else
                                Token := CopyStr(Template, I, RunLength(Template, I, 68, 2));
                        104, 72, 109, 115, 90: // hh? HH? mm? ss? ZZ?
                            Token := CopyStr(Template, I, RunLength(Template, I, C, 2));
                        83: // S{1,3}
                            Token := CopyStr(Template, I, RunLength(Template, I, 83, 3));
                    end;
            if Token <> '' then begin
                Tokens.Add(Token);
                I += StrLen(Token);
            end else
                I += 1;
        end;
        if Tokens.Count() = 0 then
            exit(false);
        foreach Token in Tokens do
            if IsReader(Token) then begin
                StepReader.Add(Token);
                StepLiteral.Add('');
            end else begin
                StepReader.Add('');
                if Token.StartsWith('[') then
                    Token := CopyStr(Token, 2);
                if Token.EndsWith(']') then
                    Token := CopyStr(Token, 1, StrLen(Token) - 1);
                StepLiteral.Add(Token);
            end;
        CompiledOk := true;
        exit(true);
    end;

    local procedure IsReader(Token: Text): Boolean
    begin
        case Token of
            'A', 'a', 'Q', 'S', 'SS', 'SSS', 's', 'ss', 'm', 'mm', 'H', 'h', 'HH', 'hh', 'D', 'DD', 'Do', 'w', 'ww',
            'M', 'MM', 'MMM', 'MMMM', 'Y', 'YY', 'YYYY', 'Z', 'ZZ':
                exit(true);
        end;
        exit(false);
    end;

    /// <summary>The pattern a reader matches: 1 \d, 2 \d\d, 3 \d{3}, 4 \d{4}, 5 \d\d?, 6 [+-]?\d+, 7 an offset, 8 a word.</summary>
    local procedure ReaderPattern(Token: Text): Integer
    begin
        case Token of
            'A', 'a', 'Do', 'MMM', 'MMMM':
                exit(8);
            'Q', 'S':
                exit(1);
            'SS', 'DD', 'MM', 'ww', 'YY':
                exit(2);
            'SSS':
                exit(3);
            'YYYY':
                exit(4);
            'Y':
                exit(6);
            'Z', 'ZZ':
                exit(7);
        end;
        exit(5);
    end;

    local procedure IsWordClass(C: Integer): Boolean
    begin
        // [^-_:/,()\s\d]
        if (C = -1) or MText.IsDigit(C) or MText.IsSpace(C) then
            exit(false);
        exit(not ((C = 45) or (C = 95) or (C = 58) or (C = 47) or (C = 44) or (C = 40) or (C = 41)));
    end;

    local procedure DigitRun(Str: Text; P: Integer): Integer
    var
        L: Integer;
    begin
        while MText.IsDigit(MText.CharAt(Str, P + L)) do
            L += 1;
        exit(L);
    end;

    local procedure MatchAt(Pattern: Integer; Str: Text; P: Integer): Integer
    var
        C: Integer;
        L: Integer;
        K: Integer;
    begin
        C := MText.CharAt(Str, P);
        case Pattern of
            1, 2, 3, 4:
                if DigitRun(Str, P) >= Pattern then
                    exit(Pattern);
            5:
                begin
                    L := DigitRun(Str, P);
                    if L > 2 then
                        L := 2;
                    exit(L);
                end;
            6:
                begin
                    K := 0;
                    if (C = 43) or (C = 45) then
                        K := 1;
                    L := DigitRun(Str, P + K);
                    if L > 0 then
                        exit(K + L);
                end;
            7:
                begin
                    if ((C = 43) or (C = 45)) and (DigitRun(Str, P + 1) >= 2) then begin
                        L := 3;
                        if MText.CharAt(Str, P + 3) = 58 then
                            L := 4;
                        if DigitRun(Str, P + L) >= 2 then
                            L += 2;
                        exit(L);
                    end;
                    if C = 90 then
                        exit(1);
                end;
            8:
                begin
                    K := DigitRun(Str, P);
                    L := 0;
                    while IsWordClass(MText.CharAt(Str, P + K + L)) do
                        L += 1;
                    if L > 0 then
                        exit(K + L);
                end;
        end;
        exit(0);
    end;

    /// <summary>The first match of a reader's pattern anywhere in the text.</summary>
    local procedure SearchPattern(Pattern: Integer; Str: Text; var Found: Text): Boolean
    var
        P: Integer;
        L: Integer;
    begin
        for P := 1 to StrLen(Str) do begin
            L := MatchAt(Pattern, Str, P);
            if L > 0 then begin
                Found := CopyStr(Str, P, L);
                exit(true);
            end;
        end;
        exit(false);
    end;

    /// <summary>+input for a run of digits with an optional sign; very long numbers are capped.</summary>
    local procedure NumOf(Value: Text): Decimal
    var
        Result: Decimal;
        I: Integer;
        Negative: Boolean;
        C: Integer;
    begin
        I := 1;
        if CopyStr(Value, 1, 1) = '-' then begin
            Negative := true;
            I := 2;
        end else
            if CopyStr(Value, 1, 1) = '+' then
                I := 2;
        while I <= StrLen(Value) do begin
            C := Value[I];
            if MText.IsDigit(C) then
                if Result < 100000000000000000000.0 then
                    Result := Result * 10 + (C - 48);
            I += 1;
        end;
        if Negative then
            exit(-Result);
        exit(Result);
    end;

    local procedure ResetFields()
    begin
        FYear := 0;
        FMonth := 0;
        FDay := 0;
        FHours := 0;
        FMinutes := 0;
        FSeconds := 0;
        FMs := 0;
        FWeek := 0;
        FOffset := 0;
        FAfternoon := false;
        HasYear := false;
        HasMonth := false;
        HasDay := false;
        DayGiven := false;
        HasHours := false;
        HasMinutes := false;
        HasSeconds := false;
        HasMs := false;
        HasWeek := false;
        HasOffset := false;
        HasAfternoon := false;
    end;

    local procedure ReadField(Token: Text; Input: Text): Boolean
    var
        Value: Decimal;
        I: Integer;
        J: Integer;
        Names: Text;
    begin
        case Token of
            'A':
                begin
                    FAfternoon := Input = 'PM';
                    HasAfternoon := true;
                end;
            'a':
                begin
                    FAfternoon := Input = 'pm';
                    HasAfternoon := true;
                end;
            'Q':
                begin
                    FMonth := (NumOf(Input) - 1) * 3 + 1;
                    HasMonth := true;
                end;
            'S', 'SS', 'SSS':
                begin
                    case Token of
                        'S':
                            FMs := NumOf(Input) * 100;
                        'SS':
                            FMs := NumOf(Input) * 10;
                        else
                            FMs := NumOf(Input);
                    end;
                    HasMs := true;
                end;
            's', 'ss':
                begin
                    FSeconds := NumOf(Input);
                    HasSeconds := true;
                end;
            'm', 'mm':
                begin
                    FMinutes := NumOf(Input);
                    HasMinutes := true;
                end;
            'H', 'h', 'HH', 'hh':
                begin
                    FHours := NumOf(Input);
                    HasHours := true;
                end;
            'D', 'DD':
                begin
                    FDay := NumOf(Input);
                    HasDay := true;
                end;
            'Do':
                begin
                    I := 1;
                    while (I <= StrLen(Input)) and not MText.IsDigit(MText.CharAt(Input, I)) do
                        I += 1;
                    if I > StrLen(Input) then
                        exit(false);
                    J := I;
                    while MText.IsDigit(MText.CharAt(Input, J)) do
                        J += 1;
                    // dayjs keeps the digits as a string here, so even "0" counts as a day having been given.
                    FDay := NumOf(MText.Substr(Input, I, J));
                    HasDay := true;
                    DayGiven := true;
                    for I := 1 to 31 do
                        if Ordinal(I) = Input then
                            FDay := I;
                end;
            'w', 'ww':
                begin
                    FWeek := NumOf(Input);
                    HasWeek := true;
                end;
            'M', 'MM':
                begin
                    FMonth := NumOf(Input);
                    HasMonth := true;
                end;
            'MMM', 'MMMM':
                begin
                    for I := 0 to 11 do begin
                        Names := MonthName(I);
                        if Token = 'MMM' then
                            Names := CopyStr(Names, 1, 3);
                        if (Value = 0) and (Names = Input) then
                            Value := I + 1;
                    end;
                    if Value < 1 then
                        exit(false);
                    FMonth := Value;
                    HasMonth := true;
                end;
            'Y', 'YYYY':
                begin
                    FYear := NumOf(Input);
                    HasYear := true;
                end;
            'YY':
                begin
                    Value := NumOf(Input);
                    if Value > 68 then
                        FYear := Value + 1900
                    else
                        FYear := Value + 2000;
                    HasYear := true;
                end;
            'Z', 'ZZ':
                begin
                    ReadOffset(Input);
                    HasOffset := true;
                end;
        end;
        exit(true);
    end;

    local procedure ReadOffset(Input: Text)
    var
        Parts2: List of [Text];
        I: Integer;
        C: Integer;
        Minutes: Decimal;
    begin
        if Input = 'Z' then begin
            FOffset := 0;
            exit;
        end;
        // input.match(/([+-]|\d\d)/g)
        I := 1;
        while I <= StrLen(Input) do begin
            C := Input[I];
            if (C = 43) or (C = 45) then begin
                Parts2.Add(CopyStr(Input, I, 1));
                I += 1;
            end else
                if MText.IsDigit(C) and MText.IsDigit(MText.CharAt(Input, I + 1)) then begin
                    Parts2.Add(CopyStr(Input, I, 2));
                    I += 2;
                end else
                    I += 1;
        end;
        if Parts2.Count() < 2 then begin
            FOffset := 0;
            exit;
        end;
        Minutes := NumOf(Parts2.Get(2)) * 60;
        if Parts2.Count() >= 3 then
            Minutes += NumOf(Parts2.Get(3));
        if Minutes = 0 then
            FOffset := 0
        else
            if Parts2.Get(1) = '+' then
                FOffset := -Minutes
            else
                FOffset := Minutes;
    end;

    local procedure IsCanonicalInt(Value: Text): Boolean
    var
        Digits: Text;
    begin
        if Value = '0' then
            exit(true);
        Digits := Value;
        if Digits.StartsWith('-') then
            Digits := CopyStr(Digits, 2);
        if (Digits = '') or (StrLen(Digits) > 17) then
            exit(false);
        if not IsAllDigits(Digits) then
            exit(false);
        exit(CopyStr(Digits, 1, 1) <> '0');
    end;

    /// <summary>dayjs's loose parse against a format, with its quirks; NaNT() when it fails.</summary>
    local procedure LooseParse(Input: Text; Template: Text; NowT: BigInteger): BigInteger
    var
        Rest: Text;
        Sub: Text;
        Found: Text;
        Reader: Text;
        StartOff: Integer;
        K: Integer;
        P: Integer;
        Value: Decimal;
        DayV: Decimal;
        YearV: Decimal;
        MonthV: Decimal;
        YearTruthy: Boolean;
        MonthTruthy: Boolean;
    begin
        if (Template = 'x') or (Template = 'X') then begin
            // Only a canonical integer can survive the strict round trip through format.
            if not IsCanonicalInt(Input) then
                exit(NaNT());
            Value := NumOf(Input);
            if Template = 'X' then
                Value := Value * 1000;
            exit(ClipT(Value));
        end;
        if not CompileFormat(Template) then
            exit(NaNT());
        ResetFields();
        Rest := Input;
        StartOff := 0;
        for K := 1 to StepReader.Count() do begin
            Reader := StepReader.Get(K);
            if Reader = '' then
                StartOff += StrLen(StepLiteral.Get(K))
            else begin
                Sub := MText.Substr(Rest, StartOff + 1, StrLen(Rest) + 1);
                if not SearchPattern(ReaderPattern(Reader), Sub, Found) then
                    exit(NaNT());
                if not ReadField(Reader, Found) then
                    exit(NaNT());
                // dayjs drops the first occurrence of the matched text, wherever it is, and does not move the start.
                P := StrPos(Rest, Found);
                if P > 0 then
                    Rest := CopyStr(Rest, 1, P - 1) + CopyStr(Rest, P + StrLen(Found));
            end;
        end;
        if HasAfternoon and HasHours then
            if FAfternoon then begin
                if FHours < 12 then
                    FHours += 12;
            end else
                if FHours = 12 then
                    FHours := 0;
        YearTruthy := HasYear and (FYear <> 0);
        MonthTruthy := HasMonth and (FMonth <> 0);
        if DayGiven or (HasDay and (FDay <> 0)) then
            DayV := FDay
        else
            if (not YearTruthy) and (not MonthTruthy) then
                DayV := TDate(NowT)
            else
                DayV := 1;
        if YearTruthy then
            YearV := FYear
        else
            YearV := TYear(NowT);
        MonthV := 0;
        if not (YearTruthy and not MonthTruthy) then
            if HasMonth and (FMonth > 0) then
                MonthV := FMonth - 1
            else
                MonthV := TMonth(NowT);
        // The Date constructor reads years 0 to 99 as 1900 to 1999.
        if (TruncDec(YearV) >= 0) and (TruncDec(YearV) <= 99) then
            YearV := 1900 + TruncDec(YearV);
        if HasOffset then
            exit(MakeT(YearV, MonthV, DayV, FHours, FMinutes, FSeconds, FMs + FOffset * 60000));
        // Applying a week number needs a dayjs plugin Mermaid does not load.
        if HasWeek and (FWeek <> 0) then
            exit(NaNT());
        exit(MakeT(YearV, MonthV, DayV, FHours, FMinutes, FSeconds, FMs));
    end;

    /// <summary>dayjs(input, format, true): a date is accepted only when formatting it gives back the input.</summary>
    local procedure ParseStrict(Input: Text; Template: Text; NowT: BigInteger): BigInteger
    var
        T: BigInteger;
        Ok: Boolean;
        Formatted: Text;
    begin
        T := LooseParse(Input, Template, NowT);
        if not IsValidT(T) then
            exit(NaNT());
        Formatted := FormatT(T, Template, Ok);
        if Ok and (Formatted = Input) then
            exit(T);
        exit(NaNT());
    end;

    // ================================================================ the JavaScript date parser (new Date(text))

    local procedure JsDateParse(Str: Text): BigInteger
    var
        T: BigInteger;
    begin
        case IsoDateParse(Str, T) of
            1:
                exit(T);
            2:
                exit(NaNT());
        end;
        exit(LegacyDateParse(Str));
    end;

    local procedure FixedDigits(Str: Text; P: Integer; Len: Integer; var Value: Integer): Boolean
    var
        I: Integer;
    begin
        Value := 0;
        for I := 0 to Len - 1 do begin
            if not MText.IsDigit(MText.CharAt(Str, P + I)) then
                exit(false);
            if Value < 100000000 then
                Value := Value * 10 + MText.CharAt(Str, P + I) - 48;
        end;
        exit(true);
    end;

    /// <summary>The ECMAScript date time string format: 0 when the text is not in it, 1 parsed, 2 out of range.</summary>
    local procedure IsoDateParse(Str: Text; var T: BigInteger): Integer
    var
        P: Integer;
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        OffH: Integer;
        OffM: Integer;
        Sign: Integer;
        Frac: Integer;
        Digits: Integer;
        C: Integer;
        HasOff: Boolean;
        OffSign: Integer;
    begin
        P := 1;
        Mo := 1;
        D := 1;
        C := MText.CharAt(Str, 1);
        if (C = 43) or (C = 45) then begin
            Sign := 1;
            if C = 45 then
                Sign := -1;
            if not FixedDigits(Str, 2, 6, Y) then
                exit(0);
            if (Sign = -1) and (Y = 0) then
                exit(2);
            Y := Sign * Y;
            P := 8;
        end else begin
            if not FixedDigits(Str, 1, 4, Y) then
                exit(0);
            P := 5;
        end;
        if MText.CharAt(Str, P) = 45 then begin
            if not FixedDigits(Str, P + 1, 2, Mo) then
                exit(0);
            P += 3;
            if MText.CharAt(Str, P) = 45 then begin
                if not FixedDigits(Str, P + 1, 2, D) then
                    exit(0);
                P += 3;
            end;
        end;
        if MText.CharAt(Str, P) = 84 then begin
            if not FixedDigits(Str, P + 1, 2, H) then
                exit(0);
            if MText.CharAt(Str, P + 3) <> 58 then
                exit(0);
            if not FixedDigits(Str, P + 4, 2, Mi) then
                exit(0);
            P += 6;
            if MText.CharAt(Str, P) = 58 then begin
                if not FixedDigits(Str, P + 1, 2, S) then
                    exit(0);
                P += 3;
                if MText.CharAt(Str, P) = 46 then begin
                    P += 1;
                    Digits := 0;
                    while MText.IsDigit(MText.CharAt(Str, P)) do begin
                        if Digits < 3 then
                            Frac := Frac * 10 + MText.CharAt(Str, P) - 48;
                        Digits += 1;
                        P += 1;
                    end;
                    if Digits = 0 then
                        exit(0);
                    while Digits < 3 do begin
                        Frac := Frac * 10;
                        Digits += 1;
                    end;
                    Ms := Frac;
                end;
            end;
            C := MText.CharAt(Str, P);
            if C = 90 then begin
                HasOff := true;
                P += 1;
            end else
                if (C = 43) or (C = 45) then begin
                    OffSign := 1;
                    if C = 45 then
                        OffSign := -1;
                    if not FixedDigits(Str, P + 1, 2, OffH) then
                        exit(0);
                    if MText.CharAt(Str, P + 3) <> 58 then
                        exit(0);
                    if not FixedDigits(Str, P + 4, 2, OffM) then
                        exit(0);
                    HasOff := true;
                    P += 6;
                end;
        end;
        if P <> StrLen(Str) + 1 then
            exit(0);
        if (Mo < 1) or (Mo > 12) or (D < 1) or (D > DaysInMonth(Y, Mo)) or (H > 24) or (Mi > 59) or (S > 59) then
            exit(2);
        if (H = 24) and ((Mi <> 0) or (S <> 0) or (Ms <> 0)) then
            exit(2);
        if (OffH > 23) or (OffM > 59) then
            exit(2);
        T := MakeT(Y, Mo - 1, D, H, Mi, S, Ms);
        if HasOff and IsValidT(T) then
            T := AddMsT(T, -OffSign * (OffH * 60 + OffM) * 60000);
        if not IsValidT(T) then
            exit(2);
        exit(1);
    end;

    local procedure MonthPrefix(Word: Text): Integer
    var
        I: Integer;
    begin
        if StrLen(Word) < 3 then
            exit(0);
        for I := 0 to 11 do
            if LowerCase(CopyStr(MonthName(I), 1, 3)) = CopyStr(Word, 1, 3) then
                exit(I + 1);
        exit(0);
    end;

    local procedure WeekdayPrefix(Word: Text): Boolean
    var
        I: Integer;
    begin
        if StrLen(Word) < 3 then
            exit(false);
        for I := 0 to 6 do
            if LowerCase(CopyStr(WeekdayName(I), 1, 3)) = CopyStr(Word, 1, 3) then
                exit(true);
        exit(false);
    end;

    /// <summary>An approximation of V8's legacy date parser: month names, numeric dates, times, AM/PM and offsets.</summary>
    local procedure LegacyDateParse(Str: Text): BigInteger
    var
        Nums: List of [Integer];
        NumLens: List of [Integer];
        Word: Text;
        N: Integer;
        I: Integer;
        J: Integer;
        C: Integer;
        V: Integer;
        Len: Integer;
        NamedMonth: Integer;
        Hour: Integer;
        Minute: Integer;
        Second: Integer;
        Milli: Integer;
        HasTime: Boolean;
        AmPm: Integer;
        HasTz: Boolean;
        TzMinutes: Integer;
        LastSign: Integer;
        Y: Integer;
        Mo: Integer;
        D: Integer;
        YearLen: Integer;
        T: BigInteger;
    begin
        N := StrLen(Str);
        I := 1;
        while I <= N do begin
            C := MText.CharAt(Str, I);
            if MText.IsDigit(C) then begin
                J := I;
                V := 0;
                while MText.IsDigit(MText.CharAt(Str, J)) do begin
                    if V < 100000000 then
                        V := V * 10 + MText.CharAt(Str, J) - 48;
                    J += 1;
                end;
                Len := J - I;
                if (MText.CharAt(Str, J) = 58) and not HasTime then begin
                    Hour := V;
                    HasTime := true;
                    if not FixedDigits(Str, J + 1, 2, Minute) then
                        if not FixedDigits(Str, J + 1, 1, Minute) then
                            exit(NaNT());
                    J += 1 + DigitRun(Str, J + 1);
                    if MText.CharAt(Str, J) = 58 then begin
                        if DigitRun(Str, J + 1) = 0 then
                            exit(NaNT());
                        FixedDigits(Str, J + 1, DigitRun(Str, J + 1), Second);
                        J += 1 + DigitRun(Str, J + 1);
                        if (MText.CharAt(Str, J) = 46) and (DigitRun(Str, J + 1) > 0) then begin
                            Len := DigitRun(Str, J + 1);
                            if Len > 3 then
                                Len := 3;
                            FixedDigits(Str, J + 1, Len, Milli);
                            while Len < 3 do begin
                                Milli := Milli * 10;
                                Len += 1;
                            end;
                            J += 1 + DigitRun(Str, J + 1);
                        end;
                    end;
                end else
                    if (LastSign <> 0) and (HasTime or HasTz) then begin
                        if Len <= 2 then begin
                            TzMinutes := V * 60;
                            if (MText.CharAt(Str, J) = 58) and (DigitRun(Str, J + 1) = 2) then begin
                                FixedDigits(Str, J + 1, 2, V);
                                TzMinutes += V;
                                J += 3;
                            end;
                        end else
                            TzMinutes := (V div 100) * 60 + V mod 100;
                        TzMinutes := TzMinutes * LastSign;
                        HasTz := true;
                    end else begin
                        Nums.Add(V);
                        NumLens.Add(Len);
                    end;
                LastSign := 0;
                I := J;
            end else
                if MText.IsLetter(C) then begin
                    J := I;
                    while MText.IsLetter(MText.CharAt(Str, J)) do
                        J += 1;
                    Word := LowerCase(MText.Substr(Str, I, J));
                    if (Word = 'am') or (Word = 'pm') then begin
                        if Word = 'am' then
                            AmPm := 1
                        else
                            AmPm := 2;
                    end else
                        if (Word = 'z') or (Word = 'utc') or (Word = 'gmt') or (Word = 'ut') then begin
                            HasTz := true;
                            TzMinutes := 0;
                        end else
                            if (Word = 't') and MText.IsDigit(MText.CharAt(Str, J)) then
                                ;
                    if not ((Word = 'am') or (Word = 'pm') or (Word = 'z') or (Word = 'utc') or (Word = 'gmt') or (Word = 'ut') or (Word = 't')) then
                        if MonthPrefix(Word) > 0 then
                            NamedMonth := MonthPrefix(Word)
                        else
                            if not WeekdayPrefix(Word) then
                                // Unknown words are skipped before the first number, and fail after it.
                                if (Nums.Count() > 0) or HasTime then
                                    exit(NaNT());
                    LastSign := 0;
                    I := J;
                end else begin
                    if C = 40 then begin
                        J := I;
                        while (J <= N) and (MText.CharAt(Str, J) <> 41) do
                            J += 1;
                        I := J;
                    end;
                    if C = 43 then
                        LastSign := 1
                    else
                        if C = 45 then
                            LastSign := -1
                        else
                            LastSign := 0;
                    I += 1;
                end;
        end;

        if Nums.Count() > 3 then
            exit(NaNT());
        if NamedMonth > 0 then begin
            Mo := NamedMonth;
            case Nums.Count() of
                1:
                    if Nums.Get(1) > 31 then begin
                        Y := Nums.Get(1);
                        YearLen := NumLens.Get(1);
                        D := 1;
                    end else begin
                        D := Nums.Get(1);
                        Y := 2001;
                        YearLen := 4;
                    end;
                2:
                    if (Nums.Get(1) > 31) or (NumLens.Get(1) >= 3) then begin
                        Y := Nums.Get(1);
                        YearLen := NumLens.Get(1);
                        D := Nums.Get(2);
                    end else begin
                        D := Nums.Get(1);
                        Y := Nums.Get(2);
                        YearLen := NumLens.Get(2);
                    end;
                else
                    exit(NaNT());
            end;
        end else
            case Nums.Count() of
                2:
                    if (Nums.Get(1) > 31) or (NumLens.Get(1) >= 3) then begin
                        Y := Nums.Get(1);
                        YearLen := NumLens.Get(1);
                        Mo := Nums.Get(2);
                        D := 1;
                    end else begin
                        Mo := Nums.Get(1);
                        D := Nums.Get(2);
                        Y := 2001;
                        YearLen := 4;
                    end;
                3:
                    if (Nums.Get(1) > 31) or (NumLens.Get(1) >= 3) then begin
                        Y := Nums.Get(1);
                        YearLen := NumLens.Get(1);
                        Mo := Nums.Get(2);
                        D := Nums.Get(3);
                    end else begin
                        Mo := Nums.Get(1);
                        D := Nums.Get(2);
                        Y := Nums.Get(3);
                        YearLen := NumLens.Get(3);
                    end;
                else
                    exit(NaNT());
            end;
        if (YearLen <= 2) and (Y < 100) then
            if Y < 50 then
                Y += 2000
            else
                Y += 1900;
        if (Mo < 1) or (Mo > 12) or (D < 1) or (D > DaysInMonth(Y, Mo)) then
            exit(NaNT());
        if AmPm > 0 then begin
            if Hour > 12 then
                exit(NaNT());
            Hour := Hour mod 12;
            if AmPm = 2 then
                Hour += 12;
        end;
        if (Hour > 24) or (Minute > 59) or (Second > 59) then
            exit(NaNT());
        T := MakeT(Y, Mo - 1, D, Hour, Minute, Second, Milli);
        if HasTz then
            T := AddMsT(T, -TzMinutes * 60000.0);
        exit(T);
    end;

    // ================================================================ d3 time axis (axis.ts)

    local procedure UnitMs(TickUnit: Integer): BigInteger
    begin
        case TickUnit of
            0:
                exit(1);
            1:
                exit(1000);
            2:
                exit(60000);
            3:
                exit(3600000);
            4:
                exit(DayMs());
            5:
                exit(WeekMs());
            6:
                exit(30 * DayMs());
        end;
        exit(365 * DayMs());
    end;

    /// <summary>How many values a unit's field cycles through; 0 for none.</summary>
    local procedure UnitCycle(TickUnit: Integer): Integer
    begin
        case TickUnit of
            1, 2:
                exit(60);
            3:
                exit(24);
            4:
                exit(31);
            6:
                exit(12);
        end;
        exit(0);
    end;

    local procedure WeekFloor(T: BigInteger; WeekStart: Integer): BigInteger
    begin
        if not IsValidT(T) then
            exit(NaNT());
        exit(StartOfDay(AddDaysT(T, -((TDay(T) + 7 - WeekStart) mod 7))));
    end;

    local procedure FloorYear(T: BigInteger): BigInteger
    begin
        if not IsValidT(T) then
            exit(NaNT());
        exit(MakeT(TYear(T), 0, 1, 0, 0, 0, 0));
    end;

    local procedure BaseFloor(TickUnit: Integer; WeekStart: Integer; T: BigInteger): BigInteger
    begin
        if not IsValidT(T) then
            exit(NaNT());
        case TickUnit of
            0:
                exit(T);
            1:
                exit(T - PosModB(T, 1000));
            2:
                exit(T - PosModB(T, 60000));
            3:
                exit(T - PosModB(T, 3600000));
            4:
                exit(StartOfDay(T));
            5:
                exit(WeekFloor(T, WeekStart));
            6:
                exit(MakeT(TYear(T), TMonth(T), 1, 0, 0, 0, 0));
        end;
        exit(FloorYear(T));
    end;

    local procedure BaseOffset(TickUnit: Integer; T: BigInteger; Step: Decimal): BigInteger
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
    begin
        if not IsValidT(T) then
            exit(NaNT());
        case TickUnit of
            0:
                exit(AddMsT(T, Step));
            1:
                exit(AddMsT(T, Step * 1000));
            2:
                exit(AddMsT(T, Step * 60000));
            3:
                exit(AddMsT(T, Step * 3600000));
            4:
                exit(AddDaysT(T, Step));
            5:
                exit(AddDaysT(T, Step * 7));
        end;
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        if TickUnit = 6 then
            exit(MakeT(Y, Mo + Step, D, H, Mi, S, Ms));
        exit(MakeT(Y + Step, Mo, D, H, Mi, S, Ms));
    end;

    local procedure CalField(TickUnit: Integer; T: BigInteger): Integer
    begin
        case TickUnit of
            1:
                exit(TSeconds(T));
            2:
                exit(TMinutes(T));
            3:
                exit(THours(T));
            4:
                exit(TDate(T) - 1);
            6:
                exit(TMonth(T));
        end;
        exit(0);
    end;

    local procedure CalTest(T: BigInteger): Boolean
    var
        F: Decimal;
    begin
        F := CalField(CalUnit, T);
        exit(F - FloorDec(F / CalStep) * CalStep = 0);
    end;

    /// <summary>Selects the interval d3's unit.every(step) gives.</summary>
    local procedure SetCalendar(TickUnit: Integer; Step: Decimal; WeekStart: Integer)
    begin
        CalUnit := TickUnit;
        CalStep := Step;
        CalWeekStart := WeekStart;
    end;

    local procedure CalFloor(T: BigInteger): BigInteger
    var
        D: BigInteger;
        Epoch: BigInteger;
        Weeks: Decimal;
    begin
        if not IsValidT(T) then
            exit(NaNT());
        if CalStep <= 1 then
            exit(BaseFloor(CalUnit, CalWeekStart, T));
        case CalUnit of
            0:
                exit(ClipT(FloorDec(T / CalStep) * CalStep));
            7:
                exit(MakeT(FloorDec(TYear(T) / CalStep) * CalStep, 0, 1, 0, 0, 0, 0));
            5:
                begin
                    D := BaseFloor(5, CalWeekStart, T);
                    Epoch := BaseFloor(5, CalWeekStart, 0);
                    Weeks := FloorDivB(D - Epoch, WeekMs());
                    exit(BaseOffset(5, D, -(Weeks - FloorDec(Weeks / CalStep) * CalStep)));
                end;
        end;
        // Date overflow ends the search, as NaN can never match the interval.
        D := BaseFloor(CalUnit, CalWeekStart, T);
        while IsValidT(D) and not CalTest(D) do
            D := BaseFloor(CalUnit, CalWeekStart, D - 1);
        exit(D);
    end;

    local procedure CalOffset(T: BigInteger; N: Integer): BigInteger
    var
        D: BigInteger;
        I: Integer;
    begin
        if CalStep <= 1 then
            exit(BaseOffset(CalUnit, T, N));
        case CalUnit of
            0, 5, 7:
                exit(BaseOffset(CalUnit, T, N * CalStep));
        end;
        D := T;
        I := 0;
        while (I < N) and IsValidT(D) do begin
            repeat
                D := BaseOffset(CalUnit, D, 1);
            until (not IsValidT(D)) or CalTest(D);
            I += 1;
        end;
        exit(D);
    end;

    /// <summary>Ticks from start to stop inclusive; false when there would be more than the limit.</summary>
    local procedure TickRange(StartT: BigInteger; StopT: BigInteger; Limit: Decimal; var Ticks: List of [BigInteger]): Boolean
    var
        D: BigInteger;
        Previous: BigInteger;
        HasPrevious: Boolean;
        Going: Boolean;
    begin
        Clear(Ticks);
        D := CalFloor(StartT - 1);
        D := CalOffset(D, 1);
        D := CalFloor(D);
        Going := true;
        while Going do begin
            Going := IsValidT(D) and (D <= StopT);
            if Going and HasPrevious then
                Going := D > Previous;
            if Going then begin
                if Ticks.Count() >= Limit then
                    exit(false);
                Previous := D;
                HasPrevious := true;
                Ticks.Add(D);
                D := CalOffset(D, 1);
                D := CalFloor(D);
            end;
        end;
        exit(true);
    end;

    local procedure Pow10(Power: Integer): Decimal
    var
        Result: Decimal;
        I: Integer;
    begin
        Result := 1;
        if Power >= 0 then
            for I := 1 to Power do
                Result := Result * 10
        else
            for I := 1 to -Power do
                Result := Result / 10;
        exit(Result);
    end;

    local procedure TickStep(StartV: Decimal; StopV: Decimal; TickCount: Integer): Decimal
    var
        Step: Decimal;
        Power: Integer;
        Err: Decimal;
        Factor: Decimal;
    begin
        if TickCount <= 0 then
            exit(0);
        Step := (StopV - StartV) / TickCount;
        if Step <= 0 then
            exit(0);
        // floor(log10(step))
        Power := 0;
        while Pow10(Power + 1) <= Step do
            Power += 1;
        while Pow10(Power) > Step do
            Power -= 1;
        Err := Step / Pow10(Power);
        Factor := 1;
        if Err >= 7.0710678118654755 then
            Factor := 10
        else
            if Err >= 3.1622776601683795 then
                Factor := 5
            else
                if Err >= 1.4142135623730951 then
                    Factor := 2;
        exit(Pow10(Power) * Factor);
    end;

    local procedure AutoUnit(I: Integer): Integer
    begin
        case I of
            1 .. 4:
                exit(1);
            5 .. 8:
                exit(2);
            9 .. 12:
                exit(3);
            13, 14:
                exit(4);
            15:
                exit(5);
            16, 17:
                exit(6);
        end;
        exit(7);
    end;

    local procedure AutoStep(I: Integer): Integer
    begin
        case I of
            1, 5, 9, 13, 15, 16, 18:
                exit(1);
            2, 6:
                exit(5);
            3, 7:
                exit(15);
            4, 8:
                exit(30);
            10, 17:
                exit(3);
            11:
                exit(6);
            12:
                exit(12);
            14:
                exit(2);
        end;
        exit(1);
    end;

    local procedure AutoMs(I: Integer): Decimal
    var
        Value: Decimal;
    begin
        if (I < 1) or (I > 18) then
            exit(1000000000000000000000.0);
        Value := UnitMs(AutoUnit(I));
        exit(Value * AutoStep(I));
    end;

    /// <summary>About Count ticks at round times, chosen the way d3's time scale chooses them.</summary>
    local procedure AutoTicks(StartT: BigInteger; StopT: BigInteger; TickCount: Integer; var Ticks: List of [BigInteger])
    var
        Target: Decimal;
        Span: Decimal;
        YearMs: Decimal;
        Step: Decimal;
        I: Integer;
        K: Integer;
    begin
        Span := StopT - StartT;
        Target := Span / TickCount;
        I := 1;
        while (I <= 18) and (AutoMs(I) <= Target) do
            I += 1;
        if I = 19 then begin
            YearMs := UnitMs(7);
            Step := TickStep(StartT / YearMs, StopT / YearMs, TickCount);
            if Step < 1 then
                Step := 1;
            SetCalendar(7, Step, 0);
        end else
            if I = 1 then begin
                Step := TickStep(StartT, StopT, TickCount);
                if Step < 1 then
                    Step := 1;
                SetCalendar(0, Step, 0);
            end else begin
                if Target / AutoMs(I - 1) < AutoMs(I) / Target then
                    K := I - 1
                else
                    K := I;
                SetCalendar(AutoUnit(K), AutoStep(K), 0);
            end;
        if not TickRange(StartT, StopT, 4 * TickCount + 8, Ticks) then
            Clear(Ticks);
    end;

    /// <summary>Ticks for a tickInterval such as 1week; false when it is not one or asks for more than the limit.</summary>
    local procedure IntervalTicks(Interval: Text; Weekday: Text; StartT: BigInteger; StopT: BigInteger; Limit: Decimal; var Ticks: List of [BigInteger]): Boolean
    var
        P: Integer;
        Step: Decimal;
        UnitName: Text;
        TickUnit: Integer;
        WeekStart: Integer;
        Day: Integer;
        Least: Decimal;
        Span: Decimal;
    begin
        P := 1;
        if not ((MText.CharAt(Interval, 1) >= 49) and (MText.CharAt(Interval, 1) <= 57)) then
            exit(false);
        while MText.IsDigit(MText.CharAt(Interval, P)) do
            P += 1;
        if P > 19 then
            Step := 1000000000000000000.0
        else
            Step := NumOf(MText.Substr(Interval, 1, P));
        UnitName := CopyStr(Interval, P);
        case UnitName of
            'millisecond':
                TickUnit := 0;
            'second':
                TickUnit := 1;
            'minute':
                TickUnit := 2;
            'hour':
                TickUnit := 3;
            'day':
                TickUnit := 4;
            'week':
                TickUnit := 5;
            'month':
                TickUnit := 6;
            else
                exit(false);
        end;
        WeekStart := 0;
        for Day := 0 to 6 do
            if LowerCase(WeekdayName(Day)) = Weekday then
                WeekStart := Day;
        SetCalendar(TickUnit, Step, WeekStart);
        Least := Step;
        if UnitCycle(TickUnit) > 0 then
            if UnitCycle(TickUnit) < Least then
                Least := UnitCycle(TickUnit);
        Span := StopT - StartT;
        if Span / (Least * UnitMs(TickUnit)) > Limit then
            exit(false);
        exit(TickRange(StartT, StopT, Limit, Ticks));
    end;

    local procedure PadD3(Value: BigInteger; Fill: Text; Width: Integer): Text
    var
        Sign: Text;
        Digits: Text;
    begin
        if Value < 0 then begin
            Sign := '-';
            Value := -Value;
        end;
        Digits := BigText(Value);
        if StrLen(Digits) < Width then
            Digits := MText.RepeatText(Fill, Width - StrLen(Digits)) + Digits;
        exit(Sign + Digits);
    end;

    local procedure SpanUnits(A: BigInteger; B: BigInteger; Unit: BigInteger): BigInteger
    begin
        exit(FloorDivB(B - A, Unit));
    end;

    /// <summary>Weeks since the last WeekStart day before the year began, which is d3's %U and %W.</summary>
    local procedure WeekOfYear(T: BigInteger; WeekStart: Integer): BigInteger
    var
        YearStart: BigInteger;
    begin
        YearStart := FloorYear(T);
        exit(SpanUnits(WeekFloor(YearStart - 1, WeekStart), WeekFloor(T, WeekStart), WeekMs()));
    end;

    /// <summary>The Thursday that decides which ISO week and ISO year a date belongs to.</summary>
    local procedure IsoThursday(T: BigInteger): BigInteger
    var
        Day: Integer;
    begin
        Day := TDay(T);
        if (Day >= 4) or (Day = 0) then
            exit(WeekFloor(T, 4));
        exit(StartOfDay(AddDaysT(WeekFloor(T - 1, 4), 7)));
    end;

    local procedure CharStr(Value: Text; P: Integer): Text
    begin
        if (P < 1) or (P > StrLen(Value)) then
            exit('');
        exit(CopyStr(Value, P, 1));
    end;

    /// <summary>Formats a date with a d3 time format specifier such as %Y-%m-%d.</summary>
    local procedure TimeFormat(Spec: Text; T: BigInteger): Text
    var
        Out: TextBuilder;
        I: Integer;
        FromPos: Integer;
        C: Text;
        Fill: Text;
    begin
        FromPos := 1;
        I := 1;
        while I <= StrLen(Spec) do begin
            if MText.CharAt(Spec, I) = 37 then begin
                Out.Append(MText.Substr(Spec, FromPos, I));
                I += 1;
                C := CharStr(Spec, I);
                if (C = '-') or (C = '_') or (C = '0') then begin
                    case C of
                        '-':
                            Fill := '';
                        '_':
                            Fill := ' ';
                        else
                            Fill := '0';
                    end;
                    I += 1;
                    C := CharStr(Spec, I);
                end else
                    if C = 'e' then
                        Fill := ' '
                    else
                        Fill := '0';
                Out.Append(Directive(C, T, Fill));
                FromPos := I + 1;
            end;
            I += 1;
        end;
        Out.Append(MText.Substr(Spec, FromPos, StrLen(Spec) + 1));
        exit(Out.ToText());
    end;

    local procedure Directive(C: Text; T: BigInteger; P: Text): Text
    var
        Y: Integer;
        Mo: Integer;
        D: Integer;
        H: Integer;
        Mi: Integer;
        S: Integer;
        Ms: Integer;
        Wd: Integer;
        H12: Integer;
        Thursday: BigInteger;
        YearStart: BigInteger;
        Extra: Integer;
        Iso: Integer;
    begin
        Parts(T, Y, Mo, D, H, Mi, S, Ms, Wd);
        case C of
            'a':
                exit(CopyStr(WeekdayName(Wd), 1, 3));
            'A':
                exit(WeekdayName(Wd));
            'b':
                exit(CopyStr(MonthName(Mo), 1, 3));
            'B':
                exit(MonthName(Mo));
            'c':
                exit(TimeFormat('%x, %X', T));
            'd', 'e':
                exit(PadD3(D, P, 2));
            'f':
                exit(PadD3(Ms, P, 3) + '000');
            'g':
                exit(PadD3(TYear(IsoThursday(T)) mod 100, P, 2));
            'G':
                exit(PadD3(TYear(IsoThursday(T)) mod 10000, P, 4));
            'H':
                exit(PadD3(H, P, 2));
            'I':
                begin
                    H12 := H mod 12;
                    if H12 = 0 then
                        H12 := 12;
                    exit(PadD3(H12, P, 2));
                end;
            'j':
                exit(PadD3(1 + SpanUnits(FloorYear(T), StartOfDay(T), DayMs()), P, 3));
            'L':
                exit(PadD3(Ms, P, 3));
            'm':
                exit(PadD3(Mo + 1, P, 2));
            'M':
                exit(PadD3(Mi, P, 2));
            'p':
                if H >= 12 then
                    exit('PM')
                else
                    exit('AM');
            'q':
                exit(MText.IntText(1 + Mo div 3));
            'Q':
                exit(BigText(T));
            's':
                exit(BigText(FloorDivB(T, 1000)));
            'S':
                exit(PadD3(S, P, 2));
            'u':
                begin
                    Iso := Wd;
                    if Iso = 0 then
                        Iso := 7;
                    exit(MText.IntText(Iso));
                end;
            'U':
                exit(PadD3(WeekOfYear(T, 0), P, 2));
            'V':
                begin
                    Thursday := IsoThursday(T);
                    YearStart := FloorYear(Thursday);
                    Extra := 0;
                    if TDay(YearStart) = 4 then
                        Extra := 1;
                    exit(PadD3(SpanUnits(WeekFloor(YearStart, 4), Thursday, WeekMs()) + Extra, P, 2));
                end;
            'w':
                exit(MText.IntText(Wd));
            'W':
                exit(PadD3(WeekOfYear(T, 1), P, 2));
            'x':
                exit(TimeFormat('%-m/%-d/%Y', T));
            'X':
                exit(TimeFormat('%-I:%M:%S %p', T));
            'y':
                exit(PadD3(Y mod 100, P, 2));
            'Y':
                exit(PadD3(Y mod 10000, P, 4));
            'Z':
                exit('+0000');
            '%':
                exit('%');
        end;
        exit(C);
    end;

    // ================================================================ URLs (util/url.ts)

    local procedure SafeUrl(Url: Text): Text
    begin
        exit(SanitizeUrl(MText.DecodeEntities(Url)));
    end;

    local procedure IsCtrl(C: Integer): Boolean
    begin
        exit(((C >= 0) and (C <= 31)) or ((C >= 127) and (C <= 159)) or ((C >= 8192) and (C <= 8205)) or (C = 65279));
    end;

    local procedure RemoveCtrl(Value: Text; var Changed: Boolean): Text
    var
        Out: TextBuilder;
        I: Integer;
    begin
        for I := 1 to StrLen(Value) do
            if IsCtrl(Value[I]) then
                Changed := true
            else
                Out.Append(CopyStr(Value, I, 1));
        exit(Out.ToText());
    end;

    /// <summary>/&amp;#(\w+)(^\w|;)?/g replaced with String.fromCharCode of the digits.</summary>
    local procedure ReplaceNumericEntities(Value: Text; var Changed: Boolean): Text
    var
        Out: TextBuilder;
        I: Integer;
        J: Integer;
        Code: Decimal;
        Word: Text;
    begin
        I := 1;
        while I <= StrLen(Value) do
            if (Value[I] = 38) and (MText.CharAt(Value, I + 1) = 35) and MText.IsWord(MText.CharAt(Value, I + 2)) then begin
                J := I + 2;
                while MText.IsWord(MText.CharAt(Value, J)) do
                    J += 1;
                Word := MText.Substr(Value, I + 2, J);
                Code := 0;
                if IsAllDigits(Word) then
                    Code := NumOf(Word);
                Code := Code - FloorDec(Code / 65536) * 65536;
                // A control character would be removed in the same round.
                if not IsCtrl(Code) then
                    Out.Append(MText.FromCode(Code));
                if MText.CharAt(Value, J) = 59 then
                    J += 1;
                I := J;
                Changed := true;
            end else begin
                Out.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        exit(Out.ToText());
    end;

    local procedure RemoveCtrlEntities(Value: Text; var Changed: Boolean): Text
    var
        Out: TextBuilder;
        I: Integer;
        Lower: Text;
    begin
        Lower := LowerCase(Value);
        I := 1;
        while I <= StrLen(Value) do
            if MText.StartsWithAt(Lower, '&newline;', I) then begin
                I += 9;
                Changed := true;
            end else
                if MText.StartsWithAt(Lower, '&tab;', I) then begin
                    I += 5;
                    Changed := true;
                end else begin
                    Out.Append(CopyStr(Value, I, 1));
                    I += 1;
                end;
        exit(Out.ToText());
    end;

    /// <summary>/(\\|%5[cC])((%(6[eE]|72|74))|[nrt])/g removed.</summary>
    local procedure RemoveWsEscapes(Value: Text; var Changed: Boolean): Text
    var
        Out: TextBuilder;
        I: Integer;
        L: Integer;
        Tail: Text;
    begin
        I := 1;
        while I <= StrLen(Value) do begin
            L := 0;
            if Value[I] = 92 then
                L := 1
            else
                if LowerCase(CopyStr(Value, I, 3)) = '%5c' then
                    L := 3;
            if L > 0 then begin
                Tail := CopyStr(Value, I + L, 3);
                if (LowerCase(Tail) = '%6e') or (Tail = '%72') or (Tail = '%74') then
                    L += 3
                else
                    if (CopyStr(Tail, 1, 1) = 'n') or (CopyStr(Tail, 1, 1) = 'r') or (CopyStr(Tail, 1, 1) = 't') then
                        L += 1
                    else
                        L := 0;
            end;
            if L > 0 then begin
                I += L;
                Changed := true;
            end else begin
                Out.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        end;
        exit(Out.ToText());
    end;

    local procedure HexDigit(C: Integer): Integer
    begin
        if MText.IsDigit(C) then
            exit(C - 48);
        if (C >= 97) and (C <= 102) then
            exit(C - 87);
        if (C >= 65) and (C <= 70) then
            exit(C - 55);
        exit(-1);
    end;

    local procedure PercentByte(Value: Text; P: Integer): Integer
    begin
        if MText.CharAt(Value, P) <> 37 then
            exit(-1);
        if (HexDigit(MText.CharAt(Value, P + 1)) < 0) or (HexDigit(MText.CharAt(Value, P + 2)) < 0) then
            exit(-1);
        exit(HexDigit(MText.CharAt(Value, P + 1)) * 16 + HexDigit(MText.CharAt(Value, P + 2)));
    end;

    /// <summary>decodeURIComponent, or the text unchanged when it is malformed.</summary>
    local procedure DecodeUri(Value: Text): Text
    var
        Out: TextBuilder;
        I: Integer;
        B: Integer;
        Need: Integer;
        K: Integer;
        Cont: Integer;
        Cp: Integer;
        MinCp: Integer;
    begin
        if StrPos(Value, '%') = 0 then
            exit(Value);
        I := 1;
        while I <= StrLen(Value) do
            if Value[I] <> 37 then begin
                Out.Append(CopyStr(Value, I, 1));
                I += 1;
            end else begin
                B := PercentByte(Value, I);
                if B < 0 then
                    exit(Value);
                I += 3;
                if B < 128 then
                    Out.Append(MText.FromCode(B))
                else begin
                    case true of
                        (B >= 192) and (B <= 223):
                            begin
                                Need := 1;
                                Cp := B - 192;
                                MinCp := 128;
                            end;
                        (B >= 224) and (B <= 239):
                            begin
                                Need := 2;
                                Cp := B - 224;
                                MinCp := 2048;
                            end;
                        (B >= 240) and (B <= 247):
                            begin
                                Need := 3;
                                Cp := B - 240;
                                MinCp := 65536;
                            end;
                        else
                            exit(Value);
                    end;
                    for K := 1 to Need do begin
                        Cont := PercentByte(Value, I);
                        if (Cont < 128) or (Cont > 191) then
                            exit(Value);
                        Cp := Cp * 64 + (Cont - 128);
                        I += 3;
                    end;
                    if (Cp < MinCp) or (Cp > 1114111) or ((Cp >= 55296) and (Cp <= 57343)) then
                        exit(Value);
                    Out.Append(MText.FromCode(Cp));
                end;
            end;
        exit(Out.ToText());
    end;

    local procedure IsLineTerminator(C: Integer): Boolean
    begin
        exit((C = 10) or (C = 13) or (C = 8232) or (C = 8233));
    end;

    /// <summary>The first match of /^.+(:|&amp;colon;)/m: the longest prefix of a line that ends in a colon.</summary>
    local procedure SchemeOf(Value: Text; var Scheme: Text): Boolean
    var
        LineStart: Integer;
        LineEnd: Integer;
        Best: Integer;
        K: Integer;
    begin
        LineStart := 1;
        while LineStart <= StrLen(Value) + 1 do begin
            LineEnd := LineStart;
            while (LineEnd <= StrLen(Value)) and not IsLineTerminator(MText.CharAt(Value, LineEnd)) do
                LineEnd += 1;
            Best := 0;
            for K := LineStart + 1 to LineEnd - 1 do
                if MText.CharAt(Value, K) = 58 then
                    Best := K + 1;
            for K := LineStart + 1 to LineEnd - 7 do
                if MText.StartsWithAt(Value, '&colon;', K) then
                    if K + 7 > Best then
                        Best := K + 7;
            if Best > 0 then begin
                Scheme := MText.Substr(Value, LineStart, Best);
                exit(true);
            end;
            if LineEnd > StrLen(Value) then
                exit(false);
            LineStart := LineEnd + 1;
        end;
        exit(false);
    end;

    /// <summary>Follows the algorithm of @braintree/sanitize-url, which Mermaid applies to click targets.</summary>
    local procedure SanitizeUrl(Url: Text): Text
    var
        Decoded: Text;
        Trimmed: Text;
        Scheme: Text;
        Protocol: Text;
        Normalized: Text;
        Rounds: Integer;
        More: Boolean;
        Changed: Boolean;
        P: Integer;
    begin
        if Url = '' then
            exit('about:blank');
        Decoded := DecodeUri(MText.TrimWs(Url));
        repeat
            // Each round peels one layer of encoding. A URL wrapped this many times is not a real one.
            Rounds += 1;
            if Rounds > 32 then
                exit('about:blank');
            Changed := false;
            Decoded := RemoveCtrl(Decoded, Changed);
            Decoded := ReplaceNumericEntities(Decoded, Changed);
            Decoded := RemoveCtrlEntities(Decoded, Changed);
            Decoded := RemoveCtrl(Decoded, Changed);
            Decoded := RemoveWsEscapes(Decoded, Changed);
            Decoded := MText.TrimWs(Decoded);
            Decoded := DecodeUri(Decoded);
            More := false;
            RemoveCtrl(Decoded, More);
            ReplaceNumericEntities(Decoded, More);
            RemoveCtrlEntities(Decoded, More);
            RemoveWsEscapes(Decoded, More);
        until not More;

        if Decoded = '' then
            exit('about:blank');
        if (CopyStr(Decoded, 1, 1) = '.') or (CopyStr(Decoded, 1, 1) = '/') then
            exit(Decoded);
        Trimmed := MText.TrimStartWs(Decoded);
        if not SchemeOf(Trimmed, Scheme) then
            exit(Decoded);
        Protocol := MText.TrimWs(LowerCase(Scheme));
        P := 1;
        while (P <= StrLen(Protocol)) and not MText.IsWord(MText.CharAt(Protocol, P)) do
            P += 1;
        if MText.StartsWithAt(Protocol, 'javascript', P) or MText.StartsWithAt(Protocol, 'data', P) or MText.StartsWithAt(Protocol, 'vbscript', P) then
            exit('about:blank');
        Normalized := Trimmed.Replace('\', '/');
        if (Protocol = 'mailto:') or Protocol.Contains('://') then
            exit(Normalized);
        if (Protocol = 'http:') or (Protocol = 'https:') then
            exit(SerializeHttpUrl(Normalized));
        exit(Normalized);
    end;

    local procedure PercentEncode(Value: Text; Extra: Text): Text
    var
        Out: TextBuilder;
        I: Integer;
        C: Integer;
        Cp: Integer;
    begin
        I := 1;
        while I <= StrLen(Value) do begin
            C := Value[I];
            if (C <= 32) or (C = 127) or (StrPos(Extra, CopyStr(Value, I, 1)) > 0) then
                Out.Append('%' + HexByte(C))
            else
                if C < 128 then
                    Out.Append(CopyStr(Value, I, 1))
                else begin
                    Cp := C;
                    if (C >= 55296) and (C <= 56319) and (MText.CharAt(Value, I + 1) >= 56320) and (MText.CharAt(Value, I + 1) <= 57343) then begin
                        Cp := 65536 + (C - 55296) * 1024 + (MText.CharAt(Value, I + 1) - 56320);
                        I += 1;
                    end;
                    case true of
                        Cp < 2048:
                            Out.Append('%' + HexByte(192 + Cp div 64) + '%' + HexByte(128 + Cp mod 64));
                        Cp < 65536:
                            Out.Append('%' + HexByte(224 + Cp div 4096) + '%' + HexByte(128 + (Cp div 64) mod 64) + '%' + HexByte(128 + Cp mod 64));
                        else
                            Out.Append('%' + HexByte(240 + Cp div 262144) + '%' + HexByte(128 + (Cp div 4096) mod 64) + '%' +
                                       HexByte(128 + (Cp div 64) mod 64) + '%' + HexByte(128 + Cp mod 64));
                    end;
                end;
            I += 1;
        end;
        exit(Out.ToText());
    end;

    local procedure HexByte(B: Integer): Text
    var
        Digits: Text;
    begin
        Digits := '0123456789ABCDEF';
        exit(CopyStr(Digits, (B div 16) mod 16 + 1, 1) + CopyStr(Digits, B mod 16 + 1, 1));
    end;

    /// <summary>new URL(url).toString() for an http or https URL whose only colon ends the scheme.</summary>
    local procedure SerializeHttpUrl(Url: Text): Text
    var
        Colon: Integer;
        SchemeName: Text;
        Rest: Text;
        P: Integer;
        HostEnd: Integer;
        Host: Text;
        PathPart: Text;
        QueryPart: Text;
        FragPart: Text;
        HasQuery: Boolean;
        HasFrag: Boolean;
        Hash: Integer;
        Question: Integer;
        At: Integer;
        I: Integer;
        C: Integer;
    begin
        Colon := StrPos(Url, ':');
        SchemeName := LowerCase(MText.TrimWs(CopyStr(Url, 1, Colon - 1)));
        Rest := CopyStr(Url, Colon + 1);
        P := 1;
        while (MText.CharAt(Rest, P) = 47) or (MText.CharAt(Rest, P) = 92) do
            P += 1;
        HostEnd := P;
        while (HostEnd <= StrLen(Rest)) and not (MText.CharAt(Rest, HostEnd) in [47, 63, 35]) do
            HostEnd += 1;
        Host := MText.Substr(Rest, P, HostEnd);
        At := MText.LastIndexOf(Host, '@');
        if At > 0 then
            Host := CopyStr(Host, At + 1);
        Host := LowerCase(Host);
        if Host = '' then
            exit('about:blank');
        for I := 1 to StrLen(Host) do begin
            C := Host[I];
            if (C <= 32) or (C = 60) or (C = 62) or (C = 94) or (C = 124) or (C = 91) or (C = 93) or (C = 37) then
                exit('about:blank');
        end;
        Rest := CopyStr(Rest, HostEnd);
        Hash := StrPos(Rest, '#');
        if Hash > 0 then begin
            FragPart := CopyStr(Rest, Hash + 1);
            HasFrag := true;
            Rest := CopyStr(Rest, 1, Hash - 1);
        end;
        Question := StrPos(Rest, '?');
        if Question > 0 then begin
            QueryPart := CopyStr(Rest, Question + 1);
            HasQuery := true;
            Rest := CopyStr(Rest, 1, Question - 1);
        end;
        PathPart := Rest;
        if PathPart = '' then
            PathPart := '/';
        Url := SchemeName + '://' + Host + PercentEncode(PathPart, '"<>`{}');
        if HasQuery then
            Url += '?' + PercentEncode(QueryPart, '"#<>''');
        if HasFrag then
            Url += '#' + PercentEncode(FragPart, '"<>`');
        exit(Url);
    end;

    /// <summary>Keeps a link only when it is relative or uses a scheme the host allows.</summary>
    local procedure LinkAllowed(Url: Text): Boolean
    var
        P: Integer;
        SchemeName: Text;
    begin
        if ((MText.CharAt(Url, 1) = 47) or (MText.CharAt(Url, 1) = 92)) and ((MText.CharAt(Url, 2) = 47) or (MText.CharAt(Url, 2) = 92)) then
            exit(false);
        if not MText.IsLetter(MText.CharAt(Url, 1)) then
            exit(true);
        P := 2;
        while MText.IsLetter(MText.CharAt(Url, P)) or MText.IsDigit(MText.CharAt(Url, P)) or (MText.CharAt(Url, P) in [43, 46, 45]) do
            P += 1;
        if MText.CharAt(Url, P) <> 58 then
            exit(true);
        SchemeName := LowerCase(CopyStr(Url, 1, P - 1));
        exit((SchemeName = 'http') or (SchemeName = 'https') or (SchemeName = 'mailto') or (SchemeName = 'tel'));
    end;

    // ================================================================ rendering (render.ts)

    local procedure Setting(var Config: Dictionary of [Text, Text]; KeyName: Text; MinV: Decimal; MaxV: Decimal; Default: Decimal): Decimal
    var
        Value: Decimal;
    begin
        if SettingOpt(Config, KeyName, MinV, MaxV, Value) then
            exit(Value);
        exit(Default);
    end;

    local procedure SettingOpt(var Config: Dictionary of [Text, Text]; KeyName: Text; MinV: Decimal; MaxV: Decimal; var Value: Decimal): Boolean
    begin
        if not MText.ConfigNumber(Config, 'gantt.' + KeyName, Value) then
            exit(false);
        if Value < MinV then
            Value := MinV;
        if Value > MaxV then
            Value := MaxV;
        exit(true);
    end;

    local procedure IsScheduled(I: Integer): Boolean
    begin
        exit(IsValidT(TStart.Get(I)) and IsValidT(TEnd.Get(I)));
    end;

    /// <summary>A task label sits on one row, so only its first line is kept.</summary>
    local procedure OneLine(Raw: Text; Size: Decimal; var Lbl: Codeunit "Mermaid Label")
    var
        Out: TextBuilder;
        Source: Text;
        I: Integer;
        J: Integer;
        Cut: Integer;
        Matched: Boolean;
    begin
        // raw.replace(/<br\s*\/?>/gi, ' ')
        I := 1;
        while I <= StrLen(Raw) do begin
            Matched := false;
            if (Raw[I] = 60) and (LowerCase(CopyStr(Raw, I + 1, 2)) = 'br') then begin
                J := I + 3;
                while MText.IsSpace(MText.CharAt(Raw, J)) do
                    J += 1;
                if MText.CharAt(Raw, J) = 47 then
                    J += 1;
                if MText.CharAt(Raw, J) = 62 then begin
                    Out.Append(' ');
                    I := J + 1;
                    Matched := true;
                end;
            end;
            if not Matched then begin
                Out.Append(CopyStr(Raw, I, 1));
                I += 1;
            end;
        end;
        Source := MText.TrimWs(Out.ToText());
        // The label's first line: up to a literal \n or a line break.
        Cut := 0;
        for I := StrLen(Source) downto 1 do
            if (Source[I] = 10) or ((Source[I] = 92) and (MText.CharAt(Source, I + 1) = 110)) then
                Cut := I;
        if Cut > 0 then
            Source := CopyStr(Source, 1, Cut - 1);
        Lbl.Layout(Source, false, Size, 4000, 0);
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Lbl: Codeunit "Mermaid Label";
        Categories: Dictionary of [Text, Integer];
        CategoryNames: List of [Text];
        RowOf: List of [Integer];
        RowSection: List of [Text];
        GroupNames: List of [Text];
        Group: List of [Integer];
        Ticks: List of [BigInteger];
        VertIdx: List of [Integer];
        VertEnds: List of [Decimal];
        BarTask: List of [Integer];
        BarX0: List of [Decimal];
        BarX1: List of [Decimal];
        BarLabelX: List of [Decimal];
        BarInside: List of [Boolean];
        BarSched: List of [Boolean];
        Grid: TextBuilder;
        AxisBottom: TextBuilder;
        AxisTop: TextBuilder;
        VertLines: TextBuilder;
        VertLabels: TextBuilder;
        Bands: TextBuilder;
        SectionOut: TextBuilder;
        Excluded: TextBuilder;
        TasksOut: TextBuilder;
        Content: TextBuilder;
        Declarations: List of [Text];
        Size: Decimal;
        Pad: Decimal;
        LabelSize: Decimal;
        SectionSize: Decimal;
        TickSize: Decimal;
        BarHeight: Decimal;
        BarGap: Decimal;
        RowHeight: Decimal;
        SectionStyles: Integer;
        Compact: Boolean;
        ShowTopAxis: Boolean;
        StartT: BigInteger;
        StopT: BigInteger;
        HasPlot: Boolean;
        TitleHeight: Decimal;
        SvgWidth: Decimal;
        SvgHeight: Decimal;
        SectionWidth: Decimal;
        AxisFmt: Text;
        SampleWidth: Decimal;
        LeftX: Decimal;
        RightPadding: Decimal;
        Target: Decimal;
        PlotWidth: Decimal;
        RightX: Decimal;
        Scale: Decimal;
        TickHeight: Decimal;
        TopPadding: Decimal;
        HasTopPadding: Boolean;
        GridStart: Decimal;
        HasGridStart: Boolean;
        HeadHeight: Decimal;
        PlotTop: Decimal;
        GridLead: Decimal;
        PlotHeight: Decimal;
        PlotBottom: Decimal;
        Extent: Decimal;
        X0: Decimal;
        X1: Decimal;
        Mid: Decimal;
        LabelX: Decimal;
        LW: Decimal;
        Inside: Boolean;
        FitsRight: Boolean;
        FitsLeft: Boolean;
        Interval: Text;
        Weekday: Text;
        TickCount: Integer;
        LastRight: Decimal;
        HasLastRight: Boolean;
        LastLabel: Text;
        BottomY: Decimal;
        TopY: Decimal;
        Tx: Decimal;
        TickText: Text;
        TickW: Decimal;
        Body: Text;
        VertTop: Decimal;
        VertLine: Decimal;
        Vx: Decimal;
        Cx: Decimal;
        Line: Integer;
        Searching: Boolean;
        RowIdx: Integer;
        EndRow: Integer;
        Section: Text;
        CatIndex: Integer;
        Y: Decimal;
        H: Decimal;
        Fill: Text;
        FromDay: BigInteger;
        ToDay: BigInteger;
        HasRun: Boolean;
        Day: BigInteger;
        State: Text;
        Classes: Text;
        Shape: Text;
        TextFill: Text;
        Color: Text;
        Paint: Text;
        Stroke: Text;
        Cy: Decimal;
        R: Decimal;
        Url: Text;
        TodaySvg: Text;
        StyleAttr: Text;
        ShapeAttr: Text;
        TextAttr: Text;
        StrokeValue: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleFontSize: Decimal;
        AxisLine: Text;
        I: Integer;
        K: Integer;
        Rows: Integer;
        TaskIdx: Integer;
        Offset: Integer;
    begin
        Size := MText.FontSize();
        Pad := 8;
        LabelSize := Setting(Config, 'fontSize', 4, 72, Round(Size * 0.8125, 1));
        SectionSize := Setting(Config, 'sectionFontSize', 4, 72, LabelSize);
        TickSize := Round(Size * 0.75, 1);
        BarHeight := Setting(Config, 'barHeight', 4, 400, Round(LabelSize * 1.85, 1));
        BarGap := Setting(Config, 'barGap', 0, 400, Round(BarHeight / 4, 1));
        RowHeight := BarHeight + BarGap;
        SectionStyles := Round(Setting(Config, 'numberSectionStyles', 1, 1000, 4), 1);
        Compact := GDisplayMode = 'compact';
        ShowTopAxis := GTopAxis or MText.ConfigBool(Config, 'gantt.topAxis', false);

        GetTasks();

        // Sections in order of first use by a task that takes a row.
        for I := 1 to TId.Count() do
            if not TVert.Get(I) then
                if not Categories.ContainsKey(TSection.Get(I)) then begin
                    Categories.Add(TSection.Get(I), Categories.Count());
                    CategoryNames.Add(TSection.Get(I));
                end;

        for I := 1 to TId.Count() do
            RowOf.Add(-1);
        if Compact then begin
            // Mermaid's compact mode: within a section, a task goes on the first row that is free when it starts.
            foreach Section in CategoryNames do
                GroupNames.Add(Section);
            foreach Section in GroupNames do begin
                Clear(Group);
                for I := 1 to TId.Count() do
                    if not TVert.Get(I) then
                        if TSection.Get(I) = Section then
                            Group.Add(I);
                Offset := RowSection.Count();
                Rows := PackRows(Group, Offset, RowOf);
                for K := 1 to Rows do
                    RowSection.Add(Section);
            end;
        end else
            for I := 1 to TId.Count() do
                if not TVert.Get(I) then begin
                    RowOf.Set(I, RowSection.Count());
                    RowSection.Add(TSection.Get(I));
                end;

        HasPlot := false;
        for I := 1 to TId.Count() do
            if IsScheduled(I) then begin
                if not HasPlot then begin
                    StartT := TStart.Get(I);
                    StopT := TEnd.Get(I);
                    HasPlot := true;
                end;
                if TStart.Get(I) < StartT then
                    StartT := TStart.Get(I);
                if TEnd.Get(I) > StopT then
                    StopT := TEnd.Get(I);
            end;
        if HasPlot then
            HasPlot := StartT <= StopT;

        TitleLbl.Layout(GTitle, false, Size, 4000, MText.StyleBold());
        TitleHeight := 0;
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 16;

        if not HasPlot then begin
            SvgWidth := MText.Ceil(MText.MaxDec(TitleLbl.GetWidth(), 1) + 2 * Pad);
            SvgHeight := MText.Ceil(MText.MaxDec(TitleLbl.GetHeight(), 1) + 2 * Pad);
            exit(Builder.Document('gantt', SvgWidth, SvgHeight, Size, GAccTitle, GAccDescr,
                                  Builder.TitleSvg(TitleLbl, SvgWidth / 2, Pad + TitleLbl.GetHeight() / 2)));
        end;

        SectionWidth := 0;
        foreach Section in CategoryNames do begin
            Lbl.Layout(Section, false, SectionSize, 180, 0);
            SectionWidth := MText.MaxDec(SectionWidth, Lbl.GetWidth());
        end;

        AxisFmt := GAxisFormat;
        if AxisFmt = '' then
            if GDateFormat = 'D' then
                AxisFmt := '%d'
            else
                AxisFmt := MText.ConfigText(Config, 'gantt.axisFormat', '%Y-%m-%d');
        SampleWidth := MText.MaxDec(MText.Width(TimeFormat(AxisFmt, StartT), TickSize, 0), MText.Width(TimeFormat(AxisFmt, StopT), TickSize, 0));

        if SectionWidth > 0 then
            LeftX := SectionWidth + 24
        else
            LeftX := 0;
        LeftX := Pad + Setting(Config, 'leftPadding', 0, 2000, MText.MaxDec(LeftX, SampleWidth / 2));
        RightPadding := Setting(Config, 'rightPadding', 0, 2000, MText.MaxDec(16, SampleWidth / 2));
        Target := Setting(Config, 'useWidth', 100, 20000, 800);
        PlotWidth := MText.MaxDec(240, Target - LeftX - RightPadding - Pad);
        RightX := LeftX + PlotWidth;
        Scale := 0;
        if StopT > StartT then
            Scale := PlotWidth / (StopT - StartT);

        TickHeight := Round(TickSize * 1.75, 1);
        HasTopPadding := SettingOpt(Config, 'topPadding', 0, 2000, TopPadding);
        HasGridStart := SettingOpt(Config, 'gridLineStartPadding', 0, 2000, GridStart);
        HeadHeight := Pad + TitleHeight;
        if ShowTopAxis then
            HeadHeight += TickHeight;
        PlotTop := HeadHeight;
        if HasTopPadding then
            PlotTop := MText.MaxDec(HeadHeight, TopPadding);
        // Mermaid starts its grid lines above the first row by the difference between these two settings.
        // Here that only uses room a larger topPadding leaves free.
        GridLead := 0;
        if HasTopPadding and HasGridStart then
            GridLead := MText.MaxDec(0, MText.MinDec(TopPadding - GridStart, PlotTop - HeadHeight));
        Rows := RowSection.Count();
        if Rows < 1 then
            PlotHeight := RowHeight
        else
            PlotHeight := Rows * RowHeight;
        PlotBottom := PlotTop + PlotHeight;

        // Bars and where their labels go: inside when they fit, otherwise beside the bar on the side with room.
        Extent := RightX + RightPadding;
        for I := 1 to TId.Count() do
            if not TVert.Get(I) then begin
                OneLine(TName.Get(I), LabelSize, Lbl);
                LW := Lbl.GetWidth();
                BarTask.Add(I);
                if not IsScheduled(I) then begin
                    LabelX := LeftX + 8 + LW / 2;
                    Extent := MText.MaxDec(Extent, LabelX + LW / 2);
                    BarX0.Add(0);
                    BarX1.Add(0);
                    BarLabelX.Add(LabelX);
                    BarInside.Add(false);
                    BarSched.Add(false);
                end else begin
                    X0 := XOf(TStart.Get(I), StartT, LeftX, PlotWidth, Scale);
                    if IsValidT(TRenderEnd.Get(I)) then
                        X1 := XOf(TRenderEnd.Get(I), StartT, LeftX, PlotWidth, Scale)
                    else
                        X1 := XOf(TEnd.Get(I), StartT, LeftX, PlotWidth, Scale);
                    if TMilestone.Get(I) then
                        X1 := MText.MaxDec(X1, X0)
                    else
                        X1 := MText.MaxDec(X1, X0 + 2);
                    if TMilestone.Get(I) then begin
                        Mid := X0 + (XOf(TEnd.Get(I), StartT, LeftX, PlotWidth, Scale) - X0) / 2;
                        X0 := Mid - BarHeight / 2;
                        X1 := Mid + BarHeight / 2;
                    end;
                    Inside := (not TMilestone.Get(I)) and (LW + 16 <= X1 - X0);
                    LabelX := (X0 + X1) / 2;
                    if not Inside then begin
                        FitsRight := X1 + 8 + LW <= RightX + RightPadding;
                        FitsLeft := X0 - 8 - LW >= LeftX;
                        if FitsRight or not FitsLeft then
                            LabelX := X1 + 8 + LW / 2
                        else
                            LabelX := X0 - 8 - LW / 2;
                        Extent := MText.MaxDec(Extent, LabelX + LW / 2);
                    end;
                    BarX0.Add(X0);
                    BarX1.Add(X1);
                    BarLabelX.Add(LabelX);
                    BarInside.Add(Inside);
                    BarSched.Add(true);
                end;
            end;

        Interval := GTickInterval;
        if Interval = '' then
            Interval := MText.ConfigText(Config, 'gantt.tickInterval', '');
        if GHasWeekday then
            Weekday := GWeekday
        else
            Weekday := MText.ConfigText(Config, 'gantt.weekday', 'sunday');
        TickCount := MText.Floor(PlotWidth / (SampleWidth + 24));
        if TickCount > 10 then
            TickCount := 10;
        if TickCount < 2 then
            TickCount := 2;
        if not IntervalTicks(Interval, Weekday, StartT, StopT, MText.Ceil(PlotWidth / 3), Ticks) then
            AutoTicks(StartT, StopT, TickCount, Ticks);

        BottomY := PlotBottom + TickHeight / 2 + 2;
        TopY := PlotTop - GridLead - TickHeight / 2 - 2;
        foreach Day in Ticks do begin
            Tx := XOf(Day, StartT, LeftX, PlotWidth, Scale);
            Grid.Append('M' + MText.Num(Tx) + ',' + MText.Num(PlotTop - GridLead) + 'V' + MText.Num(PlotBottom));
            TickText := TimeFormat(AxisFmt, Day);
            TickW := MText.Width(TickText, TickSize, 0);
            // A label is skipped when it would run into the one before it or only repeat it; its grid line stays.
            Searching := TickText <> LastLabel;
            if Searching and HasLastRight then
                if Tx - TickW / 2 < LastRight + 8 then
                    Searching := false;
            if Searching then begin
                LastRight := Tx + TickW / 2;
                HasLastRight := true;
                LastLabel := TickText;
                Extent := MText.MaxDec(Extent, LastRight);
                Body := 'text-anchor="middle">' + MText.Esc(TickText) + '</text>';
                AxisBottom.Append('<text x="' + MText.Num(Tx) + '" y="' + MText.Num(BottomY + TickSize * 0.35) + '" ' + Body);
                if ShowTopAxis then
                    AxisTop.Append('<text x="' + MText.Num(Tx) + '" y="' + MText.Num(TopY + TickSize * 0.35) + '" ' + Body);
            end;
        end;

        // Vertical markers take no row. Their labels go under the axis, on as many lines as it takes to keep them apart.
        for I := 1 to TId.Count() do
            if TVert.Get(I) and IsScheduled(I) then begin
                K := VertIdx.Count() + 1;
                Searching := true;
                while Searching do
                    if K = 1 then
                        Searching := false
                    else
                        if TStart.Get(VertIdx.Get(K - 1)) > TStart.Get(I) then
                            K -= 1
                        else
                            Searching := false;
                VertIdx.Insert(K, I);
            end;
        VertTop := PlotBottom + TickHeight + 4;
        VertLine := Round(LabelSize * 1.5, 1);
        foreach TaskIdx in VertIdx do begin
            Vx := XOf(TStart.Get(TaskIdx), StartT, LeftX, PlotWidth, Scale);
            OneLine(TName.Get(TaskIdx), LabelSize, Lbl);
            LW := Lbl.GetWidth();
            Cx := MText.MaxDec(Pad + LW / 2, Vx);
            Line := 0;
            Searching := true;
            while Searching do
                if Line >= VertEnds.Count() then
                    Searching := false
                else
                    if Cx - LW / 2 < VertEnds.Get(Line + 1) + 8 then
                        Line += 1
                    else
                        Searching := false;
            if Line = VertEnds.Count() then
                VertEnds.Add(Cx + LW / 2)
            else
                VertEnds.Set(Line + 1, Cx + LW / 2);
            Extent := MText.MaxDec(Extent, VertEnds.Get(Line + 1));
            VertLines.Append('<path class="pele-vert" data-id="' + MText.EscText(TId.Get(TaskIdx)) + '" d="M' + MText.Num(Vx) + ',' +
                             MText.Num(PlotTop - GridLead) + 'V' + MText.Num(PlotBottom) + '"/>');
            VertLabels.Append(Lbl.ToSvg(Cx, VertTop + Line * VertLine + VertLine / 2, ' class="pele-vert-label" data-id="' + MText.EscText(TId.Get(TaskIdx)) + '"'));
        end;

        SvgWidth := MText.Ceil(MText.MaxDec(Extent, Pad + TitleLbl.GetWidth()) + Pad);
        if VertEnds.Count() > 0 then
            SvgHeight := MText.Ceil(PlotBottom + TickHeight + 4 + VertEnds.Count() * VertLine + Pad)
        else
            SvgHeight := MText.Ceil(PlotBottom + TickHeight + Pad);

        // Section bands, one per run of rows that share a section, shaded on alternate sections.
        RowIdx := 0;
        while RowIdx < RowSection.Count() do begin
            Section := RowSection.Get(RowIdx + 1);
            EndRow := RowIdx + 1;
            Searching := true;
            while Searching do
                if EndRow >= RowSection.Count() then
                    Searching := false
                else
                    if RowSection.Get(EndRow + 1) = Section then
                        EndRow += 1
                    else
                        Searching := false;
            CatIndex := Categories.Get(Section) mod SectionStyles;
            Y := PlotTop + RowIdx * RowHeight;
            H := (EndRow - RowIdx) * RowHeight;
            if (Categories.Count() > 1) or (Section <> '') then begin
                if CatIndex mod 2 = 0 then
                    Fill := 'var(--_s)'
                else
                    Fill := 'none';
                Bands.Append('<rect class="pele-section pele-section-' + MText.IntText(CatIndex) + '" x="0" y="' + MText.Num(Y) + '" width="' +
                             MText.Num(SvgWidth) + '" height="' + MText.Num(H) + '" fill="' + Fill + '"/>');
            end;
            Lbl.Layout(Section, false, SectionSize, 180, 0);
            SectionOut.Append(Lbl.ToSvg(Pad + 8 + Lbl.GetWidth() / 2, Y + H / 2, ' class="pele-section-label" data-id="' + MText.EscText(Section) + '"'));
            RowIdx := EndRow;
        end;

        // Excluded days, as Mermaid marks them: a day at a time from the first task's start, and not at all
        // when the chart spans more than five years.
        if (GExcludes.Count() > 0) or (GIncludes.Count() > 0) then
            if IsValidT(AddT(StartT, 6, 'y')) then
                if AddT(StartT, 6, 'y') > StopT then begin
                    HasRun := false;
                    Day := StartT;
                    while IsValidT(Day) and (Day <= StopT) do begin
                        if IsInvalidDate(Day) then begin
                            if not HasRun then
                                FromDay := Day;
                            ToDay := Day;
                            HasRun := true;
                        end else
                            if HasRun then begin
                                Excluded.Append(ExcludedRect(FromDay, ToDay, StartT, LeftX, RightX, PlotWidth, Scale, PlotTop, PlotHeight));
                                HasRun := false;
                            end;
                        Day := AddDaysT(Day, 1);
                    end;
                    if HasRun then
                        Excluded.Append(ExcludedRect(FromDay, ToDay, StartT, LeftX, RightX, PlotWidth, Scale, PlotTop, PlotHeight));
                end;

        for K := 1 to BarTask.Count() do begin
            I := BarTask.Get(K);
            Cy := PlotTop + RowOf.Get(I) * RowHeight + RowHeight / 2;
            State := '';
            if TActive.Get(I) then
                State := 'active'
            else
                if TDone.Get(I) then
                    State := 'done';
            Classes := 'pele-task';
            if State <> '' then
                Classes += ' pele-' + State;
            if TCrit.Get(I) then
                Classes += ' pele-crit';
            if TMilestone.Get(I) then
                Classes += ' pele-milestone';
            if TClickable.Get(I) then
                Classes += ' pele-clickable';
            Shape := '';
            TextFill := '';
            if not BarSched.Get(K) then begin
                Classes += ' pele-unscheduled';
                TextFill := ' fill="var(--_m)"';
            end else begin
                // A critical task takes the critical color in place of the accent. Done, it keeps the fill
                // of finished work and only its border is in that color.
                if TCrit.Get(I) then
                    Color := Builder.Critical()
                else
                    Color := 'var(--_c)';
                case State of
                    'done':
                        Paint := 'fill="var(--_a)"';
                    'active':
                        Paint := 'fill="' + Color + '" fill-opacity="0.25"';
                    else
                        Paint := 'fill="' + Color + '"';
                end;
                if (State = 'done') and not TCrit.Get(I) then
                    Stroke := 'stroke="var(--_b)"'
                else
                    Stroke := 'stroke="' + Color + '"';
                X0 := BarX0.Get(K);
                X1 := BarX1.Get(K);
                if TMilestone.Get(I) then begin
                    Cx := (X0 + X1) / 2;
                    R := BarHeight / 2;
                    Shape := '<path d="M' + MText.Num(Cx) + ',' + MText.Num(Cy - R) + 'L' + MText.Num(Cx + R) + ',' + MText.Num(Cy) + 'L' +
                             MText.Num(Cx) + ',' + MText.Num(Cy + R) + 'L' + MText.Num(Cx - R) + ',' + MText.Num(Cy) + 'Z" ' + Paint + ' ' + Stroke +
                             ' stroke-linejoin="round"/>';
                end else
                    Shape := '<rect x="' + MText.Num(X0) + '" y="' + MText.Num(Cy - BarHeight / 2) + '" width="' + MText.Num(X1 - X0) +
                             '" height="' + MText.Num(BarHeight) + '" rx="' + Builder.Radius() + '" ' + Paint + ' ' + Stroke + '/>';
                if BarInside.Get(K) then begin
                    if State = '' then
                        TextFill := ' fill="var(--_bg)"';
                end else
                    if State = 'done' then
                        TextFill := ' fill="var(--_m)"';
            end;
            OneLine(TName.Get(I), LabelSize, Lbl);
            Body := Shape + Lbl.ToSvg(BarLabelX.Get(K), Cy, ' class="pele-label"' + TextFill);
            if GLinks.ContainsKey(TId.Get(I)) then begin
                Url := GLinks.Get(TId.Get(I));
                if LinkAllowed(Url) then
                    Body := '<a href="' + MText.Esc(Url) + '" rel="noopener">' + Body + '</a>';
            end;
            TasksOut.Append('<g class="' + Classes + '" data-id="' + MText.EscText(TId.Get(I)) + '">' + Body + '</g>');
        end;

        TodaySvg := '';
        if (GTodayMarker <> 'off') and (NowMs >= StartT) and (NowMs <= StopT) and (StopT > StartT) then begin
            Tx := XOf(NowMs, StartT, LeftX, PlotWidth, Scale);
            Y := PlotTop - GridLead;
            StyleAttr := '';
            if GTodayMarker <> '' then begin
                Declarations := GTodayMarker.Split(',');
                Builder.ResolveStyle(Declarations, ShapeAttr, StyleAttr, TextAttr, StrokeValue, IsBold, IsItalic, StyleFontSize);
            end;
            TodaySvg := '<g class="pele-today"><path d="M' + MText.Num(Tx) + ',' + MText.Num(Y) + 'V' + MText.Num(PlotBottom) +
                        '" fill="none" stroke="var(--_c)" stroke-width="2"' + StyleAttr + '/>';
            if StyleAttr = '' then
                TodaySvg += '<path d="M' + MText.Num(Tx - 4) + ',' + MText.Num(Y - 5) + 'H' + MText.Num(Tx + 4) + 'L' + MText.Num(Tx) + ',' +
                            MText.Num(Y + 1) + 'Z" fill="var(--_c)"/>';
            TodaySvg += '</g>';
        end;

        AxisLine := 'M' + MText.Num(LeftX) + ',' + MText.Num(PlotBottom) + 'H' + MText.Num(RightX);
        if ShowTopAxis then
            AxisLine += 'M' + MText.Num(LeftX) + ',' + MText.Num(PlotTop - GridLead) + 'H' + MText.Num(RightX);

        Content.Append(Builder.TitleSvg(TitleLbl, SvgWidth / 2, Pad + TitleLbl.GetHeight() / 2));
        if Bands.Length() > 0 then
            Content.Append('<g class="pele-sections">' + Bands.ToText() + '</g>');
        if Excluded.Length() > 0 then
            Content.Append('<g class="pele-excluded" fill="var(--_a)">' + Excluded.ToText() + '</g>');
        Content.Append('<g class="pele-grid" fill="none"><path d="' + Grid.ToText() + '" stroke="var(--_b)" stroke-dasharray="1 3"/><path d="' +
                       AxisLine + '" stroke="var(--_b)"/></g>');
        if VertLines.Length() > 0 then
            Content.Append('<g class="pele-verts" fill="none" stroke="var(--_l)" stroke-width="1.5" stroke-dasharray="4 3">' + VertLines.ToText() + '</g>');
        Content.Append(TodaySvg);
        Content.Append('<g class="pele-tasks" font-size="' + MText.Num(LabelSize) + '">' + TasksOut.ToText() + '</g>');
        Content.Append('<g class="pele-section-labels" font-size="' + MText.Num(SectionSize) + '">' + SectionOut.ToText() + '</g>');
        Content.Append('<g class="pele-axis" font-size="' + MText.Num(TickSize) + '" fill="var(--_m)">' + AxisBottom.ToText() + AxisTop.ToText() + '</g>');
        if VertLabels.Length() > 0 then
            Content.Append('<g class="pele-vert-labels" font-size="' + MText.Num(LabelSize) + '">' + VertLabels.ToText() + '</g>');

        exit(Builder.Document('gantt', SvgWidth, SvgHeight, Size, GAccTitle, GAccDescr, Content.ToText()));
    end;

    local procedure XOf(T: BigInteger; StartT: BigInteger; LeftX: Decimal; PlotWidth: Decimal; Scale: Decimal): Decimal
    begin
        if Scale = 0 then
            exit(LeftX + PlotWidth / 2);
        exit(LeftX + (T - StartT) * Scale);
    end;

    local procedure ExcludedRect(FromDay: BigInteger; ToDay: BigInteger; StartT: BigInteger; LeftX: Decimal; RightX: Decimal; PlotWidth: Decimal; Scale: Decimal; PlotTop: Decimal; PlotHeight: Decimal): Text
    var
        Ex0: Decimal;
        Ex1: Decimal;
    begin
        Ex0 := MText.MaxDec(LeftX, XOf(StartOfDay(FromDay), StartT, LeftX, PlotWidth, Scale));
        Ex1 := MText.MinDec(RightX, XOf(StartOfDay(ToDay) + DayMs() - 1, StartT, LeftX, PlotWidth, Scale));
        if Ex1 > Ex0 then
            exit('<rect x="' + MText.Num(Ex0) + '" y="' + MText.Num(PlotTop) + '" width="' + MText.Num(Ex1 - Ex0) + '" height="' + MText.Num(PlotHeight) + '"/>');
        exit('');
    end;

    /// <summary>Packs one section's tasks onto rows; returns how many rows it takes, at least one.</summary>
    local procedure PackRows(var Group: List of [Integer]; Offset: Integer; var RowOf: List of [Integer]): Integer
    var
        Sorted: List of [Integer];
        Free: List of [BigInteger];
        I: Integer;
        K: Integer;
        Row: Integer;
        Rows: Integer;
        Searching: Boolean;
    begin
        foreach I in Group do
            if IsScheduled(I) then begin
                K := Sorted.Count() + 1;
                Searching := true;
                while Searching do
                    if K = 1 then
                        Searching := false
                    else
                        if StartsAfter(Sorted.Get(K - 1), I) then
                            K -= 1
                        else
                            Searching := false;
                Sorted.Insert(K, I);
            end;
        foreach I in Sorted do begin
            Row := 0;
            Searching := true;
            while Searching do
                if Row >= Free.Count() then
                    Searching := false
                else
                    if TStart.Get(I) < Free.Get(Row + 1) then
                        Row += 1
                    else
                        Searching := false;
            if Row = Free.Count() then
                Free.Add(TEnd.Get(I))
            else
                Free.Set(Row + 1, TEnd.Get(I));
            RowOf.Set(I, Offset + Row);
        end;
        Rows := Free.Count();
        foreach I in Group do
            if RowOf.Get(I) < 0 then begin
                RowOf.Set(I, Offset + Rows);
                Rows += 1;
            end;
        if Rows < 1 then
            exit(1);
        exit(Rows);
    end;

    /// <summary>Whether task A sorts after task B: by start, then by source order.</summary>
    local procedure StartsAfter(A: Integer; B: Integer): Boolean
    begin
        if TStart.Get(A) <> TStart.Get(B) then
            exit(TStart.Get(A) > TStart.Get(B));
        exit(TOrder.Get(A) > TOrder.Get(B));
    end;
}
