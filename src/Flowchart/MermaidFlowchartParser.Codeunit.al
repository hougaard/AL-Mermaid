/// <summary>
/// Port of pele's diagrams/flowchart lexer.ts, parser.ts and db.ts as one hand-written scanner and
/// recursive-descent parser. It reads Mermaid's flowchart syntax: graph/flowchart headers with a
/// direction, vertices with every bracket shape, @{ shape data }, chains of links of every kind with
/// |pipe| or inline labels, &amp; groups, link ids, subgraphs with their own direction, classDef, class,
/// :::class, style, linkStyle (with interpolate), click, accTitle and accDescr.
/// The result is kept in two temporary tables and read back by the renderer.
/// </summary>
codeunit 68905 "Mermaid Flowchart Parser"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Shapes: Codeunit "Mermaid Shapes";
        TempNode: Record "Mermaid Flow Node" temporary;
        TempEdge: Record "Mermaid Flow Edge" temporary;
        ClassStyles: Dictionary of [Text, Text];
        ClassTextStyles: Dictionary of [Text, Text];
        PairCount: Dictionary of [Text, Integer];
        Members: Dictionary of [Text, Boolean];
        SubgraphIds: Dictionary of [Text, Boolean];
        EdgeIds: Dictionary of [Text, Integer];
        FrameHasId: List of [Boolean];
        FrameIds: List of [Text];
        FrameTitleGiven: List of [Boolean];
        FrameTitles: List of [Text];
        FrameTitleTypes: List of [Text];
        FrameMembers: List of [Text];
        FrameDirs: List of [Text];
        Src: Text;
        Pos: Integer;
        SrcLen: Integer;
        FlowDirection: Text;
        FlowTitle: Text;
        AccTitleValue: Text;
        AccDescrValue: Text;
        DefaultEdgeStyle: Text;
        DefaultInterpolate: Text;
        SubCount: Integer;
        NextNodeNo: Integer;
        NextEdgeNo: Integer;
        MaxEdges: Integer;
        InheritDir: Boolean;
        StatementStartTok: Label '''SEMI'', ''NEWLINE'', ''SPACE'', ''EOF'', ''subgraph'', ''acc_title'', ''acc_descr'', ''acc_descr_multiline_value'', ''STYLE'', ''LINKSTYLE'', ''CLASSDEF'', ''CLASS'', ''CLICK'', ''NODE_STRING''', Locked = true;
        TextTokensTok: Label '''UNICODE_TEXT'', ''TEXT'', ''TAGSTART'', ''TAGEND'', ''STR'', ''MD_STR''', Locked = true;

    // ---------------------------------------------------------------- results

    procedure GetNodes(var Node: Record "Mermaid Flow Node" temporary)
    begin
        Node.Copy(TempNode, true);
    end;

    procedure GetEdges(var Edge: Record "Mermaid Flow Edge" temporary)
    begin
        Edge.Copy(TempEdge, true);
    end;

    procedure GetDirection(): Text
    begin
        exit(FlowDirection);
    end;

    procedure GetTitle(): Text
    begin
        exit(FlowTitle);
    end;

    procedure GetAccTitle(): Text
    begin
        exit(AccTitleValue);
    end;

    procedure GetAccDescr(): Text
    begin
        exit(AccDescrValue);
    end;

    procedure GetDefaultEdgeStyle(): Text
    begin
        exit(DefaultEdgeStyle);
    end;

    procedure GetDefaultInterpolate(): Text
    begin
        exit(DefaultInterpolate);
    end;

    /// <summary>The styles of each class named, then their text styles, joined by semicolons (pele's compiled()).</summary>
    procedure CompiledStyles(ClassList: Text): Text
    var
        Name: Text;
        Value: Text;
        Result: Text;
    begin
        foreach Name in ClassList.Split(' ') do
            if Name <> '' then begin
                if ClassStyles.Get(Name, Value) then
                    Result := JoinStyle(Result, Value);
                if ClassTextStyles.Get(Name, Value) then
                    Result := JoinStyle(Result, Value);
            end;
        exit(Result);
    end;

    local procedure JoinStyle(Existing: Text; Extra: Text): Text
    begin
        if Extra = '' then
            exit(Existing);
        if Existing = '' then
            exit(Extra);
        exit(Existing + ';' + Extra);
    end;

    // ---------------------------------------------------------------- scanning helpers

    local procedure Cur(): Integer
    begin
        exit(MText.CharAt(Src, Pos));
    end;

    local procedure Ahead(K: Integer): Integer
    begin
        exit(MText.CharAt(Src, Pos + K));
    end;

    local procedure IsBlankChar(C: Integer): Boolean
    begin
        exit(MText.IsSpace(C) and (C <> 10) and (C <> 13));
    end;

    local procedure SkipBlanks()
    begin
        while IsBlankChar(Cur()) do
            Pos += 1;
    end;

    local procedure SkipBlanksFrom(P: Integer): Integer
    begin
        while IsBlankChar(MText.CharAt(Src, P)) do
            P += 1;
        exit(P);
    end;

    local procedure IsKw(Word: Text): Boolean
    begin
        exit(MText.StartsWithAt(Src, Word, Pos) and not MText.IsWord(MText.CharAt(Src, Pos + StrLen(Word))));
    end;

    local procedure TokenName(): Text
    var
        C: Integer;
    begin
        C := Cur();
        case C of
            -1:
                exit('EOF');
            10:
                exit('NEWLINE');
            59:
                exit('SEMI');
            93:
                exit('SQE');
            91:
                exit('SQS');
            41:
                exit('PE');
            40:
                exit('PS');
            125:
                exit('DIAMOND_STOP');
            123:
                exit('DIAMOND_START');
            124:
                exit('PIPE');
            34:
                exit('STR');
            38:
                exit('AMP');
            58:
                exit('COLON');
            44:
                exit('COMMA');
        end;
        if IsBlankChar(C) then
            exit('SPACE');
        if MText.IsDigit(C) then
            exit('NUM');
        exit('NODE_STRING');
    end;

    local procedure Fail(Expected: Text)
    begin
        MText.SyntaxError('flowchart', Src, Pos, 'Expecting ' + Expected + ', got ''' + TokenName() + '''', false);
    end;

    local procedure FailLexical()
    begin
        MText.SyntaxError('flowchart', Src, Pos, '', true);
    end;

    local procedure ExpectBlank()
    begin
        if not IsBlankChar(Cur()) then
            Fail('''SPACE''');
        SkipBlanks();
    end;

    local procedure Separator()
    var
        C: Integer;
    begin
        SkipBlanks();
        C := Cur();
        if C = -1 then
            exit;
        if (C <> 10) and (C <> 59) then
            Fail('''SEMI'', ''NEWLINE'', ''EOF''');
        Pos += 1;
    end;

    // ---------------------------------------------------------------- entry

    procedure Parse(Source: Text; FrontTitle: Text; NewMaxEdges: Integer; NewInheritDir: Boolean)
    var
        C: Integer;
        Dir: Text;
        J: Integer;
        LastNewline: Integer;
    begin
        TempNode.Reset();
        TempNode.DeleteAll();
        TempEdge.Reset();
        TempEdge.DeleteAll();
        Clear(ClassStyles);
        Clear(ClassTextStyles);
        Clear(PairCount);
        Clear(Members);
        Clear(SubgraphIds);
        Clear(EdgeIds);
        Clear(FrameHasId);
        Clear(FrameIds);
        Clear(FrameTitleGiven);
        Clear(FrameTitles);
        Clear(FrameTitleTypes);
        Clear(FrameMembers);
        Clear(FrameDirs);
        FlowDirection := '';
        FlowTitle := FrontTitle;
        AccTitleValue := '';
        AccDescrValue := '';
        DefaultEdgeStyle := '';
        DefaultInterpolate := '';
        SubCount := 0;
        NextNodeNo := 0;
        NextEdgeNo := 0;
        MaxEdges := NewMaxEdges;
        InheritDir := NewInheritDir;
        Src := TrimAfterBraces(Source);
        SrcLen := StrLen(Src);
        Pos := 1;

        while MText.IsSpace(Cur()) do
            Pos += 1;
        if IsKw('flowchart-elk') then
            Pos += 13
        else
            if IsKw('flowchart') then
                Pos += 9
            else
                if IsKw('graph') then
                    Pos += 5
                else
                    Fail('''GRAPH''');

        // NODIR: nothing but whitespace up to the end of the line.
        J := Pos;
        LastNewline := 0;
        while MText.IsSpace(MText.CharAt(Src, J)) do begin
            if MText.CharAt(Src, J) = 10 then
                LastNewline := J;
            J += 1;
        end;
        if LastNewline > 0 then begin
            Pos := LastNewline + 1;
            SetDirection('TB');
        end else begin
            SkipBlanks();
            Dir := ReadDirection();
            if Dir = '' then
                Fail('''DIR'', ''NODIR''');
            SetDirection(Dir);
            SkipBlanks();
            C := Cur();
            if (C <> 10) and (C <> 59) and (C <> -1) then
                Fail('''SEMI'', ''NEWLINE'', ''SPACE''');
            Pos += 1;
        end;
        Document();
    end;

    /// <summary>Mermaid trims whitespace between a closing brace and the end of its line before parsing.</summary>
    local procedure TrimAfterBraces(Value: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        J: Integer;
    begin
        if StrPos(Value, '}') = 0 then
            exit(Value);
        I := 1;
        while I <= StrLen(Value) do begin
            Builder.Append(CopyStr(Value, I, 1));
            if Value[I] = '}' then begin
                J := I + 1;
                while MText.IsSpace(MText.CharAt(Value, J)) and (MText.CharAt(Value, J) <> 10) do
                    J += 1;
                if (J > I + 1) and (MText.CharAt(Value, J) = 10) then
                    I := J - 1;
            end;
            I += 1;
        end;
        exit(Builder.ToText());
    end;

    local procedure ReadDirection(): Text
    var
        Two: Text;
        C: Integer;
    begin
        Two := CopyStr(Src, Pos, 2);
        if (Two in ['LR', 'RL', 'TB', 'BT', 'TD', 'BR']) and not MText.IsWord(MText.CharAt(Src, Pos + 2)) then begin
            Pos += 2;
            exit(Two);
        end;
        C := Cur();
        if (C = 60) or (C = 62) or (C = 94) then begin
            Pos += 1;
            exit(MText.FromCode(C));
        end;
        if (C = 118) and not MText.IsWord(Ahead(1)) then begin
            Pos += 1;
            exit('v');
        end;
        exit('');
    end;

    local procedure SetDirection(Dir: Text)
    begin
        Dir := MText.TrimWs(Dir);
        if Dir.Contains('<') then
            Dir := 'RL';
        if Dir.Contains('^') then
            Dir := 'BT';
        if Dir.Contains('>') then
            Dir := 'LR';
        if Dir.Contains('v') then
            Dir := 'TB';
        if Dir = 'TD' then
            Dir := 'TB';
        FlowDirection := Dir;
    end;

    // ---------------------------------------------------------------- document

    local procedure Document()
    var
        C: Integer;
    begin
        while Pos <= SrcLen do begin
            C := Cur();
            if MText.IsSpace(C) or (C = 59) then
                Pos += 1
            else
                if IsKw('end') then begin
                    if FrameIds.Count() = 0 then
                        Fail(StatementStartTok);
                    Pos += 3;
                    while MText.IsSpace(Cur()) do
                        Pos += 1;
                    CloseSubgraph();
                end else
                    if IsKw('subgraph') then begin
                        Pos += 8;
                        OpenSubgraph();
                    end else
                        Statement();
        end;
        if FrameIds.Count() > 0 then
            Fail('''end''');
    end;

    local procedure AddMember(Id: Text)
    var
        Last: Integer;
    begin
        Last := FrameMembers.Count();
        if Last = 0 then
            exit;
        if MText.TrimWs(Id) = '' then
            exit;
        FrameMembers.Set(Last, FrameMembers.Get(Last) + Id + MText.LF());
    end;

    local procedure OpenSubgraph()
    var
        C: Integer;
        IdText: Text;
        IdType: Text;
        TitleText: Text;
        TitleType: Text;
        HasId: Boolean;
        TitleGiven: Boolean;
    begin
        C := Cur();
        if (C = 10) or (C = 59) or (C = -1) then
            Pos += 1
        else begin
            if not IsBlankChar(C) then
                Fail('''SPACE'', ''SEMI'', ''NEWLINE'', ''EOF''');
            SkipBlanks();
            TextNoTags(IdText, IdType);
            HasId := true;
            TitleText := IdText;
            TitleType := IdType;
            if Cur() = 91 then begin
                Pos += 1;
                ReadLabel(1, TitleText, TitleType);
                ExpectCloser(1, 'SQE');
                TitleGiven := true;
            end;
            SkipBlanks();
            C := Cur();
            if (C <> 10) and (C <> 59) and (C <> -1) then
                Fail('''SEMI'', ''NEWLINE'', ''EOF'', ''SQS''');
            Pos += 1;
        end;
        FrameHasId.Add(HasId);
        FrameIds.Add(IdText);
        FrameTitleGiven.Add(TitleGiven);
        FrameTitles.Add(TitleText);
        if HasId then
            FrameTitleTypes.Add(TitleType)
        else
            FrameTitleTypes.Add('');
        FrameMembers.Add('');
        FrameDirs.Add('');
    end;

    /// <summary>pele's addSubGraph: a subgraph takes the nodes listed in it that no subgraph closed before has taken.</summary>
    local procedure CloseSubgraph()
    var
        Last: Integer;
        HasId: Boolean;
        Id: Text;
        TitleText: Text;
        TitleType: Text;
        MemberText: Text;
        Dir: Text;
        Member: Text;
        Seen: Dictionary of [Text, Boolean];
        Taken: List of [Text];
        Existing: Boolean;
    begin
        Last := FrameIds.Count();
        HasId := FrameHasId.Get(Last);
        Id := MText.TrimWs(FrameIds.Get(Last));
        TitleText := FrameTitles.Get(Last);
        TitleType := FrameTitleTypes.Get(Last);
        MemberText := FrameMembers.Get(Last);
        Dir := FrameDirs.Get(Last);
        if HasId and not FrameTitleGiven.Get(Last) and MText.ContainsWs(TitleText) then
            Id := '';
        FrameHasId.RemoveAt(Last);
        FrameIds.RemoveAt(Last);
        FrameTitleGiven.RemoveAt(Last);
        FrameTitles.RemoveAt(Last);
        FrameTitleTypes.RemoveAt(Last);
        FrameMembers.RemoveAt(Last);
        FrameDirs.RemoveAt(Last);

        if (Dir = '') and InheritDir then
            Dir := FlowDirection;
        if Id = '' then
            Id := 'subGraph' + MText.IntText(SubCount);
        SubCount += 1;

        foreach Member in MemberText.Split(MText.LF()) do
            if (MText.TrimWs(Member) <> '') and not Seen.ContainsKey(Member) then begin
                Seen.Add(Member, true);
                if (not Members.ContainsKey(Member)) and (Member <> Id) then begin
                    Members.Add(Member, true);
                    Taken.Add(Member);
                end;
            end;

        Existing := SubgraphIds.ContainsKey(Id);
        if not Existing then begin
            SubgraphIds.Add(Id, true);
            if not FindNode(Id) then
                NewNode(Id);
            TempNode."Is Group" := true;
            TempNode.Label := CopyStr(MText.TrimWs(TitleText), 1, MaxStrLen(TempNode.Label));
            TempNode."Label Type" := CopyStr(LabelTypeOf(TitleType), 1, MaxStrLen(TempNode."Label Type"));
            TempNode."Has Label" := true;
            TempNode.Direction := CopyStr(Dir, 1, MaxStrLen(TempNode.Direction));
            TempNode.Modify();
        end;
        foreach Member in Taken do
            if FindNode(Member) then begin
                TempNode."Parent Id" := CopyStr(Id, 1, MaxStrLen(TempNode."Parent Id"));
                TempNode.Modify();
            end;
        AddMember(Id);
    end;

    local procedure LabelTypeOf(TypeName: Text): Text
    begin
        if TypeName in ['markdown', 'string', 'text'] then
            exit(TypeName);
        exit('markdown');
    end;

    /// <summary>A subgraph id: a quoted string, or text up to a bracket or the end of the line.</summary>
    local procedure TextNoTags(var Value: Text; var TypeName: Text)
    var
        StartPos: Integer;
        C: Integer;
    begin
        Value := '';
        TypeName := 'text';
        if Cur() = 34 then begin
            if Ahead(1) = 96 then
                TypeName := 'markdown';
            Value := ReadQuoted();
        end;
        StartPos := Pos;
        C := Cur();
        while (C <> -1) and (C <> 10) and (C <> 59) and (C <> 91) and (C <> 34) and (C <> 40) and (C <> 123) and (C <> 124) and (C <> 93) and (C <> 41) and (C <> 125) do begin
            Pos += 1;
            C := Cur();
        end;
        Value += MText.Substr(Src, StartPos, Pos);
        if Value = '' then
            Fail('''NODE_STRING'', ''STR'', ''MD_STR''');
    end;

    // ---------------------------------------------------------------- statements

    local procedure Statement()
    var
        Id: Text;
        Ids: Text;
        ClassName: Text;
        Styles: List of [Text];
        Nodes: List of [Text];
        NodeId: Text;
        Dir: Text;
        Close: Integer;
    begin
        if IsKw('style') then begin
            Pos += 5;
            ExpectBlank();
            Id := IdString();
            ExpectBlank();
            Styles := StylesOpt(false);
            AddVertexStyles(Id, Styles);
            Separator();
            exit;
        end;
        if IsKw('linkStyle') then begin
            LinkStyleStatement();
            Separator();
            exit;
        end;
        if IsKw('classDef') then begin
            Pos += 8;
            ExpectBlank();
            Ids := IdString();
            ExpectBlank();
            Styles := StylesOpt(true);
            AddClass(Ids, Styles);
            Separator();
            exit;
        end;
        if IsKw('class') then begin
            Pos += 5;
            ExpectBlank();
            Ids := IdString();
            ExpectBlank();
            ClassName := IdString();
            SetClass(Ids, ClassName);
            Separator();
            exit;
        end;
        if MText.StartsWithAt(Src, 'click', Pos) and MText.IsSpace(Ahead(5)) then begin
            Pos += 5;
            while MText.IsSpace(Cur()) do
                Pos += 1;
            ClickStatement();
            Separator();
            exit;
        end;
        if IsKw('direction') then begin
            Pos += 9;
            SkipBlanks();
            Dir := CopyStr(Src, Pos, 2);
            if not (Dir in ['TB', 'BT', 'RL', 'LR', 'TD']) then
                Fail('''direction_tb''');
            if FrameDirs.Count() > 0 then
                FrameDirs.Set(FrameDirs.Count(), Dir);
            while (Cur() <> 10) and (Cur() <> -1) do
                Pos += 1;
            exit;
        end;
        if MText.StartsWithAt(Src, 'accTitle', Pos) then
            if MText.CharAt(Src, SkipWsFrom(Pos + 8)) = 58 then begin
                Pos := SkipWsFrom(SkipWsFrom(Pos + 8) + 1);
                AccTitleValue := MText.TrimStartWs(MText.TrimWs(RestOfLine()));
                exit;
            end;
        if MText.StartsWithAt(Src, 'accDescr', Pos) then begin
            if MText.CharAt(Src, SkipWsFrom(Pos + 8)) = 58 then begin
                Pos := SkipWsFrom(SkipWsFrom(Pos + 8) + 1);
                AccDescrValue := MText.TrimWs(RestOfLine());
                exit;
            end;
            if MText.CharAt(Src, SkipWsFrom(Pos + 8)) = 123 then begin
                Pos := SkipWsFrom(SkipWsFrom(Pos + 8) + 1);
                Close := MText.IndexOfFrom(Src, '}', Pos);
                if Close = 0 then
                    Close := SrcLen + 1;
                AccDescrValue := CollapseIndent(MText.TrimWs(MText.Substr(Src, Pos, Close)));
                Pos := Close + 1;
                exit;
            end;
        end;
        if not IsIdChar(Cur(), Pos) then
            Fail(StatementStartTok);
        Nodes := VertexStatement();
        Separator();
        foreach NodeId in Nodes do
            AddMember(NodeId);
    end;

    local procedure SkipWsFrom(P: Integer): Integer
    begin
        while MText.IsSpace(MText.CharAt(Src, P)) do
            P += 1;
        exit(P);
    end;

    local procedure RestOfLine(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        while (Cur() <> 10) and (Cur() <> -1) do
            Pos += 1;
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    local procedure CollapseIndent(Value: Text): Text
    var
        Lines: List of [Text];
        Builder: TextBuilder;
        I: Integer;
    begin
        Lines := Value.Split(MText.LF());
        for I := 1 to Lines.Count() do begin
            if I > 1 then begin
                Builder.Append(MText.LF());
                Builder.Append(MText.TrimStartWs(Lines.Get(I)));
            end else
                Builder.Append(Lines.Get(I));
        end;
        exit(Builder.ToText());
    end;

    /// <summary>Style declarations up to the end of the statement, split at commas; for classDef an escaped \, stays a comma.</summary>
    local procedure StylesOpt(Escaped: Boolean): List of [Text]
    var
        Result: List of [Text];
        Builder: TextBuilder;
        C: Integer;
    begin
        C := Cur();
        if (C = 10) or (C = 59) or (C = -1) or (C = 44) then
            Fail('''NODE_STRING'', ''NUM'', ''COLON'', ''BRKT''');
        while (C <> 10) and (C <> 59) and (C <> -1) do begin
            if C = 44 then begin
                Result.Add(Builder.ToText());
                Builder.Clear();
            end else
                if Escaped and (C = 92) and (Ahead(1) = 44) then begin
                    Builder.Append(',');
                    Pos += 1;
                end else
                    Builder.Append(CopyStr(Src, Pos, 1));
            Pos += 1;
            C := Cur();
        end;
        Result.Add(Builder.ToText());
        exit(Result);
    end;

    local procedure LinkStyleStatement()
    var
        Positions: List of [Text];
        Styles: List of [Text];
        Curve: Text;
        StartPos: Integer;
    begin
        Pos += 9;
        ExpectBlank();
        if IsKw('default') then begin
            Positions.Add('default');
            Pos += 7;
        end else begin
            Positions.Add(ReadNumber());
            while Cur() = 44 do begin
                Pos += 1;
                Positions.Add(ReadNumber());
            end;
        end;
        ExpectBlank();
        if not IsKw('interpolate') then begin
            Styles := StylesOpt(false);
            UpdateLink(Positions, Styles);
            exit;
        end;
        Pos += 11;
        ExpectBlank();
        StartPos := Pos;
        while IsIdChar(Cur(), Pos) do
            Pos += 1;
        Curve := MText.Substr(Src, StartPos, Pos);
        if Curve = '' then
            Fail('''NODE_STRING''');
        UpdateLinkInterpolate(Positions, Curve);
        if IsBlankChar(Cur()) then begin
            SkipBlanks();
            if (Cur() <> 10) and (Cur() <> 59) and (Cur() <> -1) then begin
                Styles := StylesOpt(false);
                UpdateLink(Positions, Styles);
            end;
        end;
    end;

    local procedure ReadNumber(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        while MText.IsDigit(Cur()) do
            Pos += 1;
        if Pos = StartPos then
            Fail('''NUM'', ''DEFAULT''');
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    local procedure ReadQuoted(): Text
    var
        Close: Integer;
        Value: Text;
    begin
        if Ahead(1) = 96 then begin
            Close := MText.IndexOfFrom(Src, '`"', Pos + 2);
            if Close = 0 then
                FailLexical();
            Value := MText.Substr(Src, Pos + 2, Close);
            Pos := Close + 2;
            exit(Value);
        end;
        Close := MText.IndexOfFrom(Src, '"', Pos + 1);
        if Close = 0 then
            FailLexical();
        Value := MText.Substr(Src, Pos + 1, Close);
        Pos := Close + 1;
        exit(Value);
    end;

    local procedure ClickStatement()
    var
        Id: Text;
        StartPos: Integer;
        Url: Text;
        Tooltip: Text;
        Close: Integer;
    begin
        StartPos := Pos;
        while (Cur() <> -1) and not MText.IsSpace(Cur()) do
            Pos += 1;
        Id := MText.Substr(Src, StartPos, Pos);
        while MText.IsSpace(Cur()) and (Cur() <> 10) do
            Pos += 1;
        if MText.StartsWithAt(Src, 'call', Pos) and MText.IsSpace(Ahead(4)) then begin
            Pos += 4;
            SkipBlanks();
            Close := MText.IndexOfFrom(Src, '(', Pos);
            if Close > 0 then begin
                Pos := Close;
                Close := MText.IndexOfFrom(Src, ')', Pos);
                if Close = 0 then
                    Close := SrcLen;
                Pos := Close + 1;
            end else
                while (Cur() <> 10) and (Cur() <> -1) do
                    Pos += 1;
            SetClass(Id, 'clickable');
            if IsBlankChar(Cur()) then begin
                SkipBlanks();
                if Cur() = 34 then
                    SetTooltip(Id, ReadQuoted());
            end;
            exit;
        end;
        if MText.StartsWithAt(Src, 'href', Pos) and MText.IsSpace(Ahead(4)) then begin
            Pos += 4;
            SkipBlanks();
            if Cur() <> 34 then
                Fail('''STR''');
            Url := ReadQuoted();
            LinkTail(Id, Url);
            exit;
        end;
        if Cur() = 34 then begin
            Url := ReadQuoted();
            LinkTail(Id, Url);
            exit;
        end;
        // A callback name: the node is only marked clickable, as in Mermaid's strict mode.
        StartPos := Pos;
        while IsIdChar(Cur(), Pos) do
            Pos += 1;
        if Pos = StartPos then
            Fail('''NODE_STRING''');
        SetClass(Id, 'clickable');
        if IsBlankChar(Cur()) then begin
            SkipBlanks();
            if Cur() = 34 then begin
                Tooltip := ReadQuoted();
                SetTooltip(Id, Tooltip);
            end;
        end;
    end;

    local procedure LinkTail(Id: Text; Url: Text)
    var
        Target: Text;
        Tooltip: Text;
    begin
        if IsBlankChar(Cur()) then begin
            SkipBlanks();
            if Cur() = 34 then begin
                Tooltip := ReadQuoted();
                SetTooltip(Id, Tooltip);
                SkipBlanks();
            end;
            Target := ReadLinkTarget();
        end;
        SetLink(Id, Url, Target);
    end;

    local procedure ReadLinkTarget(): Text
    var
        Target: Text;
    begin
        foreach Target in '_self,_blank,_parent,_top'.Split(',') do
            if IsKw(Target) then begin
                Pos += StrLen(Target);
                exit(Target);
            end;
        exit('');
    end;

    // ---------------------------------------------------------------- vertices

    local procedure IsIdChar(C: Integer; At: Integer): Boolean
    var
        Next: Integer;
    begin
        if C = -1 then
            exit(false);
        if MText.IsWord(C) then
            exit(true);
        // ! # $ % & ' * + . ` ? \ /
        if C in [33, 35, 36, 37, 38, 39, 42, 43, 46, 96, 63, 92, 47] then
            exit(true);
        if C = 58 then
            exit(not MText.StartsWithAt(Src, ':::', At));
        if C = 44 then
            exit(true);
        if C = 45 then begin
            Next := MText.CharAt(Src, At + 1);
            exit(not (Next in [62, 45, 46]) and (Next <> -1));
        end;
        exit(MText.IsUnicodeLetter(C));
    end;

    local procedure IdString(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        while IsIdChar(Cur(), Pos) do
            Pos += 1;
        if Pos = StartPos then
            Fail('''NODE_STRING''');
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    local procedure FindNode(Id: Text): Boolean
    begin
        if StrLen(Id) > MaxStrLen(TempNode.Id) then
            Id := CopyStr(Id, 1, MaxStrLen(TempNode.Id));
        TempNode.Reset();
        TempNode.SetCurrentKey(Id);
        TempNode.SetRange(Id, Id);
        if TempNode.FindFirst() then begin
            TempNode.Reset();
            exit(true);
        end;
        TempNode.Reset();
        exit(false);
    end;

    local procedure NewNode(Id: Text)
    begin
        NextNodeNo += 1;
        TempNode.Init();
        TempNode."Entry No." := NextNodeNo;
        TempNode.Id := CopyStr(Id, 1, MaxStrLen(TempNode.Id));
        TempNode."Label Type" := 'text';
        TempNode.Insert();
    end;

    local procedure AddVertex(Id: Text; TextGiven: Boolean; TextValue: Text; TextType: Text; ShapeType: Text)
    begin
        if MText.TrimWs(Id) = '' then
            exit;
        if not FindNode(Id) then
            NewNode(Id);
        if TextGiven then begin
            TempNode."Label Type" := CopyStr(TextType, 1, MaxStrLen(TempNode."Label Type"));
            TempNode.Label := CopyStr(Unquote(MText.TrimWs(TextValue)), 1, MaxStrLen(TempNode.Label));
            TempNode."Has Label" := true;
        end else
            if not TempNode."Has Label" then begin
                TempNode.Label := CopyStr(Id, 1, MaxStrLen(TempNode.Label));
                TempNode."Has Label" := true;
            end;
        if ShapeType <> '' then
            TempNode.Shape := CopyStr(ShapeType, 1, MaxStrLen(TempNode.Shape));
        TempNode.Modify();
    end;

    local procedure AddVertexStyles(Id: Text; Styles: List of [Text])
    var
        S: Text;
    begin
        AddVertex(Id, false, '', '', '');
        if not FindNode(Id) then
            exit;
        foreach S in Styles do
            TempNode.Styles := CopyStr(JoinStyle(TempNode.Styles, S), 1, MaxStrLen(TempNode.Styles));
        TempNode.Modify();
    end;

    local procedure Unquote(Value: Text): Text
    begin
        if (StrLen(Value) >= 2) and Value.StartsWith('"') and Value.EndsWith('"') then
            exit(CopyStr(Value, 2, StrLen(Value) - 2));
        exit(Value);
    end;

    local procedure StyledVertex(): Text
    var
        Id: Text;
    begin
        Id := Vertex();
        if MText.StartsWithAt(Src, ':::', Pos) then begin
            Pos += 3;
            SetClass(Id, IdString());
        end;
        exit(Id);
    end;

    local procedure Vertex(): Text
    var
        Id: Text;
        LabelText: Text;
        LabelKind: Text;
        C: Integer;
        D: Integer;
    begin
        Id := IdString();
        C := Cur();
        D := Ahead(1);
        case C of
            91:
                case D of
                    91:
                        begin
                            Pos += 2;
                            ReadLabel(1, LabelText, LabelKind);
                            ExpectCloser(1, 'SUBROUTINEEND');
                            AddVertex(Id, true, LabelText, LabelKind, 'subroutine');
                        end;
                    40:
                        begin
                            Pos += 2;
                            ReadLabel(1, LabelText, LabelKind);
                            ExpectCloser(1, 'CYLINDEREND');
                            AddVertex(Id, true, LabelText, LabelKind, 'cylinder');
                        end;
                    47:
                        begin
                            Pos += 2;
                            ReadLabel(3, LabelText, LabelKind);
                            if CloserAt(3) = 'INVTRAPEND' then begin
                                Pos += 2;
                                AddVertex(Id, true, LabelText, LabelKind, 'lean_right');
                            end else begin
                                ExpectCloser(3, 'TRAPEND');
                                AddVertex(Id, true, LabelText, LabelKind, 'trapezoid');
                            end;
                        end;
                    92:
                        begin
                            Pos += 2;
                            ReadLabel(3, LabelText, LabelKind);
                            if CloserAt(3) = 'TRAPEND' then begin
                                Pos += 2;
                                AddVertex(Id, true, LabelText, LabelKind, 'lean_left');
                            end else begin
                                ExpectCloser(3, 'INVTRAPEND');
                                AddVertex(Id, true, LabelText, LabelKind, 'inv_trapezoid');
                            end;
                        end;
                    124:
                        begin
                            // [|field:value|text] : the property is read and not used.
                            Pos += 2;
                            IdString();
                            if Cur() <> 58 then
                                Fail('''COLON''');
                            Pos += 1;
                            IdString();
                            if Cur() <> 124 then
                                Fail('''PIPE''');
                            Pos += 1;
                            ReadLabel(1, LabelText, LabelKind);
                            ExpectCloser(1, 'SQE');
                            AddVertex(Id, true, LabelText, LabelKind, 'rect');
                        end;
                    else begin
                        Pos += 1;
                        ReadLabel(1, LabelText, LabelKind);
                        ExpectCloser(1, 'SQE');
                        AddVertex(Id, true, LabelText, LabelKind, 'square');
                    end;
                end;
            40:
                if D = 45 then begin
                    Pos += 2;
                    ReadLabel(2, LabelText, LabelKind);
                    ExpectCloser(2, 'ELLIPSE_END');
                    AddVertex(Id, true, LabelText, LabelKind, 'ellipse');
                end else
                    if D = 91 then begin
                        Pos += 2;
                        ReadLabel(1, LabelText, LabelKind);
                        ExpectCloser(1, 'STADIUMEND');
                        AddVertex(Id, true, LabelText, LabelKind, 'stadium');
                    end else
                        if (D = 40) and (Ahead(2) = 40) then begin
                            Pos += 3;
                            ReadLabel(1, LabelText, LabelKind);
                            ExpectCloser(1, 'DOUBLECIRCLEEND');
                            AddVertex(Id, true, LabelText, LabelKind, 'doublecircle');
                        end else
                            if D = 40 then begin
                                Pos += 2;
                                ReadLabel(1, LabelText, LabelKind);
                                ExpectCloser(1, 'PE');
                                ExpectCloser(1, 'PE');
                                AddVertex(Id, true, LabelText, LabelKind, 'circle');
                            end else begin
                                Pos += 1;
                                ReadLabel(1, LabelText, LabelKind);
                                ExpectCloser(1, 'PE');
                                AddVertex(Id, true, LabelText, LabelKind, 'round');
                            end;
            123:
                if D = 123 then begin
                    Pos += 2;
                    ReadLabel(1, LabelText, LabelKind);
                    ExpectCloser(1, 'DIAMOND_STOP');
                    ExpectCloser(1, 'DIAMOND_STOP');
                    AddVertex(Id, true, LabelText, LabelKind, 'hexagon');
                end else begin
                    Pos += 1;
                    ReadLabel(1, LabelText, LabelKind);
                    ExpectCloser(1, 'DIAMOND_STOP');
                    AddVertex(Id, true, LabelText, LabelKind, 'diamond');
                end;
            62:
                begin
                    Pos += 1;
                    ReadLabel(1, LabelText, LabelKind);
                    ExpectCloser(1, 'SQE');
                    AddVertex(Id, true, LabelText, LabelKind, 'odd');
                end;
            else
                AddVertex(Id, false, '', '', '');
        end;
        exit(Id);
    end;

    /// <summary>
    /// Text inside a shape (Mode 1), an ellipse (2) or a trapezoid (3), or between pipes: a quoted string or plain text,
    /// followed by more plain text. Stops at the closer, which the caller then expects.
    /// </summary>
    local procedure ReadLabel(Mode: Integer; var Value: Text; var TypeName: Text)
    var
        Part: Text;
    begin
        if Cur() = 34 then begin
            if Ahead(1) = 96 then
                TypeName := 'markdown'
            else
                TypeName := 'string';
            Value := ReadQuoted();
        end else begin
            Part := ReadPlain(Mode);
            if Part = '' then
                Fail(TextTokensTok);
            TypeName := 'text';
            Value := Part;
        end;
        Part := ReadPlain(Mode);
        while Part <> '' do begin
            Value += Part;
            Part := ReadPlain(Mode);
        end;
    end;

    local procedure ReadPlain(Mode: Integer): Text
    var
        StartPos: Integer;
        C: Integer;
        D: Integer;
        Stop: Boolean;
    begin
        StartPos := Pos;
        repeat
            C := Cur();
            D := Ahead(1);
            Stop := (C = -1) or (C = 34);
            if not Stop then
                case Mode of
                    1:
                        Stop := C in [91, 93, 40, 41, 123, 125, 124];
                    2:
                        Stop := (C in [40, 41, 91, 93, 123, 125]) or (((C = 45) or (C = 47)) and (D = 41));
                    3:
                        Stop := (C in [91, 93, 40, 41, 123, 125]) or (((C = 92) or (C = 47) or (C = 63) or (C = 61)) and (D = 93));
                end;
            if not Stop then
                Pos += 1;
        until Stop;
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    /// <summary>The token that closes a label at the current position, named as pele's lexer names it.</summary>
    local procedure CloserAt(Mode: Integer): Text
    var
        C: Integer;
        D: Integer;
    begin
        C := Cur();
        D := Ahead(1);
        case Mode of
            2:
                if ((C = 45) or (C = 47) or (C = 41)) and (D = 41) then
                    exit('ELLIPSE_END');
            3:
                begin
                    if (C = 47) and (D = 93) then
                        exit('INVTRAPEND');
                    if ((C = 92) or (C = 93) or (C = 41) or (C = 63) or (C = 61)) and (D = 93) then
                        exit('TRAPEND');
                end;
            else
                case C of
                    93:
                        begin
                            if D = 41 then
                                exit('STADIUMEND');
                            if D = 93 then
                                exit('SUBROUTINEEND');
                            exit('SQE');
                        end;
                    41:
                        begin
                            if D = 93 then
                                exit('CYLINDEREND');
                            if (D = 41) and (Ahead(2) = 41) then
                                exit('DOUBLECIRCLEEND');
                            exit('PE');
                        end;
                    124:
                        exit('PIPE');
                    125:
                        exit('DIAMOND_STOP');
                end;
        end;
        exit(TokenName());
    end;

    local procedure CloserLength(Name: Text): Integer
    begin
        case Name of
            'SQE', 'PE', 'PIPE', 'DIAMOND_STOP':
                exit(1);
            'DOUBLECIRCLEEND':
                exit(3);
        end;
        exit(2);
    end;

    local procedure ExpectCloser(Mode: Integer; Name: Text)
    begin
        if CloserAt(Mode) <> Name then
            Fail('''' + Name + ''', ' + TextTokensTok);
        Pos += CloserLength(Name);
    end;

    // ---------------------------------------------------------------- shape data

    local procedure ReadShapeData(): Text
    var
        Builder: TextBuilder;
        C: Integer;
        InString: Boolean;
    begin
        Pos += 2;
        C := Cur();
        while (C <> -1) and (InString or (C <> 125)) do begin
            if C = 34 then
                InString := not InString;
            if InString and (C = 10) then
                Builder.Append('<br/>')
            else
                Builder.Append(CopyStr(Src, Pos, 1));
            Pos += 1;
            C := Cur();
        end;
        if C = -1 then
            FailLexical();
        Pos += 1;
        exit(Builder.ToText());
    end;

    /// <summary>Reads key: value pairs, separated by commas or line breaks, as the YAML of shape data holds them.</summary>
    local procedure ParseShapeData(Data: Text; var Values: Dictionary of [Text, Text])
    var
        Builder: TextBuilder;
        Pairs: List of [Text];
        Pair: Text;
        I: Integer;
        C: Integer;
        Quote: Integer;
        Colon: Integer;
        KeyName: Text;
        Value: Text;
    begin
        for I := 1 to StrLen(Data) do begin
            C := Data[I];
            if Quote <> 0 then begin
                if C = Quote then
                    Quote := 0;
                Builder.Append(CopyStr(Data, I, 1));
            end else
                if (C = 34) or (C = 39) then begin
                    Quote := C;
                    Builder.Append(CopyStr(Data, I, 1));
                end else
                    if (C = 44) or (C = 10) then begin
                        Pairs.Add(Builder.ToText());
                        Builder.Clear();
                    end else
                        Builder.Append(CopyStr(Data, I, 1));
        end;
        Pairs.Add(Builder.ToText());
        foreach Pair in Pairs do begin
            Colon := StrPos(Pair, ':');
            if Colon > 1 then begin
                KeyName := MText.TrimWs(CopyStr(Pair, 1, Colon - 1));
                Value := MText.TrimWs(CopyStr(Pair, Colon + 1));
                if (StrLen(Value) >= 2) and ((Value.StartsWith('"') and Value.EndsWith('"')) or (Value.StartsWith('''') and Value.EndsWith(''''))) then
                    Value := CopyStr(Value, 2, StrLen(Value) - 2);
                if Values.ContainsKey(KeyName) then
                    Values.Set(KeyName, Value)
                else
                    Values.Add(KeyName, Value);
            end else
                if MText.TrimWs(Pair) <> '' then
                    MText.Fail('Metadata is not valid YAML: ' + MText.TrimWs(Pair));
        end;
    end;

    local procedure ApplyShapeData(Id: Text; Data: Text)
    var
        Values: Dictionary of [Text, Text];
        Shape: Text;
        Value: Text;
        EdgeNo: Integer;
    begin
        ParseShapeData(Data, Values);
        if SubgraphIds.ContainsKey(Id) then
            exit;
        if EdgeIds.Get(Id, EdgeNo) then begin
            if Values.Get('curve', Value) then
                if TempEdge.Get(EdgeNo) then begin
                    TempEdge.Interpolate := CopyStr(Value, 1, MaxStrLen(TempEdge.Interpolate));
                    TempEdge.Modify();
                end;
            exit;
        end;
        AddVertex(Id, false, '', '', '');
        FindNode(Id);
        if Values.Get('shape', Shape) and (Shape <> '') then begin
            if (Shape <> LowerCase(Shape)) or Shape.Contains('_') then
                MText.Fail('No such shape: ' + Shape + '. Shape names should be lowercase.');
            if not Shapes.IsValidShape(Shape) then
                MText.Fail('No such shape: ' + Shape + '.');
            TempNode.Shape := CopyStr(Shape, 1, MaxStrLen(TempNode.Shape));
        end;
        if Values.Get('label', Value) and (Value <> '') then begin
            TempNode.Label := CopyStr(Value, 1, MaxStrLen(TempNode.Label));
            if Values.Get('labelType', Value) then
                TempNode."Label Type" := CopyStr(LabelTypeOf(Value), 1, MaxStrLen(TempNode."Label Type"))
            else
                TempNode."Label Type" := 'markdown';
        end;
        TempNode.Modify();
    end;

    // ---------------------------------------------------------------- statements of vertices and links

    local procedure NodeGroup(var Ids: List of [Text]; var PendingData: Text; var HasPending: Boolean)
    var
        Data: Text;
        HasData: Boolean;
        Save: Integer;
        Done: Boolean;
    begin
        Ids.Add(StyledVertex());
        HasPending := false;
        repeat
            HasData := false;
            if MText.StartsWithAt(Src, '@{', Pos) then begin
                Data := ReadShapeData();
                HasData := true;
            end;
            Save := Pos;
            SkipBlanks();
            if Cur() = 38 then begin
                Pos += 1;
                SkipBlanks();
                Ids.Add(StyledVertex());
                if HasData then
                    ApplyShapeData(Ids.Get(Ids.Count() - 1), Data);
            end else begin
                Pos := Save;
                if HasData then begin
                    PendingData := Data;
                    HasPending := true;
                end;
                Done := true;
            end;
        until Done;
    end;

    local procedure VertexStatement(): List of [Text]
    var
        Stmt: List of [Text];
        NextIds: List of [Text];
        All: List of [Text];
        Id: Text;
        PendingData: Text;
        HasPending: Boolean;
        LinkId: Text;
        ArrowType: Text;
        Stroke: Text;
        Length: Integer;
        LinkText: Text;
        LinkTextType: Text;
        HasText: Boolean;
        Save: Integer;
        Done: Boolean;
    begin
        NodeGroup(Stmt, PendingData, HasPending);
        if HasPending then
            ApplyShapeData(Stmt.Get(Stmt.Count()), PendingData);
        foreach Id in Stmt do
            All.Add(Id);
        repeat
            Save := Pos;
            SkipBlanks();
            LinkId := ReadLinkId();
            if (LinkId <> '') or LinkAhead() then begin
                ReadLink(ArrowType, Stroke, Length, HasText, LinkText, LinkTextType);
                Clear(NextIds);
                NodeGroup(NextIds, PendingData, HasPending);
                if HasPending then
                    ApplyShapeData(NextIds.Get(NextIds.Count()), PendingData);
                AddLinks(Stmt, NextIds, LinkId, ArrowType, Stroke, Length, HasText, LinkText, LinkTextType);
                foreach Id in NextIds do
                    All.Add(Id);
                Stmt := NextIds;
            end else begin
                Pos := Save;
                Done := true;
            end;
        until Done;
        exit(All);
    end;

    /// <summary>A link id: the run of non-space characters up to its last @ that is not followed by { or ".</summary>
    local procedure ReadLinkId(): Text
    var
        RunEnd: Integer;
        K: Integer;
        At: Integer;
        Id: Text;
    begin
        if (Cur() = 34) or (Cur() = -1) then
            exit('');
        RunEnd := Pos;
        while (MText.CharAt(Src, RunEnd) <> -1) and (MText.CharAt(Src, RunEnd) <> 34) and not MText.IsSpace(MText.CharAt(Src, RunEnd)) do
            RunEnd += 1;
        At := 0;
        for K := RunEnd - 1 downto Pos + 1 do
            if At = 0 then
                if MText.CharAt(Src, K) = 64 then
                    if not (MText.CharAt(Src, K + 1) in [123, 34]) then
                        At := K;
        if At = 0 then
            exit('');
        Id := MText.Substr(Src, Pos, At);
        Pos := At + 1;
        exit(Id);
    end;

    local procedure LinkAhead(): Boolean
    var
        EndPos: Integer;
        Kind: Integer;
    begin
        exit((MatchLink(Pos, EndPos) > 0) or (MatchStartLink(Pos, EndPos, Kind)));
    end;

    local procedure IsArrowPrefix(C: Integer): Boolean
    begin
        exit((C = 120) or (C = 111) or (C = 60));
    end;

    local procedure IsArrowEnd(C: Integer): Boolean
    begin
        exit((C = 120) or (C = 111) or (C = 62));
    end;

    /// <summary>[xo&lt;]?CC+[Cxo&gt;] for C = - or =, as RE_LINK and RE_THICK_LINK; the end, or 0.</summary>
    local procedure MatchRun(P: Integer; Ch: Integer): Integer
    var
        Result: Integer;
    begin
        if IsArrowPrefix(MText.CharAt(Src, P)) and (MText.CharAt(Src, P + 1) = Ch) then begin
            Result := MatchRunAt(P + 1, Ch);
            if Result > 0 then
                exit(Result);
        end;
        exit(MatchRunAt(P, Ch));
    end;

    local procedure MatchRunAt(P: Integer; Ch: Integer): Integer
    var
        L: Integer;
    begin
        while MText.CharAt(Src, P + L) = Ch do
            L += 1;
        if L < 2 then
            exit(0);
        if IsArrowEnd(MText.CharAt(Src, P + L)) then
            exit(P + L + 1);
        if L >= 3 then
            exit(P + L);
        exit(0);
    end;

    /// <summary>[xo&lt;]?-?\.+-[xo&gt;]?, as RE_DOTTED_LINK.</summary>
    local procedure MatchDotted(P: Integer): Integer
    var
        Result: Integer;
    begin
        if IsArrowPrefix(MText.CharAt(Src, P)) then begin
            Result := MatchDottedAt(P + 1);
            if Result > 0 then
                exit(Result);
        end;
        exit(MatchDottedAt(P));
    end;

    local procedure MatchDottedAt(P: Integer): Integer
    var
        Q: Integer;
        Dots: Integer;
    begin
        Q := P;
        if MText.CharAt(Src, Q) = 45 then
            Q += 1;
        while MText.CharAt(Src, Q + Dots) = 46 do
            Dots += 1;
        if Dots = 0 then
            exit(0);
        Q += Dots;
        if MText.CharAt(Src, Q) <> 45 then
            exit(0);
        Q += 1;
        if IsArrowEnd(MText.CharAt(Src, Q)) then
            Q += 1;
        exit(Q);
    end;

    local procedure MatchInvisible(P: Integer): Integer
    var
        L: Integer;
    begin
        while MText.CharAt(Src, P + L) = 126 do
            L += 1;
        if L < 3 then
            exit(0);
        exit(P + L);
    end;

    /// <summary>The character a link would start with after an optional x, o or &lt;.</summary>
    local procedure LinkCharAt(P: Integer): Integer
    begin
        if IsArrowPrefix(MText.CharAt(Src, P)) then
            exit(MText.CharAt(Src, P + 1));
        exit(MText.CharAt(Src, P));
    end;

    /// <summary>A whole link at P, in the order pele's lexer tries them; the end after trailing blanks, or 0.</summary>
    local procedure MatchLink(P: Integer; var EndPos: Integer): Integer
    var
        Q: Integer;
        D: Integer;
        E: Integer;
    begin
        Q := SkipBlanksFrom(P);
        D := LinkCharAt(Q);
        E := 0;
        case D of
            45:
                begin
                    E := MatchRun(Q, 45);
                    if E = 0 then
                        if not StartLinkOnly(Q) then
                            E := MatchDotted(Q);
                end;
            61:
                E := MatchRun(Q, 61);
            46:
                E := MatchDotted(Q);
            126:
                E := MatchInvisible(Q);
        end;
        if E = 0 then
            exit(0);
        EndPos := SkipBlanksFrom(E);
        exit(E);
    end;

    /// <summary>Whether START_LINK (two dashes) wins over a dotted link here, as it does in pele's lexer order.</summary>
    local procedure StartLinkOnly(Q: Integer): Boolean
    var
        R: Integer;
    begin
        R := Q;
        if IsArrowPrefix(MText.CharAt(Src, R)) then
            R += 1;
        exit((MText.CharAt(Src, R) = 45) and (MText.CharAt(Src, R + 1) = 45));
    end;

    /// <summary>The start of a link with its text inline: --, == or -. ; Kind 1, 2 or 3.</summary>
    local procedure MatchStartLink(P: Integer; var EndPos: Integer; var Kind: Integer): Boolean
    var
        Q: Integer;
        R: Integer;
    begin
        Q := SkipBlanksFrom(P);
        R := Q;
        if IsArrowPrefix(MText.CharAt(Src, R)) and (MText.CharAt(Src, R + 1) in [45, 61]) then
            R += 1;
        if (MText.CharAt(Src, R) = 45) and (MText.CharAt(Src, R + 1) = 45) and (MatchRun(Q, 45) = 0) then begin
            Kind := 1;
            EndPos := SkipBlanksFrom(R + 2);
            exit(true);
        end;
        if (MText.CharAt(Src, R) = 61) and (MText.CharAt(Src, R + 1) = 61) and (MatchRun(Q, 61) = 0) then begin
            Kind := 2;
            EndPos := SkipBlanksFrom(R + 2);
            exit(true);
        end;
        if (MText.CharAt(Src, R) = 45) and (MText.CharAt(Src, R + 1) = 46) and (MatchDotted(Q) = 0) then begin
            Kind := 3;
            EndPos := SkipBlanksFrom(R + 2);
            exit(true);
        end;
        exit(false);
    end;

    local procedure MatchClosing(Kind: Integer; P: Integer): Integer
    var
        Q: Integer;
    begin
        Q := SkipBlanksFrom(P);
        case Kind of
            1:
                exit(MatchRun(Q, 45));
            2:
                exit(MatchRun(Q, 61));
        end;
        exit(MatchDotted(Q));
    end;

    local procedure ReadLink(var ArrowType: Text; var Stroke: Text; var Length: Integer; var HasText: Boolean; var LinkText: Text; var LinkTextType: Text)
    var
        EndPos: Integer;
        E: Integer;
        Kind: Integer;
        StartText: Text;
        EndText: Text;
        Q: Integer;
    begin
        HasText := false;
        LinkText := '';
        LinkTextType := 'text';
        E := MatchLink(Pos, EndPos);
        if E > 0 then begin
            EndText := MText.TrimWs(MText.Substr(Src, Pos, E));
            DestructLink(EndText, '', ArrowType, Stroke, Length);
            Pos := EndPos;
            if Cur() = 124 then begin
                Pos += 1;
                ReadLabel(1, LinkText, LinkTextType);
                ExpectCloser(1, 'PIPE');
                HasText := true;
                SkipBlanks();
            end;
            exit;
        end;
        if MatchStartLink(Pos, EndPos, Kind) then begin
            StartText := MText.TrimWs(MText.Substr(Src, Pos, EndPos));
            Pos := EndPos;
            ReadEdgeText(Kind, LinkText, LinkTextType);
            HasText := true;
            Q := SkipBlanksFrom(Pos);
            E := MatchClosing(Kind, Pos);
            if E = 0 then
                Fail('''LINK'', ''EDGE_TEXT''');
            EndText := MText.Substr(Src, Q, E);
            Pos := SkipBlanksFrom(E);
            DestructLink(EndText, StartText, ArrowType, Stroke, Length);
            exit;
        end;
        Fail('''LINK'', ''START_LINK''');
    end;

    local procedure ReadEdgeText(Kind: Integer; var Value: Text; var TypeName: Text)
    var
        A: Integer;
        B: Integer;
        C: Integer;
        D: Integer;
        Q: Integer;
        Stop: Boolean;
        Done: Boolean;
        First: Boolean;
    begin
        case Kind of
            1:
                begin
                    A := 45;
                    B := -2;
                end;
            2:
                begin
                    A := 61;
                    B := -2;
                end;
            else begin
                A := 46;
                B := 45;
            end;
        end;
        Value := '';
        TypeName := 'text';
        First := true;
        repeat
            C := Cur();
            if C = -1 then
                Fail('''LINK''');
            D := LinkCharAt(SkipBlanksFrom(Pos));
            if ((D = A) or (D = B)) and (MatchClosing(Kind, Pos) > 0) then
                Done := true
            else
                if C = 34 then begin
                    if not First then
                        Fail('''LINK'', ''EDGE_TEXT''');
                    if Ahead(1) = 96 then
                        TypeName := 'markdown'
                    else
                        TypeName := 'string';
                    Value += ReadQuoted();
                end else begin
                    if (C = A) and ((A <> 45) or (Ahead(1) = 45)) then
                        FailLexical();
                    Q := Pos + 1;
                    Stop := false;
                    while not Stop do begin
                        C := MText.CharAt(Src, Q);
                        if (C = -1) or (C = 34) or (C = 10) then
                            Stop := true
                        else
                            if C = A then begin
                                if (A <> 45) or (MText.CharAt(Src, Q + 1) = 45) then
                                    Stop := true;
                            end else
                                if IsArrowPrefix(C) or (C = B) or IsBlankChar(C) then
                                    if (LinkCharAt(SkipBlanksFrom(Q)) in [A, B]) and (MatchClosing(Kind, Q) > 0) then
                                        Stop := true;
                        if not Stop then
                            Q += 1;
                    end;
                    if MText.CharAt(Src, Q) = 10 then
                        Fail('''LINK''');
                    Value += MText.Substr(Src, Pos, Q);
                    Pos := Q;
                end;
            First := false;
        until Done;
    end;

    local procedure CountChar(Ch: Text; Value: Text): Integer
    var
        I: Integer;
        Cnt: Integer;
    begin
        for I := 1 to StrLen(Value) do
            if CopyStr(Value, I, 1) = Ch then
                Cnt += 1;
        exit(Cnt);
    end;

    local procedure DestructEndLink(Raw: Text; var ArrowType: Text; var Stroke: Text; var Length: Integer)
    var
        Str: Text;
        Line: Text;
        LastCh: Text;
        Dots: Integer;
    begin
        Str := MText.TrimWs(Raw);
        Line := CopyStr(Str, 1, StrLen(Str) - 1);
        LastCh := CopyStr(Str, StrLen(Str), 1);
        ArrowType := 'arrow_open';
        case LastCh of
            'x':
                begin
                    ArrowType := 'arrow_cross';
                    if Str.StartsWith('x') then begin
                        ArrowType := 'double_' + ArrowType;
                        Line := CopyStr(Line, 2);
                    end;
                end;
            '>':
                begin
                    ArrowType := 'arrow_point';
                    if Str.StartsWith('<') then begin
                        ArrowType := 'double_' + ArrowType;
                        Line := CopyStr(Line, 2);
                    end;
                end;
            'o':
                begin
                    ArrowType := 'arrow_circle';
                    if Str.StartsWith('o') then begin
                        ArrowType := 'double_' + ArrowType;
                        Line := CopyStr(Line, 2);
                    end;
                end;
        end;
        Stroke := 'normal';
        Length := StrLen(Line) - 1;
        if Line.StartsWith('=') then
            Stroke := 'thick';
        if Line.StartsWith('~') then
            Stroke := 'invisible';
        Dots := CountChar('.', Line);
        if Dots > 0 then begin
            Stroke := 'dotted';
            Length := Dots;
        end;
    end;

    local procedure DestructStartLink(Raw: Text; var ArrowType: Text; var Stroke: Text)
    var
        Str: Text;
    begin
        Str := MText.TrimWs(Raw);
        ArrowType := 'arrow_open';
        case CopyStr(Str, 1, 1) of
            '<':
                begin
                    ArrowType := 'arrow_point';
                    Str := CopyStr(Str, 2);
                end;
            'x':
                begin
                    ArrowType := 'arrow_cross';
                    Str := CopyStr(Str, 2);
                end;
            'o':
                begin
                    ArrowType := 'arrow_circle';
                    Str := CopyStr(Str, 2);
                end;
        end;
        Stroke := 'normal';
        if Str.Contains('=') then
            Stroke := 'thick';
        if Str.Contains('.') then
            Stroke := 'dotted';
    end;

    local procedure DestructLink(EndText: Text; StartText: Text; var ArrowType: Text; var Stroke: Text; var Length: Integer)
    var
        StartType: Text;
        StartStroke: Text;
    begin
        DestructEndLink(EndText, ArrowType, Stroke, Length);
        if StartText = '' then
            exit;
        DestructStartLink(StartText, StartType, StartStroke);
        if StartStroke <> Stroke then begin
            ArrowType := 'INVALID';
            Stroke := 'INVALID';
            exit;
        end;
        if StartType = 'arrow_open' then
            StartType := ArrowType
        else begin
            if StartType <> ArrowType then begin
                ArrowType := 'INVALID';
                Stroke := 'INVALID';
                exit;
            end;
            StartType := 'double_' + StartType;
        end;
        if StartType = 'double_arrow' then
            StartType := 'double_arrow_point';
        ArrowType := StartType;
    end;

    local procedure AddLinks(Starts: List of [Text]; Ends: List of [Text]; LinkId: Text; ArrowType: Text; Stroke: Text; Length: Integer; HasText: Boolean; LinkText: Text; LinkTextType: Text)
    var
        StartId: Text;
        EndId: Text;
        Id: Text;
    begin
        foreach StartId in Starts do
            foreach EndId in Ends do begin
                Id := '';
                if (StartId = Starts.Get(Starts.Count())) and (EndId = Ends.Get(1)) then
                    Id := LinkId;
                AddSingleLink(StartId, EndId, Id, ArrowType, Stroke, Length, HasText, LinkText, LinkTextType);
            end;
    end;

    local procedure AddSingleLink(StartId: Text; EndId: Text; Id: Text; ArrowType: Text; Stroke: Text; Length: Integer; HasText: Boolean; LinkText: Text; LinkTextType: Text)
    var
        PairKey: Text;
        Existing: Integer;
    begin
        if (MaxEdges > 0) and (TempEdge.Count() >= MaxEdges) then
            MText.Fail('Edge limit exceeded. ' + MText.IntText(TempEdge.Count()) + ' edges found, but the limit is ' + MText.IntText(MaxEdges) + '.');
        NextEdgeNo += 1;
        TempEdge.Init();
        TempEdge."Entry No." := NextEdgeNo;
        TempEdge."Start Id" := CopyStr(StartId, 1, MaxStrLen(TempEdge."Start Id"));
        TempEdge."End Id" := CopyStr(EndId, 1, MaxStrLen(TempEdge."End Id"));
        TempEdge."Label Type" := 'text';
        if HasText then begin
            TempEdge.Label := CopyStr(Unquote(MText.TrimWs(LinkText)), 1, MaxStrLen(TempEdge.Label));
            TempEdge."Label Type" := CopyStr(LabelTypeOf(LinkTextType), 1, MaxStrLen(TempEdge."Label Type"));
        end;
        TempEdge."Arrow Type" := CopyStr(ArrowType, 1, MaxStrLen(TempEdge."Arrow Type"));
        TempEdge.Stroke := CopyStr(Stroke, 1, MaxStrLen(TempEdge.Stroke));
        if Length > 10 then
            Length := 10;
        TempEdge.Length := Length;
        TempEdge.Interpolate := CopyStr(DefaultInterpolate, 1, MaxStrLen(TempEdge.Interpolate));
        PairKey := StartId + MText.LF() + EndId;
        if (Id <> '') and not EdgeIds.ContainsKey(Id) then begin
            TempEdge."Edge Id" := CopyStr(Id, 1, MaxStrLen(TempEdge."Edge Id"));
            TempEdge."User Defined Id" := true;
        end else begin
            if not PairCount.Get(PairKey, Existing) then
                Existing := 0;
            if Existing = 0 then
                TempEdge."Edge Id" := CopyStr('L_' + StartId + '_' + EndId + '_0', 1, MaxStrLen(TempEdge."Edge Id"))
            else
                TempEdge."Edge Id" := CopyStr('L_' + StartId + '_' + EndId + '_' + MText.IntText(Existing + 1), 1, MaxStrLen(TempEdge."Edge Id"));
        end;
        TempEdge.Insert();
        if PairCount.ContainsKey(PairKey) then
            PairCount.Set(PairKey, PairCount.Get(PairKey) + 1)
        else
            PairCount.Add(PairKey, 1);
        if not EdgeIds.ContainsKey(TempEdge."Edge Id") then
            EdgeIds.Add(TempEdge."Edge Id", TempEdge."Entry No.");
    end;

    // ---------------------------------------------------------------- styles and classes

    local procedure UpdateLinkInterpolate(Positions: List of [Text]; Curve: Text)
    var
        P: Text;
    begin
        foreach P in Positions do
            if P = 'default' then
                DefaultInterpolate := Curve
            else begin
                EdgeAt(P);
                TempEdge.Interpolate := CopyStr(Curve, 1, MaxStrLen(TempEdge.Interpolate));
                TempEdge.Modify();
            end;
    end;

    local procedure UpdateLink(Positions: List of [Text]; Styles: List of [Text])
    var
        P: Text;
        S: Text;
        Joined: Text;
        HasFill: Boolean;
    begin
        foreach S in Styles do begin
            Joined := JoinStyle(Joined, S);
            if S.StartsWith('fill') then
                HasFill := true;
        end;
        foreach P in Positions do
            if P = 'default' then
                DefaultEdgeStyle := Joined
            else begin
                EdgeAt(P);
                if (Styles.Count() > 0) and not HasFill then
                    TempEdge.Styles := CopyStr(JoinStyle(Joined, 'fill:none'), 1, MaxStrLen(TempEdge.Styles))
                else
                    TempEdge.Styles := CopyStr(Joined, 1, MaxStrLen(TempEdge.Styles));
                TempEdge."Has Style" := true;
                TempEdge.Modify();
            end;
    end;

    local procedure EdgeAt(P: Text)
    var
        Index: Integer;
    begin
        if not Evaluate(Index, P) then
            Index := -1;
        if (Index < 0) or not TempEdge.Get(Index + 1) then
            MText.Fail('The index ' + P + ' for linkStyle is out of bounds. Valid indices for linkStyle are between 0 and ' + MText.IntText(TempEdge.Count() - 1) +
                       '. (Help: Ensure that the index is within the range of existing edges.)');
    end;

    local procedure AddClass(Ids: Text; Styles: List of [Text])
    var
        Id: Text;
        S: Text;
        Existing: Text;
        TextStyles: Text;
        All: Text;
    begin
        foreach S in Styles do begin
            All := JoinStyle(All, S);
            if S.Contains('color') then
                TextStyles := JoinStyle(TextStyles, ReplaceFirst(S, 'fill', 'bgFill'));
        end;
        foreach Id in Ids.Split(',') do begin
            if ClassStyles.Get(Id, Existing) then
                ClassStyles.Set(Id, JoinStyle(Existing, All))
            else
                ClassStyles.Add(Id, All);
            if ClassTextStyles.Get(Id, Existing) then
                ClassTextStyles.Set(Id, JoinStyle(Existing, TextStyles))
            else
                ClassTextStyles.Add(Id, TextStyles);
        end;
    end;

    local procedure ReplaceFirst(Value: Text; Old: Text; New: Text): Text
    var
        P: Integer;
    begin
        P := StrPos(Value, Old);
        if P = 0 then
            exit(Value);
        exit(CopyStr(Value, 1, P - 1) + New + CopyStr(Value, P + StrLen(Old)));
    end;

    local procedure SetClass(Ids: Text; ClassName: Text)
    var
        Id: Text;
        EdgeNo: Integer;
    begin
        foreach Id in Ids.Split(',') do begin
            if FindNode(Id) then begin
                TempNode.Classes := CopyStr(MText.TrimWs(TempNode.Classes + ' ' + ClassName), 1, MaxStrLen(TempNode.Classes));
                TempNode.Modify();
            end;
            if EdgeIds.Get(Id, EdgeNo) then
                if TempEdge.Get(EdgeNo) then begin
                    TempEdge.Classes := CopyStr(MText.TrimWs(TempEdge.Classes + ' ' + ClassName), 1, MaxStrLen(TempEdge.Classes));
                    TempEdge.Modify();
                end;
        end;
    end;

    local procedure SetTooltip(Ids: Text; Tooltip: Text)
    var
        Id: Text;
    begin
        foreach Id in Ids.Split(',') do
            if FindNode(Id) then begin
                TempNode.Tooltip := CopyStr(Tooltip, 1, MaxStrLen(TempNode.Tooltip));
                TempNode.Modify();
            end;
    end;

    local procedure SetLink(Ids: Text; Url: Text; Target: Text)
    var
        Id: Text;
    begin
        Url := MText.TrimWs(Url);
        foreach Id in Ids.Split(',') do
            if FindNode(Id) then begin
                if Url <> '' then
                    TempNode.Link := CopyStr(SafeUrl(Url), 1, MaxStrLen(TempNode.Link))
                else
                    TempNode.Link := '';
                TempNode."Link Target" := CopyStr(Target, 1, MaxStrLen(TempNode."Link Target"));
                TempNode.Modify();
            end;
        SetClass(Ids, 'clickable');
    end;

    /// <summary>Follows @braintree/sanitize-url in spirit: a javascript:, data: or vbscript: target becomes about:blank.</summary>
    procedure SafeUrl(Url: Text): Text
    var
        Decoded: Text;
        Cleaned: TextBuilder;
        I: Integer;
        C: Integer;
        Scheme: Text;
        Colon: Integer;
    begin
        Decoded := MText.DecodeEntities(Url);
        for I := 1 to StrLen(Decoded) do begin
            C := Decoded[I];
            if (C > 32) and (C <> 127) and not ((C >= 128) and (C <= 159)) and not ((C >= 8203) and (C <= 8205)) and (C <> 65279) then
                Cleaned.Append(CopyStr(Decoded, I, 1));
        end;
        Decoded := Cleaned.ToText();
        Colon := StrPos(Decoded, ':');
        if Colon > 0 then begin
            Scheme := '';
            for I := 1 to Colon - 1 do
                if MText.IsWord(MText.CharAt(Decoded, I)) then
                    Scheme += LowerCase(CopyStr(Decoded, I, 1));
            if Scheme in ['javascript', 'data', 'vbscript'] then
                exit('about:blank');
        end;
        exit(Url);
    end;
}
