/// <summary>
/// Port of pele's diagrams/sequence: lexer.ts and parser.ts as one statement scanner, db.ts for the model,
/// actors.ts and render.ts for the drawing. Participants (participant, actor, and the @{ "type": ... } kinds),
/// aliases, boxes, create and destroy, every message arrow including half and reverse arrows, activations
/// with + and -, notes, loop, alt/else, opt, par/and, critical/option, break and rect blocks, autonumber,
/// title and accessibility statements are supported.
/// </summary>
codeunit 68909 "Mermaid Sequence Diagram"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        TempActor: Record "Mermaid Seq Actor" temporary;
        TempMsg: Record "Mermaid Seq Message" temporary;
        BoxNames: List of [Text];
        BoxFills: List of [Text];
        BoxWraps: List of [Boolean];
        FrameKinds: List of [Integer];
        Src: Text;
        Pos: Integer;
        SrcLen: Integer;
        SeqTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        AutoWrap: Boolean;
        CurrentBox: Integer;
        NextActorNo: Integer;
        NextMsgNo: Integer;
        // Render state
        MinX: Decimal;
        MaxX: Decimal;
        ActCol: List of [Integer];
        ActY: List of [Decimal];
        ActivationsOut: List of [Text];
        RectsOut: List of [Text];
        CrossesOut: TextBuilder;
        ColXs: List of [Decimal];
        Size: Decimal;
        Small: Decimal;
        Tiny: Decimal;
        WrapW: Decimal;
        ActW: Decimal;
        ActStep: Decimal;
        BadgeH: Decimal;

    // ---------------------------------------------------------------- line types (Mermaid's LINETYPE)
    // 0 SOLID, 1 DOTTED, 2 NOTE, 3 SOLID_CROSS, 4 DOTTED_CROSS, 5 SOLID_OPEN, 6 DOTTED_OPEN,
    // 10 LOOP_START, 11 LOOP_END, 12 ALT_START, 13 ALT_ELSE, 14 ALT_END, 15 OPT_START, 16 OPT_END,
    // 17 ACTIVE_START, 18 ACTIVE_END, 19 PAR_START, 20 PAR_AND, 21 PAR_END, 22 RECT_START, 23 RECT_END,
    // 24 SOLID_POINT, 25 DOTTED_POINT, 26 AUTONUMBER, 27 CRITICAL_START, 28 CRITICAL_OPTION, 29 CRITICAL_END,
    // 30 BREAK_START, 31 BREAK_END, 32 PAR_OVER_START, 33 BIDIRECTIONAL_SOLID, 34 BIDIRECTIONAL_DOTTED,
    // 41..48 half arrows (top, bottom, stick top, stick bottom, and their reverses), 51..58 their dotted forms.

    /// <summary>The look of a message line: Head 0 none, 1 arrow, 2 cross, 3 open, 4 half solid, 5 half stick.</summary>
    local procedure LineStyle(LineType: Integer; var Dotted: Boolean; var Head: Integer; var AtStart: Boolean; var AtEnd: Boolean; var Bottom: Boolean): Boolean
    var
        Base: Integer;
    begin
        Dotted := false;
        AtStart := false;
        AtEnd := true;
        Bottom := false;
        case LineType of
            0, 1:
                Head := 1;
            3, 4:
                Head := 2;
            5, 6:
                Head := 0;
            24, 25:
                Head := 3;
            33, 34:
                begin
                    Head := 1;
                    AtStart := true;
                end;
            41 .. 48, 51 .. 58:
                begin
                    Base := LineType;
                    if Base > 50 then begin
                        Base -= 10;
                        Dotted := true;
                    end;
                    case Base of
                        41, 42, 45, 46:
                            Head := 4;
                        else
                            Head := 5;
                    end;
                    Bottom := Base in [42, 44, 46, 48];
                    if Base >= 45 then begin
                        AtStart := true;
                        AtEnd := false;
                    end;
                    exit(true);
                end;
            else
                exit(false);
        end;
        Dotted := LineType in [1, 4, 6, 25, 34];
        exit(true);
    end;

    local procedure IsLineMessage(LineType: Integer): Boolean
    var
        Dotted: Boolean;
        Head: Integer;
        AtStart: Boolean;
        AtEnd: Boolean;
        Bottom: Boolean;
    begin
        exit(LineStyle(LineType, Dotted, Head, AtStart, AtEnd, Bottom));
    end;

    // ---------------------------------------------------------------- scanning

    local procedure Cur(): Integer
    begin
        exit(MText.CharAt(Src, Pos));
    end;

    local procedure CharAtP(P: Integer): Integer
    begin
        exit(MText.CharAt(Src, P));
    end;

    local procedure CiAt(P: Integer; Lit: Text): Boolean
    begin
        exit(LowerCase(CopyStr(Src, P, StrLen(Lit))) = Lit);
    end;

    local procedure CiWord(Lit: Text): Boolean
    begin
        exit(CiAt(Pos, Lit) and not MText.IsWord(CharAtP(Pos + StrLen(Lit))));
    end;

    local procedure SkipSameLine()
    begin
        while MText.IsSpace(Cur()) and (Cur() <> 10) do
            Pos += 1;
    end;

    local procedure SkipToEol()
    begin
        while (Cur() <> 10) and (Cur() <> -1) do
            Pos += 1;
    end;

    local procedure LineRun(P: Integer): Integer
    begin
        while (CharAtP(P) <> -1) and not (CharAtP(P) in [35, 10, 59]) do
            P += 1;
        exit(P);
    end;

    local procedure Fail(Expected: Text)
    var
        Got: Text;
    begin
        case Cur() of
            -1:
                Got := 'EOF';
            10, 59:
                Got := 'NEWLINE';
            58:
                Got := 'TXT';
            else
                Got := 'ACTOR';
        end;
        MText.SyntaxError('sequence', Src, Pos, 'Expecting ' + Expected + ', got ''' + Got + '''', false);
    end;

    local procedure ExpectNewline()
    begin
        SkipSameLine();
        if Cur() = 35 then
            SkipToEol();
        if (Cur() <> 10) and (Cur() <> 59) and (Cur() <> -1) then
            Fail('''NEWLINE''');
        if Cur() <> -1 then
            Pos += 1;
    end;

    local procedure IsActorStart(C: Integer): Boolean
    begin
        if C = -1 then
            exit(false);
        exit(not (C in [47, 92, 43, 40, 41, 60, 45, 62, 58, 10, 44, 59]));
    end;

    local procedure IsActorRest(C: Integer): Boolean
    begin
        if C = -1 then
            exit(false);
        exit(not (C in [43, 60, 45, 62, 58, 10, 44, 59]));
    end;

    local procedure IsIdChar(C: Integer; Wide: Boolean): Boolean
    begin
        if C = -1 then
            exit(false);
        if C in [60, 62, 58, 10, 44, 59, 64] then
            exit(false);
        if Wide then
            exit(true);
        exit(not MText.IsSpace(C));
    end;

    local procedure ArrowAhead(Q: Integer): Boolean
    var
        C: Integer;
        D: Integer;
        E: Integer;
    begin
        C := CharAtP(Q);
        D := CharAtP(Q + 1);
        E := CharAtP(Q + 2);
        if C = 45 then begin
            if D in [120, 88, 41, 92, 47, 45] then
                exit(true);
            exit((D = 124) and ((E = 92) or (E = 47)));
        end;
        if (C = 47) or (C = 92) then
            exit(((D = 124) or (D = C)) and (E = 45));
        exit((C = 40) and (D = 41));
    end;

    /// <summary>An actor name in a message or note, as the ACTOR rule of Mermaid's lexer reads it.</summary>
    local procedure ReadActor(): Text
    var
        Q: Integer;
        R: Integer;
        Stop: Boolean;
        Name: Text;
    begin
        SkipSameLine();
        if not IsActorStart(Cur()) then
            Fail('''ACTOR''');
        Q := Pos + 1;
        while IsActorStart(CharAtP(Q)) do
            Q += 1;
        while not Stop and (Q <= SrcLen) and not ArrowAhead(Q) do begin
            R := Q;
            while CharAtP(R) = 45 do
                R += 1;
            if not IsActorRest(CharAtP(R)) then
                Stop := true
            else begin
                R += 1;
                while IsActorRest(CharAtP(R)) do
                    R += 1;
                Q := R;
            end;
        end;
        Name := MText.TrimWs(MText.Substr(Src, Pos, Q));
        Pos := Q;
        if Name = '' then
            Fail('''ACTOR''');
        exit(Name);
    end;

    /// <summary>A message arrow at the current position, as Mermaid's line type, or -1.</summary>
    local procedure ReadArrow(): Integer
    var
        C: Integer;
        D: Integer;
        E: Integer;
        F: Integer;
        Dotted: Boolean;
        Top: Boolean;
    begin
        C := Cur();
        D := CharAtP(Pos + 1);
        E := CharAtP(Pos + 2);
        F := CharAtP(Pos + 3);
        if (C = 60) and MText.StartsWithAt(Src, '<<->>', Pos) then
            exit(Take(5, 33));
        if (C = 60) and MText.StartsWithAt(Src, '<<-->>', Pos) then
            exit(Take(6, 34));
        if (C = 47) or (C = 92) then begin
            if ((D <> 124) and (D <> C)) or (E <> 45) then
                exit(-1);
            Dotted := F = 45;
            Top := C = 47;
            if D = 124 then begin
                if Top then
                    exit(TakeDotted(Dotted, 45))
                else
                    exit(TakeDotted(Dotted, 46));
            end;
            if Top then
                exit(TakeDotted(Dotted, 47));
            exit(TakeDotted(Dotted, 48));
        end;
        if C <> 45 then
            exit(-1);
        if D = 62 then begin
            if E = 62 then
                exit(Take(3, 0));
            exit(Take(2, 5));
        end;
        if (D = 120) or (D = 88) then
            exit(Take(2, 3));
        if D = 41 then
            exit(Take(2, 24));
        if (D = 124) and (E = 92) then
            exit(Take(3, 41));
        if (D = 124) and (E = 47) then
            exit(Take(3, 42));
        if (D = 92) and (E = 92) then
            exit(Take(3, 43));
        if (D = 47) and (E = 47) then
            exit(Take(3, 44));
        if D = 45 then begin
            if E = 62 then begin
                if F = 62 then
                    exit(Take(4, 1));
                exit(Take(3, 6));
            end;
            if (E = 120) or (E = 88) then
                exit(Take(3, 4));
            if E = 41 then
                exit(Take(3, 25));
            if (E = 124) and (F = 92) then
                exit(Take(4, 51));
            if (E = 124) and (F = 47) then
                exit(Take(4, 52));
            if (E = 92) and (F = 92) then
                exit(Take(4, 53));
            if (E = 47) and (F = 47) then
                exit(Take(4, 54));
        end;
        exit(-1);
    end;

    local procedure Take(Len: Integer; LineType: Integer): Integer
    begin
        Pos += Len;
        exit(LineType);
    end;

    local procedure TakeDotted(Dotted: Boolean; LineType: Integer): Integer
    begin
        if Dotted then
            exit(Take(4, LineType + 10));
        exit(Take(3, LineType));
    end;

    /// <summary>Text after a colon: wrap: and nowrap: prefixes set the wrap of the item.</summary>
    local procedure ParseMessage(Raw: Text; var Wrap: Boolean): Text
    var
        Value: Text;
    begin
        Value := MText.TrimWs(Raw);
        Wrap := AutoWrap;
        if Value.StartsWith(':') then
            if Value.StartsWith(':wrap:') or Value.StartsWith(':nowrap:') then
                Value := CopyStr(Value, 2);
        if Value.StartsWith('wrap:') then begin
            Wrap := true;
            Value := CopyStr(Value, 6);
        end else
            if Value.StartsWith('nowrap:') then begin
                Wrap := false;
                Value := CopyStr(Value, 8);
            end;
        exit(MText.TrimWs(Value));
    end;

    local procedure ReadText(var Wrap: Boolean): Text
    var
        EndPos: Integer;
        Raw: Text;
    begin
        SkipSameLine();
        if Cur() <> 58 then
            Fail('''TXT''');
        EndPos := LineRun(Pos + 1);
        Raw := MText.Substr(Src, Pos + 1, EndPos);
        Pos := EndPos;
        exit(ParseMessage(Raw, Wrap));
    end;

    local procedure RestOfLine(): Text
    var
        EndPos: Integer;
        Value: Text;
    begin
        SkipSameLine();
        if Cur() = 35 then begin
            SkipToEol();
            exit('');
        end;
        EndPos := LineRun(Pos);
        Value := MText.Substr(Src, Pos, EndPos);
        Pos := EndPos;
        exit(Value);
    end;

    // ---------------------------------------------------------------- model

    local procedure FindActor(Id: Text): Boolean
    begin
        TempActor.Reset();
        TempActor.SetCurrentKey(Id);
        TempActor.SetRange(Id, CopyStr(Id, 1, MaxStrLen(TempActor.Id)));
        if TempActor.FindFirst() then begin
            TempActor.Reset();
            exit(true);
        end;
        TempActor.Reset();
        exit(false);
    end;

    local procedure AddActor(Id: Text; HasDescription: Boolean; Description: Text; DescriptionWrap: Boolean; Kind: Text; Declared: Boolean)
    begin
        if FindActor(Id) then begin
            if Declared then begin
                if HasDescription then begin
                    TempActor.Description := CopyStr(Description, 1, MaxStrLen(TempActor.Description));
                    TempActor.Wrap := DescriptionWrap;
                end;
                if Kind <> '' then
                    TempActor.Kind := CopyStr(Kind, 1, MaxStrLen(TempActor.Kind));
                if (CurrentBox <> 0) and (TempActor."Box No." = 0) then
                    TempActor."Box No." := CurrentBox;
                TempActor.Modify();
            end;
            exit;
        end;
        NextActorNo += 1;
        TempActor.Init();
        TempActor."Entry No." := NextActorNo;
        TempActor.Id := CopyStr(Id, 1, MaxStrLen(TempActor.Id));
        if HasDescription then begin
            TempActor.Description := CopyStr(Description, 1, MaxStrLen(TempActor.Description));
            TempActor.Wrap := DescriptionWrap;
        end else begin
            TempActor.Description := CopyStr(Id, 1, MaxStrLen(TempActor.Description));
            TempActor.Wrap := AutoWrap;
        end;
        if Kind = '' then
            Kind := 'participant';
        TempActor.Kind := CopyStr(Kind, 1, MaxStrLen(TempActor.Kind));
        TempActor."Box No." := CurrentBox;
        TempActor."Created At" := -1;
        TempActor."Destroyed At" := -1;
        TempActor.Insert();
    end;

    local procedure AddMessage(LineType: Integer; FromId: Text; ToId: Text; MessageText: Text; Wrap: Boolean; Placement: Integer)
    begin
        NextMsgNo += 1;
        TempMsg.Init();
        TempMsg."Entry No." := NextMsgNo;
        TempMsg."Line Type" := LineType;
        TempMsg."From Id" := CopyStr(FromId, 1, MaxStrLen(TempMsg."From Id"));
        TempMsg."To Id" := CopyStr(ToId, 1, MaxStrLen(TempMsg."To Id"));
        TempMsg.Message := CopyStr(MessageText, 1, MaxStrLen(TempMsg.Message));
        TempMsg.Wrap := Wrap;
        TempMsg.Placement := Placement;
        TempMsg.Insert();
    end;

    local procedure ActivationCount(Id: Text): Integer
    var
        Cnt: Integer;
    begin
        TempMsg.Reset();
        if TempMsg.FindSet() then
            repeat
                if TempMsg."From Id" = Id then
                    if TempMsg."Line Type" = 17 then
                        Cnt += 1
                    else
                        if TempMsg."Line Type" = 18 then
                            Cnt -= 1;
            until TempMsg.Next() = 0;
        exit(Cnt);
    end;

    local procedure AddSignal(LineType: Integer; Id: Text)
    begin
        if LineType = 18 then
            if ActivationCount(Id) < 1 then
                MText.Fail('Trying to inactivate an inactive participant (' + Id + ')');
        AddMessage(LineType, Id, '', '', false, 0);
    end;

    // ---------------------------------------------------------------- parsing

    procedure Parse(Source: Text; FrontTitle: Text; var Config: Dictionary of [Text, Text])
    begin
        TempActor.Reset();
        TempActor.DeleteAll();
        TempMsg.Reset();
        TempMsg.DeleteAll();
        Clear(BoxNames);
        Clear(BoxFills);
        Clear(BoxWraps);
        Clear(FrameKinds);
        SeqTitle := FrontTitle;
        AccTitle := '';
        AccDescr := '';
        CurrentBox := 0;
        NextActorNo := 0;
        NextMsgNo := 0;
        AutoWrap := MText.ConfigBool(Config, 'wrap', false) or MText.ConfigBool(Config, 'sequence.wrap', false);
        Src := Source;
        SrcLen := StrLen(Src);
        Pos := 1;
        while MText.IsSpace(Cur()) do
            Pos += 1;
        if not CiWord('sequencediagram') then
            Fail('''SD''');
        Pos += 15;
        while Pos <= SrcLen do
            Statement();
        if FrameKinds.Count() > 0 then
            Fail('''end''');
    end;

    local procedure Statement()
    var
        C: Integer;
    begin
        SkipSameLine();
        C := Cur();
        if C = -1 then
            exit;
        if (C = 10) or (C = 59) then begin
            Pos += 1;
            exit;
        end;
        if (C = 35) or ((C = 37) and (CharAtP(Pos + 1) <> 123)) then begin
            SkipToEol();
            exit;
        end;
        if InBox() then begin
            if CiWord('participant') then
                Participant('participant', 11, false)
            else
                if CiWord('actor') then
                    Participant('actor', 5, false)
                else
                    if CiWord('destroy') then
                        Destroy()
                    else
                        if CiWord('end') then
                            EndBlock()
                        else
                            Fail('''end'', ''NEWLINE'', ''participant'', ''participant_actor'', ''destroy''');
            exit;
        end;
        if Keywords() then
            exit;
        Signal();
    end;

    local procedure InBox(): Boolean
    begin
        if FrameKinds.Count() = 0 then
            exit(false);
        exit(FrameKinds.Get(FrameKinds.Count()) = 0);
    end;

    local procedure Keywords(): Boolean
    var
        Close: Integer;
    begin
        case true of
            CiWord('participant'):
                Participant('participant', 11, false);
            CiWord('actor'):
                Participant('actor', 5, false);
            CiWord('create'):
                begin
                    Pos += 6;
                    SkipSameLine();
                    if CiWord('participant') then
                        Participant('participant', 11, true)
                    else
                        if CiWord('actor') then
                            Participant('actor', 5, true)
                        else
                            Fail('''participant'', ''participant_actor'', ''destroy''');
                end;
            CiWord('destroy'):
                Destroy();
            CiWord('box'):
                begin
                    Pos += 3;
                    OpenBox(RestOfLine());
                end;
            CiWord('loop'):
                OpenBlock(4, 1, 10);
            CiWord('rect'):
                OpenBlock(4, 2, 22);
            CiWord('opt'):
                OpenBlock(3, 3, 15);
            CiWord('break'):
                OpenBlock(5, 4, 30);
            CiWord('alt'):
                OpenBlock(3, 5, 12);
            CiWord('par_over'):
                OpenBlock(8, 6, 32);
            CiWord('par'):
                OpenBlock(3, 6, 19);
            CiWord('critical'):
                OpenBlock(8, 7, 27);
            CiWord('else'):
                Divider(4, 5, 13);
            CiWord('and'):
                Divider(3, 6, 20);
            CiWord('option'):
                Divider(6, 7, 28);
            CiWord('end'):
                EndBlock();
            CiWord('note'):
                Note();
            CiWord('autonumber'):
                Autonumber();
            CiWord('activate'):
                begin
                    Pos += 8;
                    AddSignal(17, ReadIdName());
                    ExpectNewline();
                end;
            CiWord('deactivate'):
                begin
                    Pos += 10;
                    AddSignal(18, ReadIdName());
                    ExpectNewline();
                end;
            CiAt(Pos, 'title') and ((CharAtP(Pos + 5) = 58) or MText.IsSpace(CharAtP(Pos + 5))):
                begin
                    Pos += 5;
                    if Cur() = 58 then
                        Pos += 1;
                    SeqTitle := MText.TrimWs(RestOfLine());
                end;
            CiAt(Pos, 'acctitle') and (CharAtP(SkipWs(Pos + 8)) = 58):
                begin
                    Pos := SkipWs(SkipWs(Pos + 8) + 1);
                    AccTitle := MText.TrimWs(RawToEol());
                end;
            CiAt(Pos, 'accdescr') and (CharAtP(SkipWs(Pos + 8)) = 58):
                begin
                    Pos := SkipWs(SkipWs(Pos + 8) + 1);
                    AccDescr := MText.TrimWs(RawToEol());
                end;
            CiAt(Pos, 'accdescr') and (CharAtP(SkipWs(Pos + 8)) = 123):
                begin
                    Pos := SkipWs(SkipWs(Pos + 8) + 1);
                    Close := MText.IndexOfFrom(Src, '}', Pos);
                    if Close = 0 then
                        Close := SrcLen + 1;
                    AccDescr := MText.TrimWs(MText.Substr(Src, Pos, Close));
                    Pos := Close + 1;
                end;
            IsMenu('links'), IsMenu('link'), IsMenu('properties'), IsMenu('details'):
                SkipToEol();
            else
                exit(false);
        end;
        exit(true);
    end;

    local procedure IsMenu(Lit: Text): Boolean
    begin
        exit(CiAt(Pos, Lit) and MText.IsBlank(CharAtP(Pos + StrLen(Lit))));
    end;

    local procedure SkipWs(P: Integer): Integer
    begin
        while MText.IsSpace(CharAtP(P)) do
            P += 1;
        exit(P);
    end;

    local procedure RawToEol(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        SkipToEol();
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    /// <summary>A participant name up to an alias, a config object, or the end of the statement.</summary>
    local procedure ReadIdName(): Text
    var
        StartPos: Integer;
        Name: Text;
    begin
        SkipSameLine();
        StartPos := Pos;
        while IsIdChar(Cur(), true) and (Cur() <> 35) do
            Pos += 1;
        Name := MText.TrimWs(MText.Substr(Src, StartPos, Pos));
        if Name = '' then
            Fail('''ACTOR''');
        exit(Name);
    end;

    local procedure Participant(Keyword: Text; Len: Integer; Created: Boolean)
    var
        Id: Text;
        Alias: Text;
        HasAlias: Boolean;
        AliasWrap: Boolean;
        Kind: Text;
        A: Integer;
        W: Integer;
        Close: Integer;
        ConfigText: Text;
    begin
        Pos += Len;
        SkipSameLine();
        Kind := Keyword;
        A := Pos;
        while IsIdChar(CharAtP(A), false) do
            A += 1;
        W := A;
        while MText.IsBlank(CharAtP(W)) do
            W += 1;
        if (A > Pos) and (CharAtP(W) = 64) and (CharAtP(W + 1) = 123) then begin
            Id := MText.Substr(Src, Pos, A);
            Close := MText.IndexOfFrom(Src, '}', W);
            if Close = 0 then
                Fail('''CONFIG_END''');
            ConfigText := MText.Substr(Src, W + 2, Close);
            Kind := ConfigType(ConfigText, Kind, Alias, HasAlias);
            Pos := Close + 1;
            SkipSameLine();
            if CiWord('as') then begin
                Pos += 2;
                Alias := RestOfLine();
                HasAlias := true;
            end;
        end else
            if (A > Pos) and (W > A) and CiAt(W, 'as') and MText.IsSpace(CharAtP(W + 2)) then begin
                Id := MText.Substr(Src, Pos, A);
                Pos := W + 2;
                Alias := RestOfLine();
                HasAlias := true;
            end else
                Id := ReadIdName();
        if HasAlias then
            Alias := ParseMessage(Alias, AliasWrap);
        AddActor(Id, HasAlias, Alias, AliasWrap, Kind, true);
        if Created then
            if FindActor(Id) then begin
                TempActor."Created At" := NextMsgNo;
                TempActor.Modify();
            end;
        ExpectNewline();
    end;

    /// <summary>Reads "type" and "alias" from a participant's @{ ... } config.</summary>
    local procedure ConfigType(ConfigText: Text; Fallback: Text; var Alias: Text; var HasAlias: Boolean): Text
    var
        Pair: Text;
        Colon: Integer;
        KeyName: Text;
        Value: Text;
        Result: Text;
    begin
        Result := Fallback;
        foreach Pair in ConfigText.Replace(MText.LF(), ',').Split(',') do begin
            Colon := StrPos(Pair, ':');
            if Colon > 0 then begin
                KeyName := MText.TrimWs(CopyStr(Pair, 1, Colon - 1)).Replace('"', '').Replace('''', '');
                Value := MText.TrimWs(CopyStr(Pair, Colon + 1)).Replace('"', '').Replace('''', '');
                if KeyName = 'type' then
                    Result := Value;
                if KeyName = 'alias' then begin
                    Alias := Value;
                    HasAlias := true;
                end;
            end;
        end;
        exit(Result);
    end;

    local procedure Destroy()
    var
        Id: Text;
    begin
        Pos += 7;
        Id := ReadIdName();
        AddActor(Id, false, '', false, '', false);
        if FindActor(Id) then begin
            TempActor."Destroyed At" := NextMsgNo;
            TempActor.Modify();
        end;
        ExpectNewline();
    end;

    local procedure OpenBox(Raw: Text)
    var
        Color: Text;
        BoxTitle: Text;
        Wrap: Boolean;
        Close: Integer;
        Space: Integer;
        Trimmed: Text;
    begin
        Trimmed := MText.TrimWs(Raw);
        Color := '';
        BoxTitle := '';
        if LowerCase(Trimmed).StartsWith('rgb') or LowerCase(Trimmed).StartsWith('hsl') then begin
            Close := StrPos(Trimmed, ')');
            if Close > 0 then begin
                Color := CopyStr(Trimmed, 1, Close);
                BoxTitle := MText.TrimWs(CopyStr(Trimmed, Close + 1));
            end;
        end else begin
            Space := 0;
            while (Space < StrLen(Trimmed)) and not MText.IsSpace(MText.CharAt(Trimmed, Space + 1)) do
                Space += 1;
            Color := CopyStr(Trimmed, 1, Space);
            BoxTitle := MText.TrimWs(CopyStr(Trimmed, Space + 1));
        end;
        if not IsCssColor(Color) then begin
            Color := 'transparent';
            BoxTitle := Trimmed;
        end;
        Wrap := AutoWrap;
        if BoxTitle <> '' then
            BoxTitle := ParseMessage(BoxTitle, Wrap);
        BoxNames.Add(BoxTitle);
        BoxFills.Add(Color);
        BoxWraps.Add(Wrap);
        CurrentBox := BoxNames.Count();
        FrameKinds.Add(0);
    end;

    local procedure IsCssColor(Value: Text): Boolean
    var
        Lower: Text;
        I: Integer;
        Names: Text;
    begin
        Lower := LowerCase(Value);
        if Lower = '' then
            exit(false);
        if Lower.StartsWith('#') then begin
            if not (StrLen(Lower) in [4, 5, 7, 9]) then
                exit(false);
            for I := 2 to StrLen(Lower) do
                if not MText.IsHex(Lower[I]) then
                    exit(false);
            exit(true);
        end;
        if Lower.StartsWith('rgb(') or Lower.StartsWith('rgba(') or Lower.StartsWith('hsl(') or Lower.StartsWith('hsla(') then
            exit(Lower.EndsWith(')'));
        Names := ',transparent,aliceblue,antiquewhite,aqua,aquamarine,azure,beige,bisque,black,blanchedalmond,blue,blueviolet,brown,burlywood,cadetblue,chartreuse,chocolate,coral,cornflowerblue,cornsilk,crimson,cyan,darkblue,darkcyan,darkgoldenrod,darkgray,darkgreen,darkgrey,darkkhaki,darkmagenta,darkolivegreen,darkorange,darkorchid,darkred,darksalmon,darkseagreen,darkslateblue,darkslategray,darkslategrey,darkturquoise,darkviolet,deeppink,deepskyblue,dimgray,dimgrey,dodgerblue,firebrick,floralwhite,forestgreen,fuchsia,gainsboro,ghostwhite,gold,goldenrod,gray,green,greenyellow,grey,honeydew,hotpink,indianred,indigo,ivory,khaki,lavender,lavenderblush,lawngreen,lemonchiffon,lightblue,lightcoral,lightcyan,lightgoldenrodyellow,lightgray,lightgreen,lightgrey,lightpink,lightsalmon,lightseagreen,lightskyblue,lightslategray,lightslategrey,lightsteelblue,lightyellow,lime,limegreen,linen,magenta,maroon,mediumaquamarine,mediumblue,mediumorchid,mediumpurple,mediumseagreen,mediumslateblue,mediumspringgreen,mediumturquoise,mediumvioletred,midnightblue,mintcream,mistyrose,moccasin,navajowhite,navy,oldlace,olive,olivedrab,orange,orangered,orchid,palegoldenrod,palegreen,paleturquoise,palevioletred,papayawhip,peachpuff,peru,pink,plum,powderblue,purple,rebeccapurple,red,rosybrown,royalblue,saddlebrown,salmon,sandybrown,seagreen,seashell,sienna,silver,skyblue,slateblue,slategray,slategrey,snow,springgreen,steelblue,tan,teal,thistle,tomato,turquoise,violet,wheat,white,whitesmoke,yellow,yellowgreen,';
        exit(StrPos(Names, ',' + Lower + ',') > 0);
    end;

    /// <summary>Kind: 1 loop, 2 rect, 3 opt, 4 break, 5 alt, 6 par, 7 critical.</summary>
    local procedure OpenBlock(Len: Integer; Kind: Integer; StartType: Integer)
    var
        Wrap: Boolean;
        TextValue: Text;
    begin
        Pos += Len;
        TextValue := ParseMessage(RestOfLine(), Wrap);
        FrameKinds.Add(Kind);
        AddMessage(StartType, '', '', TextValue, Wrap, 0);
    end;

    local procedure Divider(Len: Integer; Kind: Integer; LineType: Integer)
    var
        Wrap: Boolean;
        TextValue: Text;
    begin
        if FrameKinds.Count() = 0 then
            Fail('''end''');
        if FrameKinds.Get(FrameKinds.Count()) <> Kind then
            Fail('''end''');
        Pos += Len;
        TextValue := ParseMessage(RestOfLine(), Wrap);
        AddMessage(LineType, '', '', TextValue, Wrap, 0);
    end;

    local procedure EndBlock()
    var
        Kind: Integer;
    begin
        if FrameKinds.Count() = 0 then
            Fail('''NEWLINE'', ''EOF''');
        Pos += 3;
        Kind := FrameKinds.Get(FrameKinds.Count());
        FrameKinds.RemoveAt(FrameKinds.Count());
        case Kind of
            0:
                CurrentBox := 0;
            1:
                AddMessage(11, '', '', '', false, 0);
            2:
                AddMessage(23, '', '', '', false, 0);
            3:
                AddMessage(16, '', '', '', false, 0);
            4:
                AddMessage(31, '', '', '', false, 0);
            5:
                AddMessage(14, '', '', '', false, 0);
            6:
                AddMessage(21, '', '', '', false, 0);
            7:
                AddMessage(29, '', '', '', false, 0);
        end;
    end;

    local procedure Note()
    var
        First: Text;
        Second: Text;
        Placement: Integer;
        TextValue: Text;
        Wrap: Boolean;
    begin
        Pos += 4;
        SkipSameLine();
        if CiWord('over') then begin
            Pos += 4;
            First := ReadActor();
            Second := First;
            SkipSameLine();
            if Cur() = 44 then begin
                Pos += 1;
                Second := ReadActor();
            end;
            Placement := 2;
        end else
            if CiAt(Pos, 'left of') and not MText.IsWord(CharAtP(Pos + 7)) then begin
                Pos += 7;
                First := ReadActor();
                Second := First;
                Placement := 0;
            end else
                if CiAt(Pos, 'right of') and not MText.IsWord(CharAtP(Pos + 8)) then begin
                    Pos += 8;
                    First := ReadActor();
                    Second := First;
                    Placement := 1;
                end else
                    Fail('''over'', ''left_of'', ''right_of''');
        TextValue := ReadText(Wrap);
        AddActor(First, false, '', false, '', false);
        AddActor(Second, false, '', false, '', false);
        AddMessage(2, First, Second, TextValue, Wrap, Placement);
        ExpectNewline();
    end;

    local procedure ReadNum(var Value: Decimal): Boolean
    var
        StartPos: Integer;
        Q: Integer;
    begin
        StartPos := Pos;
        Q := Pos;
        while MText.IsDigit(CharAtP(Q)) do
            Q += 1;
        if (CharAtP(Q) = 46) and MText.IsDigit(CharAtP(Q + 1)) then begin
            Q += 2;
            if MText.IsDigit(CharAtP(Q)) then
                Q += 1;
        end;
        if (Q = StartPos) or not (CharAtP(Q) in [32, 10, -1, 59, 9]) then
            exit(false);
        if not Evaluate(Value, MText.Substr(Src, StartPos, Q), 9) then
            exit(false);
        Pos := Q;
        exit(true);
    end;

    local procedure Autonumber()
    var
        StartValue: Decimal;
        StepValue: Decimal;
        Visible: Boolean;
    begin
        Pos += 10;
        SkipSameLine();
        Visible := true;
        if ReadNum(StartValue) then begin
            StepValue := 1;
            SkipSameLine();
            if ReadNum(StepValue) then;
        end else
            if CiWord('off') then begin
                Pos += 3;
                Visible := false;
            end;
        ExpectNewline();
        AddMessage(26, '', '', '', false, 0);
        TempMsg."Number Start" := StartValue;
        TempMsg."Number Step" := StepValue;
        TempMsg."Number Visible" := Visible;
        TempMsg.Modify();
    end;

    local procedure Signal()
    var
        FromId: Text;
        ToId: Text;
        LineType: Integer;
        Mark: Integer;
        TextValue: Text;
        Wrap: Boolean;
    begin
        FromId := ReadActor();
        SkipSameLine();
        if (Cur() = 40) and (CharAtP(Pos + 1) = 41) then
            Pos += 2;
        LineType := ReadArrow();
        if LineType < 0 then
            Fail('''SOLID_OPEN_ARROW'', ''DOTTED_OPEN_ARROW'', ''SOLID_ARROW'', ''DOTTED_ARROW'', ''SOLID_CROSS'', ''DOTTED_CROSS'', ''SOLID_POINT'', ''DOTTED_POINT''');
        SkipSameLine();
        Mark := 0;
        if (Cur() = 43) or (Cur() = 45) then begin
            Mark := Cur();
            Pos += 1;
        end else
            if (Cur() = 40) and (CharAtP(Pos + 1) = 41) then
                Pos += 2;
        ToId := ReadActor();
        TextValue := ReadText(Wrap);
        ExpectNewline();
        AddActor(FromId, false, '', false, '', false);
        AddActor(ToId, false, '', false, '', false);
        AddMessage(LineType, FromId, ToId, TextValue, Wrap, 0);
        if Mark = 43 then
            AddSignal(17, ToId)
        else
            if Mark = 45 then
                AddSignal(18, FromId);
    end;

    // ---------------------------------------------------------------- rendering helpers

    local procedure SeqOption(var Config: Dictionary of [Text, Text]; KeyName: Text; Fallback: Decimal): Decimal
    var
        Value: Decimal;
    begin
        if MText.ConfigNumber(Config, 'sequence.' + KeyName, Value) then
            if (Value >= 0) and (Value <= 2000) then
                exit(Value);
        exit(Fallback);
    end;

    local procedure SeqLabel(var Lbl: Codeunit "Mermaid Label"; Raw: Text; FontSize: Decimal; Wrap: Boolean; Width: Decimal; Base: Integer)
    begin
        if Wrap then
            Lbl.Layout(Raw, false, FontSize, Width, Base)
        else
            Lbl.Layout(Raw, false, FontSize, 100000, Base);
    end;

    local procedure IsFigure(Kind: Text): Boolean
    begin
        exit(Kind in ['actor', 'boundary', 'control', 'entity', 'database']);
    end;

    local procedure ActorKind(TypeName: Text): Text
    begin
        if TypeName in ['participant', 'actor', 'boundary', 'control', 'entity', 'database', 'collections', 'queue'] then
            exit(TypeName);
        exit('participant');
    end;

    local procedure ActorSize(Kind: Text; var Lbl: Codeunit "Mermaid Label"; MinW: Decimal; MinH: Decimal; var W: Decimal; var H: Decimal)
    var
        Extra: Decimal;
    begin
        if IsFigure(Kind) then begin
            W := MText.MaxDec(40, Lbl.GetWidth() + 8);
            H := 34;
            if Lbl.GetHeight() > 0 then
                H += 4 + Lbl.GetHeight();
            exit;
        end;
        if Kind = 'collections' then
            Extra := 5
        else
            if Kind = 'queue' then
                Extra := 12;
        W := MText.MaxDec(MinW, Lbl.GetWidth() + 32) + Extra;
        H := MText.MaxDec(MinH, Lbl.GetHeight() + 20);
        if Kind = 'collections' then
            H += 5;
    end;

    local procedure N(Value: Decimal): Text
    begin
        exit(MText.Num(Value));
    end;

    local procedure Figure(Kind: Text; Cx: Decimal; Top: Decimal): Text
    var
        ShapeAttr: Text;
        LineAttr: Text;
        X: Text;
        L: Text;
        R: Text;
    begin
        ShapeAttr := ' fill="var(--_s)" stroke="var(--_b)"';
        LineAttr := ' fill="none" stroke="var(--_b)"';
        X := N(Cx);
        case Kind of
            'actor':
                exit('<circle cx="' + X + '" cy="' + N(Top + 7) + '" r="6"' + ShapeAttr + '/>' +
                     '<path d="M' + X + ',' + N(Top + 13) + 'V' + N(Top + 24) + 'M' + N(Cx - 10) + ',' + N(Top + 17) + 'H' + N(Cx + 10) +
                     'M' + N(Cx - 8) + ',' + N(Top + 34) + 'L' + X + ',' + N(Top + 24) + 'L' + N(Cx + 8) + ',' + N(Top + 34) + '"' + LineAttr + '/>');
            'boundary':
                exit('<path d="M' + N(Cx - 19) + ',' + N(Top + 6) + 'V' + N(Top + 28) + 'M' + N(Cx - 19) + ',' + N(Top + 17) + 'H' + N(Cx - 8) + '"' + LineAttr + '/>' +
                     '<circle cx="' + N(Cx + 3) + '" cy="' + N(Top + 17) + '" r="11"' + ShapeAttr + '/>');
            'control':
                exit('<circle cx="' + X + '" cy="' + N(Top + 21) + '" r="11"' + ShapeAttr + '/>' +
                     '<path d="M' + N(Cx + 5) + ',' + N(Top + 5) + 'L' + N(Cx - 1) + ',' + N(Top + 10) + 'L' + N(Cx + 5) + ',' + N(Top + 15) + '"' + LineAttr + '/>');
            'entity':
                exit('<circle cx="' + X + '" cy="' + N(Top + 15) + '" r="11"' + ShapeAttr + '/>' +
                     '<path d="M' + N(Cx - 11) + ',' + N(Top + 30) + 'H' + N(Cx + 11) + '"' + LineAttr + '/>');
        end;
        L := N(Cx - 14);
        R := N(Cx + 14);
        exit('<path d="M' + L + ',' + N(Top + 7) + 'V' + N(Top + 27) + 'A14,5 0 0 0 ' + R + ',' + N(Top + 27) + 'V' + N(Top + 7) + 'A14,5 0 0 0 ' + L + ',' + N(Top + 7) + 'Z"' + ShapeAttr + '/>' +
             '<path d="M' + L + ',' + N(Top + 7) + 'A14,5 0 0 0 ' + R + ',' + N(Top + 7) + '"' + LineAttr + '/>');
    end;

    /// <summary>Draws a participant whose bounding box has its top centre at (Cx, Top).</summary>
    local procedure DrawActor(Kind: Text; Cx: Decimal; Top: Decimal; W: Decimal; H: Decimal; var Lbl: Codeunit "Mermaid Label"): Text
    var
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Left: Decimal;
        Bw: Decimal;
        Bh: Decimal;
        L: Text;
        R: Text;
        B: Text;
        Ry: Text;
    begin
        ShapeAttr := ' fill="var(--_s)" stroke="var(--_b)"';
        LineAttr := ' fill="none" stroke="var(--_b)"';
        TextAttr := ' class="pele-label"';
        if IsFigure(Kind) then
            exit(Figure(Kind, Cx, Top) + Lbl.ToSvg(Cx, Top + 34 + 4 + Lbl.GetHeight() / 2, TextAttr));
        Left := Cx - W / 2;
        if Kind = 'collections' then begin
            Bw := W - 5;
            Bh := H - 5;
            exit('<rect x="' + N(Left + 5) + '" y="' + N(Top) + '" width="' + N(Bw) + '" height="' + N(Bh) + '" rx="' + Builder.Radius() + '"' + ShapeAttr + '/>' +
                 '<rect x="' + N(Left) + '" y="' + N(Top + 5) + '" width="' + N(Bw) + '" height="' + N(Bh) + '" rx="' + Builder.Radius() + '"' + ShapeAttr + '/>' +
                 Lbl.ToSvg(Left + Bw / 2, Top + 5 + Bh / 2, TextAttr));
        end;
        if Kind = 'queue' then begin
            L := N(Left + 6);
            R := N(Left + W - 6);
            B := N(Top + H);
            Ry := N(H / 2);
            exit('<path d="M' + L + ',' + N(Top) + 'H' + R + 'A6,' + Ry + ' 0 0 1 ' + R + ',' + B + 'H' + L + 'A6,' + Ry + ' 0 0 1 ' + L + ',' + N(Top) + 'Z"' + ShapeAttr + '/>' +
                 '<path d="M' + R + ',' + N(Top) + 'A6,' + Ry + ' 0 0 0 ' + R + ',' + B + '"' + LineAttr + '/>' +
                 Lbl.ToSvg(Cx - 3, Top + H / 2, TextAttr));
        end;
        exit('<rect x="' + N(Left) + '" y="' + N(Top) + '" width="' + N(W) + '" height="' + N(H) + '" rx="' + Builder.Radius() + '"' + ShapeAttr + '/>' +
             Lbl.ToSvg(Cx, Top + H / 2, TextAttr));
    end;

    local procedure HalfHead(X: Decimal; Y: Decimal; Dir: Decimal; Up: Decimal; Stick: Boolean): Text
    var
        Bx: Text;
    begin
        Bx := N(X - Dir * Builder.Arrow());
        if Stick then
            exit('<path class="pele-marker" d="M' + N(X) + ',' + N(Y) + 'L' + Bx + ',' + N(Y + Up * 5) + '"/>');
        exit('<path class="pele-marker" d="M' + N(X) + ',' + N(Y) + 'L' + Bx + ',' + N(Y + Up * 4.5) + 'V' + N(Y) + 'Z" fill="var(--_l)" stroke="none"/>');
    end;

    /// <summary>Draws the head whose tip is at (X, Y) and points along Dir. Up is the side a half head sits on.</summary>
    local procedure HeadSvg(Head: Integer; X: Decimal; Y: Decimal; Dir: Decimal; Up: Decimal): Text
    begin
        case Head of
            1:
                exit(Builder.Marker('arrow_point', X, Y, Dir, 0, 'var(--_l)'));
            2:
                exit(Builder.Marker('arrow_cross', X, Y, Dir, 0, 'var(--_l)'));
            3:
                exit('<path class="pele-marker" d="M' + N(X - Dir * Builder.Arrow()) + ',' + N(Y - 4.5) + 'L' + N(X) + ',' + N(Y) + 'L' + N(X - Dir * Builder.Arrow()) + ',' + N(Y + 4.5) + '" stroke-linejoin="round"/>');
            4:
                exit(HalfHead(X, Y, Dir, Up, false));
            5:
                exit(HalfHead(X, Y, Dir, Up, true));
        end;
        exit('');
    end;

    local procedure HeadTrim(Head: Integer): Decimal
    begin
        if Head = 1 then
            exit(Builder.Arrow() - 1);
        if Head = 2 then
            exit(4);
        exit(0);
    end;

    local procedure Extend(X0: Decimal; X1: Decimal)
    begin
        if X0 < MinX then
            MinX := X0;
        if X1 > MaxX then
            MaxX := X1;
    end;

    local procedure ActCount(Col: Integer): Integer
    var
        I: Integer;
        Cnt: Integer;
    begin
        for I := 1 to ActCol.Count() do
            if ActCol.Get(I) = Col then
                Cnt += 1;
        exit(Cnt);
    end;

    local procedure LeftEdge(Col: Integer; Extra: Integer): Decimal
    begin
        TempActor.Get(Col);
        if ActCount(Col) + Extra > 0 then
            exit(TempActor.X - ActW / 2);
        exit(TempActor.X);
    end;

    local procedure RightEdge(Col: Integer; Extra: Integer): Decimal
    var
        Depth: Integer;
    begin
        TempActor.Get(Col);
        Depth := ActCount(Col) + Extra;
        if Depth > 0 then
            exit(TempActor.X + ActW / 2 + (Depth - 1) * ActStep);
        exit(TempActor.X);
    end;

    local procedure EndActivation(Col: Integer; EndY: Decimal): Decimal
    var
        I: Integer;
        Last: Integer;
        StartY: Decimal;
        BottomY: Decimal;
        X: Decimal;
    begin
        for I := 1 to ActCol.Count() do
            if ActCol.Get(I) = Col then
                Last := I;
        StartY := ActY.Get(Last);
        ActCol.RemoveAt(Last);
        ActY.RemoveAt(Last);
        BottomY := MText.MaxDec(EndY, StartY + 14);
        TempActor.Get(Col);
        X := TempActor.X - ActW / 2 + ActCount(Col) * ActStep;
        Extend(X, X + ActW);
        ActivationsOut.Add('<rect class="pele-activation" data-id="' + MText.EscText(TempActor.Id) + '" x="' + N(X) + '" y="' + N(StartY) + '" width="' + N(ActW) +
                           '" height="' + N(BottomY - StartY) + '" rx="2"/>');
        exit(BottomY);
    end;

    /// <summary>The lifeline of a destroyed participant ends in a cross a little below the message that ends it.</summary>
    local procedure DestroyCol(Col: Integer; LineY: Decimal): Decimal
    var
        Cx: Decimal;
        Cy: Decimal;
    begin
        TempActor.Get(Col);
        Cx := TempActor.X;
        Cy := LineY + 16;
        TempActor."Life End" := Cy;
        TempActor.Modify();
        CrossesOut.Append('<path class="pele-destroy" data-id="' + MText.EscText(TempActor.Id) + '" d="M' + N(Cx - 6) + ',' + N(Cy - 6) + 'L' + N(Cx + 6) + ',' + N(Cy + 6) +
                          'M' + N(Cx + 6) + ',' + N(Cy - 6) + 'L' + N(Cx - 6) + ',' + N(Cy + 6) + '"/>');
        exit(Cy + 6);
    end;

    /// <summary>Whether a lifeline runs between two x positions, where text would be struck through.</summary>
    local procedure Crosses(X0: Decimal; X1: Decimal): Boolean
    var
        X: Decimal;
    begin
        foreach X in ColXs do
            if (X > X0) and (X < X1) then
                exit(true);
        exit(false);
    end;

    local procedure Backed(var Lbl: Codeunit "Mermaid Label"; Cx: Decimal; Cy: Decimal; Attrs: Text): Text
    var
        L: Decimal;
        Back: Text;
    begin
        if Lbl.GetWidth() = 0 then
            exit('');
        L := Cx - Lbl.GetWidth() / 2;
        if Crosses(L, L + Lbl.GetWidth()) then
            Back := '<rect x="' + N(L - 3) + '" y="' + N(Cy - Lbl.GetHeight() / 2 + 2) + '" width="' + N(Lbl.GetWidth() + 6) + '" height="' + N(Lbl.GetHeight() - 4) + '" rx="3" fill="var(--_bg)" stroke="none"/>';
        exit(Back + Lbl.ToSvg(Cx, Cy, Attrs));
    end;

    local procedure ActorLabel(var Lbl: Codeunit "Mermaid Label")
    begin
        SeqLabel(Lbl, TempActor.Description, Size, TempActor.Wrap, WrapW, 0);
    end;

    local procedure ActorSvg(Col: Integer; Top: Decimal; Footer: Boolean): Text
    var
        Lbl: Codeunit "Mermaid Label";
        FooterClass: Text;
    begin
        TempActor.Get(Col);
        ActorLabel(Lbl);
        if Footer then
            FooterClass := ' pele-actor-footer';
        exit('<g class="pele-node pele-actor pele-actor-' + ActorKind(TempActor.Kind) + FooterClass + '" data-id="' + MText.EscText(TempActor.Id) + '">' +
             DrawActor(ActorKind(TempActor.Kind), TempActor.X, Top, TempActor.Width, TempActor.Height, Lbl) + '</g>');
    end;

    local procedure Badge(Number: Decimal; Cx: Decimal; Cy: Decimal; W: Decimal): Text
    begin
        exit('<g class="pele-sequence-number"><rect x="' + N(Cx - W / 2) + '" y="' + N(Cy - BadgeH / 2) + '" width="' + N(W) + '" height="' + N(BadgeH) + '" rx="' + N(BadgeH / 2) +
             '" fill="var(--_l)" stroke="none"/><text x="' + N(Cx) + '" y="' + N(Cy + Tiny * 0.35) + '" text-anchor="middle" font-size="' + N(Tiny) + '" fill="var(--_bg)" stroke="none">' +
             MText.Esc(MText.DecText(Number)) + '</text></g>');
    end;

    local procedure BadgeWidth(): Decimal
    begin
        if not TempMsg."Number Shown" then
            exit(0);
        exit(MText.MaxDec(BadgeH, MText.Width(MText.DecText(TempMsg.Number), Tiny, 0) + 8));
    end;

    local procedure ColOf(Id: Text): Integer
    begin
        if Id = '' then
            exit(0);
        if FindActor(Id) then
            exit(TempActor."Entry No.");
        exit(0);
    end;

    local procedure NeedKey(Lo: Integer; Hi: Integer): Text
    begin
        exit(MText.IntText(Lo) + ',' + MText.IntText(Hi));
    end;

    local procedure Need(var Needs: Dictionary of [Text, Decimal]; Lo: Integer; Hi: Integer; LastCol: Integer; Width: Decimal)
    var
        Existing: Decimal;
    begin
        if (Lo < 1) or (Hi > LastCol) then
            exit;
        if Needs.Get(NeedKey(Lo, Hi), Existing) then begin
            if Existing < Width then
                Needs.Set(NeedKey(Lo, Hi), Width);
        end else
            Needs.Add(NeedKey(Lo, Hi), Width);
    end;

    local procedure FrameKindName(LineType: Integer): Text
    begin
        case LineType of
            10:
                exit('loop');
            12:
                exit('alt');
            15:
                exit('opt');
            19, 32:
                exit('par');
            27:
                exit('critical');
            30:
                exit('break');
            22:
                exit('rect');
        end;
        exit('');
    end;

    // ---------------------------------------------------------------- render

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        Lbl: Codeunit "Mermaid Label";
        TitleLbl: Codeunit "Mermaid Label";
        Needs: Dictionary of [Text, Decimal];
        NextLine: List of [Integer];
        Gaps: List of [Decimal];
        RunBox: List of [Integer];
        RunFirst: List of [Integer];
        RunLast: List of [Integer];
        RunGrow: List of [Decimal];
        SpanLo: List of [Integer];
        SpanHi: List of [Integer];
        SpanW: List of [Decimal];
        FrKind: List of [Text];
        FrX0: List of [Decimal];
        FrX1: List of [Decimal];
        FrTop: List of [Decimal];
        FrTabW: List of [Decimal];
        FrFill: List of [Text];
        FrTitle: List of [Text];
        FrTitleWrap: List of [Decimal];
        FrStartMsg: List of [Integer];
        DivFrame: List of [Integer];
        DivText: List of [Text];
        DivWrap: List of [Decimal];
        DivY: List of [Decimal];
        DivMsg: List of [Integer];
        Open: List of [Integer];
        Stack: List of [Integer];
        FramesOut: TextBuilder;
        EdgesOut: TextBuilder;
        LabelsOut: TextBuilder;
        NotesOut: TextBuilder;
        ActorsOut: TextBuilder;
        Lifelines: TextBuilder;
        BoxesOut: TextBuilder;
        Inner: TextBuilder;
        Content: Text;
        Pad: Decimal;
        Mirror: Boolean;
        RightAngles: Boolean;
        ActorMargin: Decimal;
        MinW: Decimal;
        MinH: Decimal;
        MsgGap: Decimal;
        NotePad: Decimal;
        BoxPad: Decimal;
        Align: Integer;
        MsgPad: Decimal;
        NoteOver: Decimal;
        FramePad: Decimal;
        FrameNest: Decimal;
        ShowNumbers: Boolean;
        Current: Decimal;
        StepValue: Decimal;
        Visible: Boolean;
        MsgCount: Integer;
        LastCol: Integer;
        I: Integer;
        K: Integer;
        M: Integer;
        A: Integer;
        B: Integer;
        F: Integer;
        Lo: Integer;
        Hi: Integer;
        W: Decimal;
        H: Decimal;
        X0: Decimal;
        X1: Decimal;
        Total: Decimal;
        Share: Decimal;
        Room: Decimal;
        Y: Decimal;
        Top: Decimal;
        BottomY: Decimal;
        LineY: Decimal;
        BoxTitleH: Decimal;
        BoxTop: Decimal;
        RowH: Decimal;
        HeadBottom: Decimal;
        FootH: Decimal;
        MinY: Decimal;
        Cx: Decimal;
        Lx: Decimal;
        Rx: Decimal;
        Bw: Decimal;
        Outer: Decimal;
        Dir: Decimal;
        Up: Decimal;
        FromX: Decimal;
        ToX: Decimal;
        Width: Integer;
        Height: Integer;
        KeyText: Text;
        Parts: List of [Text];
        Dotted: Boolean;
        Head: Integer;
        AtStart: Boolean;
        AtEnd: Boolean;
        Bottom: Boolean;
        TailAtEnd: Boolean;
        Starting: Integer;
        Creating: Boolean;
        Heads: Text;
        Attrs: Text;
        PathD: Text;
        Fill: Text;
        ShapeAttr: Text;
        LineAttr: Text;
        TextAttr: Text;
        Stroke: Text;
        IsBold: Boolean;
        IsItalic: Boolean;
        StyleSize: Decimal;
        FillDecl: List of [Text];
        Done: Boolean;
        HasFrame: Boolean;
        IsFrameStart: Boolean;
    begin
        Size := MText.FontSize();
        Small := Round(Size * 0.875, 1);
        Tiny := Round(Size * 0.75, 1);
        Pad := 8;
        ActW := 10;
        ActStep := 4;
        BadgeH := 16;
        Mirror := MText.ConfigBool(Config, 'sequence.mirrorActors', true);
        RightAngles := MText.ConfigBool(Config, 'sequence.rightAngles', false);
        ActorMargin := SeqOption(Config, 'actorMargin', 40);
        MinW := SeqOption(Config, 'width', 64);
        MinH := SeqOption(Config, 'height', Round(Size * 1.5, 1) + 20);
        WrapW := SeqOption(Config, 'width', 160);
        MsgGap := MText.MaxDec(4, 14 + SeqOption(Config, 'messageMargin', 35) - 35);
        NotePad := SeqOption(Config, 'noteMargin', 10);
        BoxPad := SeqOption(Config, 'boxMargin', 10);
        Align := 0;
        if MText.ConfigText(Config, 'sequence.messageAlign', '') = 'left' then
            Align := -1;
        if MText.ConfigText(Config, 'sequence.messageAlign', '') = 'right' then
            Align := 1;
        MsgPad := 12;
        NoteOver := 16;
        FramePad := 20;
        FrameNest := 10;
        ShowNumbers := MText.ConfigBool(Config, 'sequence.showSequenceNumbers', false);
        MinX := 1000000000;
        MaxX := -1000000000;
        Clear(ActCol);
        Clear(ActY);
        Clear(ActivationsOut);
        Clear(RectsOut);
        CrossesOut.Clear();
        Clear(ColXs);

        // Numbers, counted the way Mermaid's renderer does while it draws.
        MsgCount := TempMsg.Count();
        Current := 1;
        StepValue := 1;
        Visible := false;
        for I := 1 to MsgCount do begin
            TempMsg.Get(I);
            if TempMsg."Line Type" = 26 then begin
                if TempMsg."Number Start" <> 0 then
                    Current := TempMsg."Number Start";
                if TempMsg."Number Step" <> 0 then
                    StepValue := TempMsg."Number Step";
                Visible := TempMsg."Number Visible";
            end else
                if IsLineMessage(TempMsg."Line Type") then begin
                    TempMsg.Number := Current;
                    TempMsg."Number Shown" := Visible or ShowNumbers;
                    TempMsg.Modify();
                    Current := Round(Current + StepValue, 0.01);
                end;
        end;

        // The next message line at or after each entry.
        for I := 1 to MsgCount + 1 do
            NextLine.Add(0);
        for I := MsgCount downto 1 do begin
            TempMsg.Get(I);
            if IsLineMessage(TempMsg."Line Type") then
                NextLine.Set(I, I)
            else
                NextLine.Set(I, NextLine.Get(I + 1));
        end;

        // Columns.
        LastCol := TempActor.Count();
        for A := 1 to LastCol do begin
            TempActor.Get(A);
            ActorLabel(Lbl);
            ActorSize(ActorKind(TempActor.Kind), Lbl, MinW, MinH, W, H);
            TempActor.Width := W;
            TempActor.Height := H;
            TempActor."Life End" := -1;
            TempActor."Create Line" := 0;
            TempActor."Destroy Line" := 0;
            if TempActor."Created At" >= 0 then begin
                K := NextLine.Get(MinInt(TempActor."Created At" + 1, MsgCount + 1));
                if K > 0 then begin
                    TempMsg.Get(K);
                    if TempMsg."To Id" = TempActor.Id then
                        TempActor."Create Line" := K;
                end;
            end;
            if TempActor."Destroyed At" >= 0 then begin
                K := NextLine.Get(MinInt(TempActor."Destroyed At" + 1, MsgCount + 1));
                if K > 0 then begin
                    TempMsg.Get(K);
                    if (TempMsg."To Id" = TempActor.Id) or (TempMsg."From Id" = TempActor.Id) then
                        TempActor."Destroy Line" := K;
                end;
            end;
            TempActor.Modify();
        end;

        // Widths between lifelines: every message and note says how far apart the lifelines it touches must be.
        for I := 1 to MsgCount do begin
            TempMsg.Get(I);
            A := ColOf(TempMsg."From Id");
            B := ColOf(TempMsg."To Id");
            TempMsg."View Kind" := 0;
            if (A > 0) and (B > 0) then
                if TempMsg."Line Type" = 2 then begin
                    SeqLabel(Lbl, TempMsg.Message, Small, TempMsg.Wrap, WrapW, 0);
                    W := Lbl.GetWidth() + 2 * NotePad;
                    case true of
                        TempMsg.Placement = 0:
                            Need(Needs, A - 1, A, LastCol, W + 2 * 10 + ActW);
                        TempMsg.Placement = 1:
                            Need(Needs, A, A + 1, LastCol, W + 2 * 10 + ActW);
                        A = B:
                            begin
                                Need(Needs, A - 1, A, LastCol, W / 2 + 10);
                                Need(Needs, A, A + 1, LastCol, W / 2 + 10);
                            end;
                        else
                            Need(Needs, MinInt(A, B), MaxInt(A, B), LastCol, W - 2 * NoteOver);
                    end;
                    TempMsg."View Kind" := 3;
                    TempMsg."View W" := W;
                    TempMsg."Wrap Width" := WrapW;
                end else
                    if IsLineMessage(TempMsg."Line Type") then begin
                        SeqLabel(Lbl, TempMsg.Message, Small, TempMsg.Wrap, WrapW, 0);
                        Bw := BadgeWidth();
                        TempMsg."Wrap Width" := WrapW;
                        if A = B then begin
                            Need(Needs, A, A + 1, LastCol, 28 + 8 + Lbl.GetWidth() + 16 + ActW + Bw);
                            TempMsg."View Kind" := 2;
                        end else begin
                            TempActor.Get(B);
                            W := 0;
                            if TempActor."Create Line" = I then
                                W := TempActor.Width / 2;
                            Need(Needs, MinInt(A, B), MaxInt(A, B), LastCol, Lbl.GetWidth() + 2 * MsgPad + ActW + Bw + W);
                            TempMsg."View Kind" := 1;
                        end;
                    end;
            TempMsg."Col A" := A;
            TempMsg."Col B" := B;
            TempMsg.Modify();
        end;

        // Boxes: runs of neighbouring participants in the same box.
        for A := 1 to LastCol do begin
            TempActor.Get(A);
            if TempActor."Box No." <> 0 then
                if ContinuesRun(RunBox, RunLast, TempActor."Box No.", A) then
                    RunLast.Set(RunLast.Count(), A)
                else begin
                    RunBox.Add(TempActor."Box No.");
                    RunFirst.Add(A);
                    RunLast.Add(A);
                    RunGrow.Add(0);
                end;
        end;

        for I := 1 to LastCol - 1 do begin
            TempActor.Get(I);
            W := TempActor.Width / 2;
            K := TempActor."Box No.";
            TempActor.Get(I + 1);
            W += TempActor.Width / 2 + ActorMargin;
            if K <> TempActor."Box No." then begin
                if K <> 0 then
                    W += BoxPad;
                if TempActor."Box No." <> 0 then
                    W += BoxPad;
            end;
            if Needs.Get(NeedKey(I, I + 1), H) then
                W := MText.MaxDec(W, H);
            Gaps.Add(W);
        end;
        // A message across several lifelines widens each gap it crosses by an equal share of what is missing.
        foreach KeyText in Needs.Keys() do begin
            Parts := KeyText.Split(',');
            Evaluate(Lo, Parts.Get(1));
            Evaluate(Hi, Parts.Get(2));
            if Hi - Lo > 1 then begin
                K := SpanLo.Count() + 1;
                while SpanSortsAfter(SpanLo, SpanHi, K - 1, Lo, Hi) do
                    K -= 1;
                SpanLo.Insert(K, Lo);
                SpanHi.Insert(K, Hi);
                SpanW.Insert(K, Needs.Get(KeyText));
            end;
        end;
        for K := 1 to SpanLo.Count() do begin
            Total := 0;
            for I := SpanLo.Get(K) to SpanHi.Get(K) - 1 do
                Total += Gaps.Get(I);
            if Total < SpanW.Get(K) then begin
                Share := (SpanW.Get(K) - Total) / (SpanHi.Get(K) - SpanLo.Get(K));
                for I := SpanLo.Get(K) to SpanHi.Get(K) - 1 do
                    Gaps.Set(I, Gaps.Get(I) + Share);
            end;
        end;
        PlaceColumns(Gaps, LastCol);
        for K := 1 to RunBox.Count() do begin
            SeqLabel(Lbl, BoxNames.Get(RunBox.Get(K)), Small, BoxWraps.Get(RunBox.Get(K)), WrapW, 0);
            TempActor.Get(RunLast.Get(K));
            X1 := TempActor.X + TempActor.Width / 2;
            TempActor.Get(RunFirst.Get(K));
            X0 := TempActor.X - TempActor.Width / 2;
            RunGrow.Set(K, MText.MaxDec(0, (Lbl.GetWidth() - (X1 - X0)) / 2));
            if RunGrow.Get(K) > 0 then begin
                if RunFirst.Get(K) > 1 then
                    Gaps.Set(RunFirst.Get(K) - 1, Gaps.Get(RunFirst.Get(K) - 1) + RunGrow.Get(K));
                if RunLast.Get(K) < LastCol then
                    Gaps.Set(RunLast.Get(K), Gaps.Get(RunLast.Get(K)) + RunGrow.Get(K));
            end;
        end;
        PlaceColumns(Gaps, LastCol);

        for A := 1 to LastCol do begin
            TempActor.Get(A);
            Extend(TempActor.X - TempActor.Width / 2, TempActor.X + TempActor.Width / 2);
            ColXs.Add(TempActor.X);
        end;
        for K := 1 to RunBox.Count() do begin
            TempActor.Get(RunFirst.Get(K));
            X0 := TempActor.X - TempActor.Width / 2 - BoxPad - RunGrow.Get(K);
            TempActor.Get(RunLast.Get(K));
            X1 := TempActor.X + TempActor.Width / 2 + BoxPad + RunGrow.Get(K);
            Extend(X0, X1);
        end;

        // Horizontal extents of every block, from what it holds.
        for I := 1 to MsgCount do begin
            TempMsg.Get(I);
            M := TempMsg."Line Type";
            if FrameKindName(M) <> '' then begin
                FrKind.Add(FrameKindName(M));
                FrX0.Add(1000000000);
                FrX1.Add(-1000000000);
                FrTop.Add(0);
                FrTabW.Add(0);
                FrStartMsg.Add(I);
                if M = 22 then
                    FrFill.Add(TempMsg.Message)
                else
                    FrFill.Add('');
                FrTitle.Add('');
                FrTitleWrap.Add(0);
                Open.Add(FrKind.Count());
                TempMsg."Frame No." := FrKind.Count();
                TempMsg.Modify();
            end else
                if M in [13, 20, 28] then begin
                    if Open.Count() > 0 then begin
                        DivFrame.Add(Open.Get(Open.Count()));
                        DivMsg.Add(I);
                        DivText.Add('');
                        DivWrap.Add(0);
                        DivY.Add(0);
                    end;
                end else
                    if M in [11, 14, 16, 21, 29, 31, 23] then begin
                        if Open.Count() > 0 then begin
                            F := Open.Get(Open.Count());
                            Open.RemoveAt(Open.Count());
                            TempMsg."Frame No." := F;
                            TempMsg.Modify();
                            if FrX0.Get(F) > FrX1.Get(F) then
                                if LastCol < 1 then begin
                                    FrX0.Set(F, 0);
                                    FrX1.Set(F, 120);
                                end else begin
                                    TempActor.Get(1);
                                    FrX0.Set(F, TempActor.X - FramePad);
                                    TempActor.Get(LastCol);
                                    FrX1.Set(F, TempActor.X + FramePad);
                                end;
                            if FrKind.Get(F) <> 'rect' then begin
                                FrTabW.Set(F, MText.Width(FrKind.Get(F), Tiny, MText.StyleBold()) + 14);
                                // A block grows to the right to give its texts up to 240 of width before they wrap.
                                TempMsg.Get(FrStartMsg.Get(F));
                                Room := FrX1.Get(F) - FrX0.Get(F) - 16 - (FrTabW.Get(F) + 8);
                                if TempMsg.Message <> '' then begin
                                    FrTitle.Set(F, '[' + TempMsg.Message + ']');
                                    FrTitleWrap.Set(F, MText.MaxDec(Room, 240));
                                    SeqLabel(Lbl, FrTitle.Get(F), Small, true, FrTitleWrap.Get(F), 0);
                                    if Lbl.GetWidth() > Room then
                                        FrX1.Set(F, FrX1.Get(F) + Lbl.GetWidth() - Room);
                                end;
                                for K := 1 to DivFrame.Count() do
                                    if DivFrame.Get(K) = F then begin
                                        TempMsg.Get(DivMsg.Get(K));
                                        Room := FrX1.Get(F) - FrX0.Get(F) - 16;
                                        if TempMsg.Message <> '' then begin
                                            DivText.Set(K, '[' + TempMsg.Message + ']');
                                            DivWrap.Set(K, MText.MaxDec(Room, 240));
                                            SeqLabel(Lbl, DivText.Get(K), Small, true, DivWrap.Get(K), 0);
                                            if Lbl.GetWidth() > Room then
                                                FrX1.Set(F, FrX1.Get(F) + Lbl.GetWidth() - Room);
                                        end;
                                    end;
                            end;
                            Extend(FrX0.Get(F), FrX1.Get(F));
                            if Open.Count() > 0 then begin
                                K := Open.Get(Open.Count());
                                FrX0.Set(K, MText.MinDec(FrX0.Get(K), FrX0.Get(F) - FrameNest));
                                FrX1.Set(K, MText.MaxDec(FrX1.Get(K), FrX1.Get(F) + FrameNest));
                            end;
                        end;
                    end else
                        if TempMsg."View Kind" > 0 then begin
                            TempActor.Get(TempMsg."Col A");
                            Lx := TempActor.X;
                            TempActor.Get(TempMsg."Col B");
                            Rx := TempActor.X;
                            SeqLabel(Lbl, TempMsg.Message, Small, TempMsg.Wrap, TempMsg."Wrap Width", 0);
                            case TempMsg."View Kind" of
                                3:
                                    begin
                                        case true of
                                            TempMsg.Placement = 0:
                                                TempMsg."View X" := Lx - 10 - TempMsg."View W";
                                            TempMsg.Placement = 1:
                                                TempMsg."View X" := Lx + 10;
                                            TempMsg."Col A" = TempMsg."Col B":
                                                TempMsg."View X" := Lx - TempMsg."View W" / 2;
                                            else begin
                                                X0 := MText.MinDec(Lx, Rx) - NoteOver;
                                                X1 := MText.MaxDec(Lx, Rx) + NoteOver;
                                                if TempMsg.Wrap then begin
                                                    TempMsg."Wrap Width" := MText.MaxDec(WrapW, X1 - X0 - 2 * NotePad);
                                                    SeqLabel(Lbl, TempMsg.Message, Small, true, TempMsg."Wrap Width", 0);
                                                end;
                                                TempMsg."View W" := MText.MaxDec(X1 - X0, Lbl.GetWidth() + 2 * NotePad);
                                                TempMsg."View X" := (X0 + X1 - TempMsg."View W") / 2;
                                            end;
                                        end;
                                        X0 := TempMsg."View X";
                                        X1 := TempMsg."View X" + TempMsg."View W";
                                    end;
                                2:
                                    begin
                                        X0 := Lx;
                                        X1 := Lx + ActW + 28 + 8 + Lbl.GetWidth() + BadgeWidth();
                                    end;
                                else begin
                                    X0 := MText.MinDec(Lx, Rx);
                                    X1 := MText.MaxDec(Lx, Rx);
                                    if TempMsg.Wrap then
                                        TempMsg."Wrap Width" := MText.MaxDec(WrapW, X1 - X0 - 2 * MsgPad - ActW);
                                    TempActor.Get(TempMsg."Col B");
                                    if TempActor."Create Line" = I then
                                        if Rx > Lx then
                                            X1 += TempActor.Width / 2
                                        else
                                            X0 -= TempActor.Width / 2;
                                end;
                            end;
                            TempMsg.Modify();
                            Extend(X0, X1);
                            if Open.Count() > 0 then begin
                                K := Open.Get(Open.Count());
                                FrX0.Set(K, MText.MinDec(FrX0.Get(K), X0 - FramePad));
                                FrX1.Set(K, MText.MaxDec(FrX1.Get(K), X1 + FramePad));
                            end;
                        end;
        end;

        // Vertical placement, top to bottom, drawing as it goes.
        for K := 1 to RunBox.Count() do begin
            SeqLabel(Lbl, BoxNames.Get(RunBox.Get(K)), Small, BoxWraps.Get(RunBox.Get(K)), WrapW, 0);
            BoxTitleH := MText.MaxDec(BoxTitleH, Lbl.GetHeight());
        end;
        if RunBox.Count() > 0 then begin
            BoxTop := BoxPad;
            if BoxTitleH > 0 then
                BoxTop += BoxTitleH + 4;
        end;
        for A := 1 to LastCol do begin
            TempActor.Get(A);
            if TempActor."Create Line" = 0 then
                RowH := MText.MaxDec(RowH, TempActor.Height);
        end;
        HeadBottom := BoxTop + RowH;
        for A := 1 to LastCol do begin
            TempActor.Get(A);
            TempActor.Top := HeadBottom - TempActor.Height;
            TempActor."Life Start" := HeadBottom;
            TempActor.Modify();
        end;

        Y := HeadBottom + 6;
        for I := 1 to MsgCount do begin
            TempMsg.Get(I);
            M := TempMsg."Line Type";
            F := TempMsg."Frame No.";
            HasFrame := F > 0;
            IsFrameStart := false;
            if HasFrame then
                IsFrameStart := FrStartMsg.Get(F) = I;
            case true of
                M = 17:
                    begin
                        A := ColOf(TempMsg."From Id");
                        if A > 0 then begin
                            ActCol.Add(A);
                            ActY.Add(Y);
                        end;
                    end;
                M = 18:
                    begin
                        A := ColOf(TempMsg."From Id");
                        if A > 0 then
                            if ActCount(A) > 0 then
                                Y := MText.MaxDec(Y, EndActivation(A, Y));
                    end;
                IsFrameStart:
                    begin
                        Stack.Add(F);
                        if FrKind.Get(F) = 'rect' then begin
                            FrTop.Set(F, Y + 8);
                            Y := FrTop.Get(F);
                        end else begin
                            FrTop.Set(F, Y + 12);
                            SeqLabel(Lbl, FrTitle.Get(F), Small, true, FrTitleWrap.Get(F), 0);
                            Y := FrTop.Get(F) + MText.MaxDec(20, Lbl.GetHeight() + 2);
                        end;
                    end;
                HasFrame:
                    begin
                        if Stack.Count() > 0 then
                            Stack.RemoveAt(Stack.Count());
                        BottomY := Y + 12;
                        if FrKind.Get(F) = 'rect' then begin
                            Fill := '';
                            if FrFill.Get(F) <> '' then begin
                                Clear(FillDecl);
                                FillDecl.Add('fill:' + FrFill.Get(F));
                                Builder.ResolveStyle(FillDecl, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
                                Fill := ShapeAttr;
                            end;
                            if Fill = '' then
                                Fill := ' fill-opacity="0.5"';
                            RectsOut.Add('<rect class="pele-rect" x="' + N(FrX0.Get(F)) + '" y="' + N(FrTop.Get(F)) + '" width="' + N(FrX1.Get(F) - FrX0.Get(F)) + '" height="' + N(BottomY - FrTop.Get(F)) +
                                         '" rx="' + Builder.Radius() + '"' + Fill + '/>');
                        end else begin
                            Inner.Clear();
                            Inner.Append('<rect x="' + N(FrX0.Get(F)) + '" y="' + N(FrTop.Get(F)) + '" width="' + N(FrX1.Get(F) - FrX0.Get(F)) + '" height="' + N(BottomY - FrTop.Get(F)) +
                                         '" rx="' + Builder.Radius() + '" fill="none"/>');
                            for K := 1 to DivFrame.Count() do
                                if DivFrame.Get(K) = F then begin
                                    SeqLabel(Lbl, DivText.Get(K), Small, true, DivWrap.Get(K), 0);
                                    Inner.Append('<path d="M' + N(FrX0.Get(F)) + ',' + N(DivY.Get(K)) + 'H' + N(FrX1.Get(F)) + '" stroke-dasharray="4 4"/>' +
                                                 Backed(Lbl, FrX0.Get(F) + 8 + Lbl.GetWidth() / 2, DivY.Get(K) + 2 + Lbl.GetHeight() / 2, ' class="pele-frame-label" fill="var(--_m)" stroke="none"'));
                                end;
                            SeqLabel(Lbl, FrTitle.Get(F), Small, true, FrTitleWrap.Get(F), 0);
                            Inner.Append('<rect x="' + N(FrX0.Get(F)) + '" y="' + N(FrTop.Get(F)) + '" width="' + N(FrTabW.Get(F)) + '" height="20" rx="' + Builder.Radius() + '" fill="var(--_s)"/>' +
                                         '<text class="pele-frame-kind" x="' + N(FrX0.Get(F) + FrTabW.Get(F) / 2) + '" y="' + N(FrTop.Get(F) + 10 + Tiny * 0.35) + '" text-anchor="middle" font-size="' + N(Tiny) +
                                         '" font-weight="var(--_hw)" fill="var(--_m)" stroke="none">' + FrKind.Get(F) + '</text>' +
                                         Backed(Lbl, FrX0.Get(F) + FrTabW.Get(F) + 8 + Lbl.GetWidth() / 2, FrTop.Get(F) + MText.MaxDec(20, Lbl.GetHeight()) / 2, ' class="pele-frame-label" fill="var(--_m)" stroke="none"'));
                            FramesOut.Append('<g class="pele-frame pele-frame-' + FrKind.Get(F) + '">' + Inner.ToText() + '</g>');
                        end;
                        Y := BottomY;
                    end;
                M in [13, 20, 28]:
                    if Stack.Count() > 0 then begin
                        Done := false;
                        for K := 1 to DivMsg.Count() do
                            if not Done and (DivMsg.Get(K) = I) then begin
                                DivY.Set(K, Y + 12);
                                SeqLabel(Lbl, DivText.Get(K), Small, true, DivWrap.Get(K), 0);
                                Y += 12 + Lbl.GetHeight();
                                Done := true;
                            end;
                    end;
                TempMsg."View Kind" = 3:
                    begin
                        SeqLabel(Lbl, TempMsg.Message, Small, TempMsg.Wrap, TempMsg."Wrap Width", 0);
                        H := Lbl.GetHeight() + 2 * MText.MaxDec(4, NotePad - 4);
                        Top := Y + 10;
                        X0 := TempMsg."View X";
                        A := TempMsg."Col A";
                        TempActor.Get(A);
                        if TempMsg.Placement = 1 then
                            X0 += RightEdge(A, 0) - TempActor.X
                        else
                            if TempMsg.Placement = 0 then
                                X0 += LeftEdge(A, 0) - TempActor.X;
                        Extend(X0, X0 + TempMsg."View W");
                        NotesOut.Append('<g class="pele-note" data-id="i' + MText.IntText(I - 1) + '">' +
                                        '<rect x="' + N(X0) + '" y="' + N(Top) + '" width="' + N(TempMsg."View W") + '" height="' + N(H) + '" rx="' + Builder.Radius() + '"/>' +
                                        Lbl.ToSvg(X0 + TempMsg."View W" / 2, Top + H / 2, ' class="pele-label" stroke="none" fill="var(--_fg)"') + '</g>');
                        Y := Top + H;
                    end;
                TempMsg."View Kind" in [1, 2]:
                    begin
                        LineStyle(M, Dotted, Head, AtStart, AtEnd, Bottom);
                        A := TempMsg."Col A";
                        B := TempMsg."Col B";
                        SeqLabel(Lbl, TempMsg.Message, Small, TempMsg.Wrap, TempMsg."Wrap Width", 0);
                        Bw := BadgeWidth();
                        // The activation a + starts belongs to this message, so the arrow stops at its edge.
                        Starting := 0;
                        Done := false;
                        K := I + 1;
                        while not Done and (K <= MsgCount) do begin
                            TempMsg.Get(K);
                            if TempMsg."Line Type" = 17 then begin
                                if ColOf(TempMsg."From Id") = B then
                                    Starting += 1;
                            end else
                                if TempMsg."Line Type" <> 18 then
                                    Done := true;
                            K += 1;
                        end;
                        TempMsg.Get(I);
                        Up := -1;
                        if Bottom then
                            Up := 1;
                        Attrs := '';
                        if Dotted then
                            Attrs := ' stroke-dasharray="4 4"';
                        TailAtEnd := AtStart and not AtEnd;
                        Heads := '';
                        TempActor.Get(A);
                        if TempMsg."View Kind" = 2 then begin
                            Top := Y + MsgGap + MText.MaxDec(0, (Lbl.GetHeight() - 22) / 2);
                            BottomY := Top + 22;
                            X0 := RightEdge(A, 0);
                            X1 := RightEdge(A, Starting);
                            Outer := MText.MaxDec(X0, X1) + 28 + Bw / 2;
                            Inner.Clear();
                            if Bw > 0 then begin
                                if TailAtEnd then begin
                                    Inner.Append(Badge(TempMsg.Number, X1, BottomY, Bw));
                                    X1 += Bw / 2;
                                end else begin
                                    Inner.Append(Badge(TempMsg.Number, X0, Top, Bw));
                                    X0 += Bw / 2;
                                end;
                            end;
                            // The loop leaves to the right and comes back heading left, which turns a half head over.
                            if AtStart then
                                Heads += HeadSvg(Head, X0, Top, -1, Up);
                            if AtEnd then
                                Heads += HeadSvg(Head, X1, BottomY, -1, -Up);
                            FromX := X0;
                            if AtStart then
                                FromX += HeadTrim(Head);
                            ToX := X1;
                            if AtEnd then
                                ToX += HeadTrim(Head);
                            if RightAngles then
                                PathD := 'M' + N(FromX) + ',' + N(Top) + 'H' + N(Outer) + 'V' + N(BottomY) + 'H' + N(ToX)
                            else
                                PathD := 'M' + N(FromX) + ',' + N(Top) + 'H' + N(Outer - 6) + 'A6,6 0 0 1 ' + N(Outer) + ',' + N(Top + 6) + 'V' + N(BottomY - 6) +
                                         'A6,6 0 0 1 ' + N(Outer - 6) + ',' + N(BottomY) + 'H' + N(ToX);
                            TempActor.Get(A);
                            Extend(TempActor.X, Outer + 8 + Lbl.GetWidth());
                            if Lbl.GetWidth() > 0 then
                                LabelsOut.Append('<g class="pele-edge-label" data-id="i' + MText.IntText(I - 1) + '">' + Lbl.ToSvg(Outer + 8 + Lbl.GetWidth() / 2, (Top + BottomY) / 2, '') + '</g>');
                            EdgesOut.Append('<g class="pele-edge pele-message" data-id="i' + MText.IntText(I - 1) + '"><path d="' + PathD + '"' + Attrs + '/>' + Heads + Inner.ToText() + '</g>');
                            LineY := BottomY;
                        end else begin
                            TempActor.Get(B);
                            Rx := TempActor.X;
                            TempActor.Get(A);
                            Lx := TempActor.X;
                            Dir := 1;
                            if Rx <= Lx then
                                Dir := -1;
                            TempActor.Get(B);
                            Creating := TempActor."Create Line" = I;
                            if Lbl.GetHeight() > 0 then
                                LineY := Lbl.GetHeight() + 2
                            else
                                LineY := 6;
                            if Creating then
                                LineY := MText.MaxDec(LineY, TempActor.Height / 2 - MsgGap + 6);
                            LineY := Y + MsgGap + LineY;
                            if Dir > 0 then begin
                                X0 := RightEdge(A, 0);
                                X1 := LeftEdge(B, Starting);
                            end else begin
                                X0 := LeftEdge(A, 0);
                                X1 := RightEdge(B, Starting);
                            end;
                            if Creating then begin
                                TempActor.Get(B);
                                TempActor.Top := LineY - TempActor.Height / 2;
                                TempActor."Life Start" := TempActor.Top + TempActor.Height;
                                TempActor.Modify();
                                if IsFigure(ActorKind(TempActor.Kind)) then
                                    X1 := TempActor.X - Dir * 18
                                else
                                    X1 := TempActor.X - Dir * (TempActor.Width / 2 + 1);
                            end;
                            Inner.Clear();
                            if Bw > 0 then
                                if TailAtEnd then begin
                                    Inner.Append(Badge(TempMsg.Number, X1, LineY, Bw));
                                    X1 := X1 - Dir * Bw / 2;
                                end else begin
                                    Inner.Append(Badge(TempMsg.Number, X0, LineY, Bw));
                                    X0 := X0 + Dir * Bw / 2;
                                end;
                            if AtStart then
                                Heads += HeadSvg(Head, X0, LineY, -Dir, Up * Dir);
                            if AtEnd then
                                Heads += HeadSvg(Head, X1, LineY, Dir, Up * Dir);
                            FromX := X0;
                            if AtStart then
                                FromX += Dir * HeadTrim(Head);
                            ToX := X1;
                            if AtEnd then
                                ToX -= Dir * HeadTrim(Head);
                            EdgesOut.Append('<g class="pele-edge pele-message" data-id="i' + MText.IntText(I - 1) + '"><path d="M' + N(FromX) + ',' + N(LineY) + 'H' + N(ToX) + '"' + Attrs + '/>' + Heads + Inner.ToText() + '</g>');
                            if Lbl.GetWidth() > 0 then begin
                                X0 := MText.MinDec(FromX, ToX);
                                X1 := MText.MaxDec(FromX, ToX);
                                case Align of
                                    -1:
                                        Cx := X0 + MsgPad + Lbl.GetWidth() / 2;
                                    1:
                                        Cx := X1 - MsgPad - Lbl.GetWidth() / 2;
                                    else
                                        Cx := (X0 + X1) / 2;
                                end;
                                Extend(Cx - Lbl.GetWidth() / 2, Cx + Lbl.GetWidth() / 2);
                                LabelsOut.Append('<g class="pele-edge-label" data-id="i' + MText.IntText(I - 1) + '">' + Backed(Lbl, Cx, LineY - 4 - Lbl.GetHeight() / 2, '') + '</g>');
                            end;
                            if Creating then begin
                                TempActor.Get(B);
                                Y := LineY + TempActor.Height / 2 - 6;
                            end;
                        end;
                        Y := MText.MaxDec(Y, LineY);
                        TempActor.Get(A);
                        if TempActor."Destroy Line" = I then
                            Y := MText.MaxDec(Y, DestroyCol(A, LineY));
                        if B <> A then begin
                            TempActor.Get(B);
                            if TempActor."Destroy Line" = I then
                                Y := MText.MaxDec(Y, DestroyCol(B, LineY));
                        end;
                    end;
            end;
        end;

        Y += 20;
        for A := 1 to LastCol do
            while ActCount(A) > 0 do
                EndActivation(A, Y);
        BottomY := Y;
        if Mirror then begin
            for A := 1 to LastCol do begin
                TempActor.Get(A);
                if TempActor."Life End" < 0 then begin
                    FootH := MText.MaxDec(FootH, TempActor.Height);
                    ActorsOut.Append(ActorSvg(A, Y, true));
                end;
            end;
            BottomY := Y + FootH;
        end;
        for A := 1 to LastCol do begin
            TempActor.Get(A);
            ActorsOut.Append(ActorSvg(A, TempActor.Top, false));
            TempActor.Get(A);
            H := Y;
            if TempActor."Life End" >= 0 then
                H := TempActor."Life End";
            if H > TempActor."Life Start" then
                Lifelines.Append('<path class="pele-lifeline" data-id="' + MText.EscText(TempActor.Id) + '" d="M' + N(TempActor.X) + ',' + N(TempActor."Life Start") + 'V' + N(H) + '"/>');
        end;

        for K := 1 to RunBox.Count() do begin
            TempActor.Get(RunFirst.Get(K));
            X0 := TempActor.X - TempActor.Width / 2 - BoxPad - RunGrow.Get(K);
            TempActor.Get(RunLast.Get(K));
            X1 := TempActor.X + TempActor.Width / 2 + BoxPad + RunGrow.Get(K);
            Fill := '';
            if BoxFills.Get(RunBox.Get(K)) <> 'transparent' then begin
                Clear(FillDecl);
                FillDecl.Add('fill:' + BoxFills.Get(RunBox.Get(K)));
                Builder.ResolveStyle(FillDecl, ShapeAttr, LineAttr, TextAttr, Stroke, IsBold, IsItalic, StyleSize);
                Fill := ShapeAttr;
            end;
            if Fill = '' then
                Fill := ' fill-opacity="0.5"';
            SeqLabel(Lbl, BoxNames.Get(RunBox.Get(K)), Small, BoxWraps.Get(RunBox.Get(K)), WrapW, 0);
            KeyText := '';
            if BoxNames.Get(RunBox.Get(K)) <> '' then
                KeyText := ' data-id="' + MText.EscText(BoxNames.Get(RunBox.Get(K))) + '"';
            BoxesOut.Append('<g class="pele-cluster pele-box"' + KeyText + '>' +
                            '<rect x="' + N(X0) + '" y="0" width="' + N(X1 - X0) + '" height="' + N(BottomY + BoxPad) + '" rx="' + Builder.Radius() + '" fill="var(--_a)" stroke="var(--_b)"' + Fill + '/>' +
                            Lbl.ToSvg((X0 + X1) / 2, BoxPad / 2 + 2 + Lbl.GetHeight() / 2, ' class="pele-cluster-label" fill="var(--_m)"') + '</g>');
        end;
        if RunBox.Count() > 0 then
            BottomY += BoxPad;

        MinY := 0;
        TitleLbl.Layout(SeqTitle, false, Size, WrapW, MText.StyleBold());
        if MinX > MaxX then
            Extend(0, MText.MaxDec(TitleLbl.GetWidth(), 40));
        Content := '';
        if TitleLbl.GetWidth() > 0 then begin
            Cx := (MinX + MaxX) / 2;
            Extend(Cx - TitleLbl.GetWidth() / 2, Cx + TitleLbl.GetWidth() / 2);
            MinY := -TitleLbl.GetHeight() - 12;
            Content := Builder.TitleSvg(TitleLbl, Cx, MinY + TitleLbl.GetHeight() / 2);
        end;

        Width := MText.Ceil(MaxX - MinX + 2 * Pad);
        Height := MText.Ceil(BottomY - MinY + 2 * Pad);
        if BoxesOut.Length() > 0 then
            Content += '<g class="pele-boxes" font-size="' + N(Small) + '">' + BoxesOut.ToText() + '</g>';
        if RectsOut.Count() > 0 then
            Content += '<g class="pele-rects" fill="var(--_a)">' + JoinReversed(RectsOut) + '</g>';
        if Lifelines.Length() > 0 then
            Content += '<g class="pele-lifelines" fill="none" stroke="var(--_b)">' + Lifelines.ToText() + '</g>';
        if ActivationsOut.Count() > 0 then
            Content += '<g class="pele-activations" fill="var(--_s)" stroke="var(--_b)">' + JoinReversed(ActivationsOut) + '</g>';
        if FramesOut.Length() > 0 then
            Content += '<g class="pele-frames" font-size="' + N(Small) + '" stroke="var(--_b)">' + FramesOut.ToText() + '</g>';
        if EdgesOut.Length() > 0 then
            Content += '<g class="pele-edges" fill="none" stroke="var(--_l)" stroke-linecap="round">' + EdgesOut.ToText() + '</g>';
        if CrossesOut.Length() > 0 then
            Content += '<g class="pele-destroys" fill="none" stroke="var(--_l)" stroke-width="1.5" stroke-linecap="round">' + CrossesOut.ToText() + '</g>';
        if LabelsOut.Length() > 0 then
            Content += '<g class="pele-edge-labels" font-size="' + N(Small) + '">' + LabelsOut.ToText() + '</g>';
        if NotesOut.Length() > 0 then
            Content += '<g class="pele-notes" font-size="' + N(Small) + '" fill="var(--_a)" stroke="var(--_b)">' + NotesOut.ToText() + '</g>';
        if ActorsOut.Length() > 0 then
            Content += '<g class="pele-nodes">' + ActorsOut.ToText() + '</g>';
        Content := '<g transform="translate(' + Builder.P(Pad - MinX, Pad - MinY) + ')">' + Content + '</g>';
        exit(Builder.Document('sequence', Width, Height, Size, AccTitle, AccDescr, Content));
    end;

    /// <summary>Whether the span at index At sorts after one from Lo to Hi: shorter spans first, then by their start.</summary>
    local procedure SpanSortsAfter(var SpanLo: List of [Integer]; var SpanHi: List of [Integer]; At: Integer; Lo: Integer; Hi: Integer): Boolean
    var
        Len: Integer;
    begin
        if At < 1 then
            exit(false);
        Len := SpanHi.Get(At) - SpanLo.Get(At);
        if Len <> Hi - Lo then
            exit(Len > Hi - Lo);
        exit(SpanLo.Get(At) > Lo);
    end;

    local procedure ContinuesRun(var RunBox: List of [Integer]; var RunLast: List of [Integer]; BoxNo: Integer; Col: Integer): Boolean
    begin
        if RunBox.Count() = 0 then
            exit(false);
        exit((RunBox.Get(RunBox.Count()) = BoxNo) and (RunLast.Get(RunLast.Count()) = Col - 1));
    end;

    local procedure PlaceColumns(var Gaps: List of [Decimal]; LastCol: Integer)
    var
        I: Integer;
        X: Decimal;
    begin
        X := 0;
        for I := 1 to LastCol do begin
            TempActor.Get(I);
            if I > 1 then
                X += Gaps.Get(I - 1);
            TempActor.X := X;
            TempActor.Modify();
        end;
    end;

    local procedure JoinReversed(var Items: List of [Text]): Text
    var
        Result: TextBuilder;
        I: Integer;
    begin
        for I := Items.Count() downto 1 do
            Result.Append(Items.Get(I));
        exit(Result.ToText());
    end;

    local procedure MinInt(A: Integer; B: Integer): Integer
    begin
        if A < B then
            exit(A);
        exit(B);
    end;

    local procedure MaxInt(A: Integer; B: Integer): Integer
    begin
        if A > B then
            exit(A);
        exit(B);
    end;
}
