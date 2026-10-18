/// <summary>
/// Port of pele's preprocess.ts and detect.ts: line endings, HTML attribute quotes, YAML front
/// matter, %%{init}%% directives, comment lines, Mermaid's entity placeholders and diagram detection.
/// Configuration is kept as a flat dictionary of dotted paths, such as "flowchart.curve".
/// </summary>
codeunit 68901 "Mermaid Preprocessor"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";

    procedure Preprocess(Source: Text; var Body: Text; var Title: Text; var Config: Dictionary of [Text, Text])
    var
        Txt: Text;
    begin
        Clear(Config);
        Title := '';
        Txt := Source;
        if StrPos(Txt, MText.CR()) > 0 then begin
            Txt := Txt.Replace(MText.CR() + MText.LF(), MText.LF());
            Txt := Txt.Replace(MText.CR(), MText.LF());
        end;
        Txt := QuoteHtmlAttributes(Txt);
        Txt := FrontMatter(Txt, Title, Config);
        Txt := Directives(Txt, Config);
        Body := CleanupComments(Txt);
    end;

    // ---------------------------------------------------------------- HTML attributes

    /// <summary>Turns attr="x" into attr='x' inside HTML tags, so the double quotes cannot end a Mermaid string.</summary>
    local procedure QuoteHtmlAttributes(Txt: Text): Text
    var
        Builder: TextBuilder;
        LastClose: Integer;
        I: Integer;
        J: Integer;
        K: Integer;
        Handled: Boolean;
    begin
        if StrPos(Txt, '<') = 0 then
            exit(Txt);
        LastClose := MText.LastIndexOf(Txt, '>');
        if LastClose <= 1 then
            exit(Txt);
        I := 1;
        while I <= StrLen(Txt) do begin
            Handled := false;
            if (MText.CharAt(Txt, I) = 60) and (I < LastClose) and MText.IsWord(MText.CharAt(Txt, I + 1)) then begin
                J := I + 1;
                while MText.IsWord(MText.CharAt(Txt, J)) do
                    J += 1;
                K := MText.IndexOfFrom(Txt, '>', J);
                if (K > 0) and (K <= LastClose) then begin
                    Builder.Append(MText.Substr(Txt, I, J));
                    Builder.Append(QuoteAttributes(MText.Substr(Txt, J, K)));
                    Builder.Append('>');
                    I := K + 1;
                    Handled := true;
                end;
            end;
            if not Handled then begin
                Builder.Append(CopyStr(Txt, I, 1));
                I += 1;
            end;
        end;
        exit(Builder.ToText());
    end;

    local procedure QuoteAttributes(Attrs: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        J: Integer;
    begin
        if StrPos(Attrs, '="') = 0 then
            exit(Attrs);
        I := 1;
        while I <= StrLen(Attrs) do
            if (MText.CharAt(Attrs, I) = 61) and (MText.CharAt(Attrs, I + 1) = 34) and (MText.IndexOfFrom(Attrs, '"', I + 2) > 0) then begin
                J := MText.IndexOfFrom(Attrs, '"', I + 2);
                Builder.Append('=''' + MText.Substr(Attrs, I + 2, J) + '''');
                I := J + 1;
            end else begin
                Builder.Append(CopyStr(Attrs, I, 1));
                I += 1;
            end;
        exit(Builder.ToText());
    end;

    // ---------------------------------------------------------------- front matter

    /// <summary>Removes a --- fenced YAML block at the start of the text and reads its title and config.</summary>
    local procedure FrontMatter(Txt: Text; var Title: Text; var Config: Dictionary of [Text, Text]): Text
    var
        Values: Dictionary of [Text, Text];
        Cursor: Integer;
        Indent: Text;
        OpeningEnd: Integer;
        LineStart: Integer;
        LineEnd: Integer;
        J: Integer;
        Line: Text;
        BodyStart: Integer;
        ClosingStart: Integer;
        RestStart: Integer;
        Body: Text;
        KeyName: Text;
        Value: Text;
    begin
        if StrPos(Txt, '---') = 0 then
            exit(Txt);
        Cursor := 1;
        while MText.IsSpace(MText.CharAt(Txt, Cursor)) and not MText.IsLineEnd(MText.CharAt(Txt, Cursor)) do
            Cursor += 1;
        Indent := MText.Substr(Txt, 1, Cursor);
        if not MText.StartsWithAt(Txt, '---', Cursor) then
            exit(Txt);
        // The opening fence is followed by nothing but whitespace up to a line break.
        J := Cursor + 3;
        OpeningEnd := 0;
        while (OpeningEnd = 0) and MText.IsSpace(MText.CharAt(Txt, J)) do begin
            if MText.CharAt(Txt, J) = 10 then
                OpeningEnd := J;
            J += 1;
        end;
        if OpeningEnd = 0 then
            exit(Txt);
        BodyStart := OpeningEnd + 1;
        // The closing fence is the first line that holds the indent and --- and nothing else.
        LineStart := BodyStart;
        ClosingStart := 0;
        while (ClosingStart = 0) and (LineStart <= StrLen(Txt)) do begin
            LineEnd := MText.IndexOfFrom(Txt, MText.LF(), LineStart);
            if LineEnd = 0 then
                LineEnd := StrLen(Txt) + 1;
            Line := MText.Substr(Txt, LineStart, LineEnd);
            if (LineEnd <= StrLen(Txt)) and Line.StartsWith(Indent + '---') and MText.IsBlankText(CopyStr(Line, StrLen(Indent) + 4)) then begin
                ClosingStart := LineStart;
                RestStart := LineEnd + 1;
            end;
            LineStart := LineEnd + 1;
        end;
        if ClosingStart = 0 then
            exit(Txt);
        Body := MText.Substr(Txt, BodyStart, ClosingStart - 1);
        if Indent <> '' then
            Body := Dedent(Body, Indent);
        ParseYaml(Body, Values);
        foreach KeyName in Values.Keys() do begin
            Value := Values.Get(KeyName);
            if KeyName = 'title' then
                Title := Value
            else
                if KeyName.StartsWith('config.') then
                    SetConfig(Config, CopyStr(KeyName, 8), Value)
                else
                    if KeyName = 'displayMode' then
                        SetConfig(Config, 'gantt.displayMode', Value);
        end;
        exit(CopyStr(Txt, RestStart));
    end;

    local procedure Dedent(Body: Text; Indent: Text): Text
    var
        Builder: TextBuilder;
        Line: Text;
        First: Boolean;
    begin
        First := true;
        foreach Line in Body.Split(MText.LF()) do begin
            if not First then
                Builder.Append(MText.LF());
            First := false;
            if Line.StartsWith(Indent) then
                Builder.Append(CopyStr(Line, StrLen(Indent) + 1))
            else
                Builder.Append(Line);
        end;
        exit(Builder.ToText());
    end;

    /// <summary>
    /// Reads the subset of YAML that diagram front matter uses: nested maps of scalars, by indentation.
    /// Every scalar is stored under its dotted path. Lists and multi-line scalars are skipped.
    /// </summary>
    local procedure ParseYaml(Body: Text; var Values: Dictionary of [Text, Text])
    var
        Indents: List of [Integer];
        Paths: List of [Text];
        Line: Text;
        Content: Text;
        Indent: Integer;
        Colon: Integer;
        KeyName: Text;
        Value: Text;
        Path: Text;
    begin
        foreach Line in Body.Split(MText.LF()) do begin
            Content := MText.TrimWs(Line);
            if (Content <> '') and not Content.StartsWith('#') and not Content.StartsWith('-') then begin
                Indent := 1;
                while MText.IsBlank(MText.CharAt(Line, Indent)) do
                    Indent += 1;
                Colon := KeyColon(Content);
                if Colon > 0 then begin
                    KeyName := Unquote(MText.TrimWs(CopyStr(Content, 1, Colon - 1)));
                    Value := MText.TrimWs(CopyStr(Content, Colon + 1));
                    while DeeperOrSame(Indents, Indent) do begin
                        Indents.RemoveAt(Indents.Count());
                        Paths.RemoveAt(Paths.Count());
                    end;
                    if Paths.Count() > 0 then
                        Path := Paths.Get(Paths.Count()) + KeyName
                    else
                        Path := KeyName;
                    if (Value = '') or (Value = '|') or (Value = '>') then begin
                        Indents.Add(Indent);
                        Paths.Add(Path + '.');
                    end else
                        if not IsUnsafeKey(KeyName) then
                            SetConfig(Values, Path, YamlScalar(Value));
                end;
            end;
        end;
    end;

    local procedure DeeperOrSame(var Indents: List of [Integer]; Indent: Integer): Boolean
    begin
        if Indents.Count() = 0 then
            exit(false);
        exit(Indents.Get(Indents.Count()) >= Indent);
    end;

    local procedure KeyColon(Content: Text): Integer
    var
        I: Integer;
        Quote: Integer;
        C: Integer;
    begin
        for I := 1 to StrLen(Content) do begin
            C := Content[I];
            if Quote <> 0 then begin
                if C = Quote then
                    Quote := 0;
            end else
                if (C = 34) or (C = 39) then
                    Quote := C
                else
                    if (C = 58) and ((I = StrLen(Content)) or MText.IsSpace(MText.CharAt(Content, I + 1))) then
                        exit(I);
        end;
        exit(0);
    end;

    local procedure YamlScalar(Value: Text): Text
    var
        Hash: Integer;
    begin
        if Value.StartsWith('"') or Value.StartsWith('''') then
            exit(Unquote(Value));
        Hash := StrPos(Value, ' #');
        if Hash > 0 then
            Value := MText.TrimWs(CopyStr(Value, 1, Hash - 1));
        exit(Value);
    end;

    local procedure Unquote(Value: Text): Text
    var
        Q: Text;
    begin
        if StrLen(Value) < 2 then
            exit(Value);
        Q := CopyStr(Value, 1, 1);
        if ((Q = '"') or (Q = '''')) and (CopyStr(Value, StrLen(Value), 1) = Q) then begin
            Value := CopyStr(Value, 2, StrLen(Value) - 2);
            if Q = '"' then
                Value := Value.Replace('\"', '"').Replace('\n', MText.LF())
            else
                Value := Value.Replace('''''', '''');
        end;
        exit(Value);
    end;

    local procedure IsUnsafeKey(KeyName: Text): Boolean
    begin
        exit((KeyName = '__proto__') or (KeyName = 'constructor') or (KeyName = 'prototype'));
    end;

    local procedure SetConfig(var Config: Dictionary of [Text, Text]; Path: Text; Value: Text)
    begin
        if Config.ContainsKey(Path) then
            Config.Set(Path, Value)
        else
            Config.Add(Path, Value);
    end;

    // ---------------------------------------------------------------- directives

    /// <summary>Applies and removes %%{init: {...}}%% and %%{wrap}%% directives.</summary>
    local procedure Directives(Txt: Text; var Config: Dictionary of [Text, Text]): Text
    var
        Builder: TextBuilder;
        StartPos: Integer;
        EndPos: Integer;
        LastPos: Integer;
        Inner: Text;
        Kind: Text;
        Args: Text;
        I: Integer;
        Args2: JsonObject;
    begin
        if StrPos(Txt, '%%{') = 0 then
            exit(Txt);
        LastPos := 1;
        StartPos := StrPos(Txt, '%%{');
        while StartPos > 0 do begin
            EndPos := MText.IndexOfFrom(Txt, '}%%', StartPos + 3);
            if EndPos = 0 then
                EndPos := StrLen(Txt) + 1;
            Inner := MText.TrimWs(MText.Substr(Txt, StartPos + 3, EndPos));
            I := 1;
            while MText.IsWord(MText.CharAt(Inner, I)) do
                I += 1;
            Kind := CopyStr(Inner, 1, I - 1);
            Args := MText.TrimWs(CopyStr(Inner, I));
            if Args.StartsWith(':') then
                Args := MText.TrimWs(CopyStr(Args, 2));
            if Kind = 'wrap' then
                SetConfig(Config, 'wrap', 'true')
            else
                if ((Kind = 'init') or (Kind = 'initialize')) and (Args <> '') then
                    if Args2.ReadFrom(Args.Replace('''', '"')) then
                        FlattenJson(Args2, '', Config);
            Builder.Append(MText.Substr(Txt, LastPos, StartPos));
            LastPos := EndPos + 3;
            if LastPos > StrLen(Txt) + 1 then
                LastPos := StrLen(Txt) + 1;
            StartPos := MText.IndexOfFrom(Txt, '%%{', LastPos);
        end;
        Builder.Append(CopyStr(Txt, LastPos));
        exit(Builder.ToText());
    end;

    local procedure FlattenJson(Obj: JsonObject; Prefix: Text; var Config: Dictionary of [Text, Text])
    var
        KeyName: Text;
        Token: JsonToken;
        Raw: Text;
    begin
        foreach KeyName in Obj.Keys() do
            if not IsUnsafeKey(KeyName) then begin
                Obj.Get(KeyName, Token);
                if Token.IsObject() then
                    FlattenJson(Token.AsObject(), Prefix + KeyName + '.', Config)
                else
                    if Token.IsValue() then
                        if not Token.AsValue().IsNull() then begin
                            Token.WriteTo(Raw);
                            if Raw.StartsWith('"') then
                                Raw := Token.AsValue().AsText();
                            SetConfig(Config, Prefix + KeyName, Raw);
                        end;
            end;
    end;

    // ---------------------------------------------------------------- comments

    /// <summary>Drops %% comment lines (but not %%{ directives) and leading whitespace.</summary>
    procedure CleanupComments(Txt: Text): Text
    var
        Builder: TextBuilder;
        Line: Text;
        Trimmed: Text;
        Lines: List of [Text];
        I: Integer;
    begin
        if StrPos(Txt, '%%') > 0 then begin
            Lines := Txt.Split(MText.LF());
            for I := 1 to Lines.Count() do begin
                Line := Lines.Get(I);
                Trimmed := MText.TrimStartWs(Line);
                // A comment line goes, with its line break.
                if not (Trimmed.StartsWith('%%') and (StrLen(Trimmed) > 2) and (MText.CharAt(Trimmed, 3) <> 123)) then begin
                    Builder.Append(Line);
                    if I < Lines.Count() then
                        Builder.Append(MText.LF());
                end;
            end;
            Txt := Builder.ToText();
        end;
        exit(MText.TrimStartWs(Txt));
    end;

    // ---------------------------------------------------------------- entities

    /// <summary>Mermaid hides #name; entity codes behind placeholder characters so # and ; survive parsing.</summary>
    procedure EncodeEntities(Txt: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        J: Integer;
        Inner: Text;
        Handled: Boolean;
    begin
        if StrPos(Txt, '#') = 0 then
            exit(Txt);
        Txt := DropColorSemicolons(DropColorSemicolons(Txt, 'style'), 'classDef');
        I := 1;
        while I <= StrLen(Txt) do begin
            Handled := false;
            if MText.CharAt(Txt, I) = 35 then begin
                J := I + 1;
                while MText.IsWord(MText.CharAt(Txt, J)) do
                    J += 1;
                if (J > I + 1) and (MText.CharAt(Txt, J) = 59) then begin
                    Inner := MText.Substr(Txt, I + 1, J);
                    if IsInteger(Inner) then
                        Builder.Append(MText.PlaceholderOpen() + MText.PlaceholderNumeric() + Inner + MText.PlaceholderClose())
                    else
                        Builder.Append(MText.PlaceholderOpen() + Inner + MText.PlaceholderClose());
                    I := J + 1;
                    Handled := true;
                end;
            end;
            if not Handled then begin
                Builder.Append(CopyStr(Txt, I, 1));
                I += 1;
            end;
        end;
        exit(Builder.ToText());
    end;

    local procedure IsInteger(Value: Text): Boolean
    var
        I: Integer;
    begin
        if Value = '' then
            exit(false);
        for I := 1 to StrLen(Value) do
            if not MText.IsDigit(Value[I]) then
                exit(false);
        exit(true);
    end;

    /// <summary>
    /// On a line where the keyword is followed by a colon, a colour-like #, and later a semicolon, the last
    /// semicolon goes, as Mermaid's text.replace(/keyword.*:\S*#.*;/g) does.
    /// </summary>
    local procedure DropColorSemicolons(Txt: Text; Keyword: Text): Text
    var
        Builder: TextBuilder;
        FromPos: Integer;
        LineEnd: Integer;
        LastPos: Integer;
        J: Integer;
        C: Integer;
        AfterColon: Boolean;
        Hash: Integer;
        Semi: Integer;
        Changed: Boolean;
    begin
        FromPos := StrPos(Txt, Keyword);
        if FromPos = 0 then
            exit(Txt);
        LastPos := 1;
        while FromPos > 0 do begin
            LineEnd := FromPos;
            while (LineEnd <= StrLen(Txt)) and not MText.IsLineEnd(MText.CharAt(Txt, LineEnd)) do
                LineEnd += 1;
            AfterColon := false;
            Hash := 0;
            J := FromPos + StrLen(Keyword);
            while (Hash = 0) and (J < LineEnd) do begin
                C := MText.CharAt(Txt, J);
                if C = 58 then
                    AfterColon := true
                else
                    if C = 35 then begin
                        if AfterColon then
                            Hash := J;
                    end else
                        if MText.IsSpace(C) then
                            AfterColon := false;
                J += 1;
            end;
            if Hash > 0 then begin
                Semi := 0;
                for J := LineEnd - 1 downto Hash + 1 do
                    if Semi = 0 then
                        if MText.CharAt(Txt, J) = 59 then
                            Semi := J;
                if Semi > 0 then begin
                    Builder.Append(MText.Substr(Txt, LastPos, Semi));
                    LastPos := Semi + 1;
                    Changed := true;
                end;
            end;
            if LineEnd > StrLen(Txt) then
                FromPos := 0
            else
                FromPos := MText.IndexOfFrom(Txt, Keyword, LineEnd + 1);
        end;
        if not Changed then
            exit(Txt);
        Builder.Append(CopyStr(Txt, LastPos));
        exit(Builder.ToText());
    end;

    // ---------------------------------------------------------------- detection

    /// <summary>Mermaid's detectors, in the order Mermaid registers them. The first match wins.</summary>
    procedure Detect(Cleaned: Text): Text
    begin
        if Starts(Cleaned, 'flowchart-elk', false) then
            exit('flowchart');
        if Starts(Cleaned, 'mindmap', false) then
            exit('mindmap');
        if Starts(Cleaned, 'architecture', false) then
            exit('architecture');
        if StartsWord(Cleaned, 'agentflow-beta') then
            exit('agentflow');
        if Starts(Cleaned, 'C4Context', false) or (StrPos(Cleaned, 'C4Container') > 0) or (StrPos(Cleaned, 'C4Component') > 0) or
           (StrPos(Cleaned, 'C4Dynamic') > 0) or (StrPos(Cleaned, 'C4Deployment') > 0)
        then
            exit('c4');
        if Starts(Cleaned, 'kanban', false) then
            exit('kanban');
        if Starts(Cleaned, 'classDiagram', false) then
            exit('class');
        if Starts(Cleaned, 'erDiagram', false) then
            exit('er');
        if Starts(Cleaned, 'gantt', false) then
            exit('gantt');
        if Starts(Cleaned, 'info', false) then
            exit('info');
        if Starts(Cleaned, 'pie', false) then
            exit('pie');
        if Starts(Cleaned, 'requirement', false) then
            exit('requirement');
        if Starts(Cleaned, 'sequenceDiagram', false) then
            exit('sequence');
        if StartsWord(Cleaned, 'swimlane-beta') then
            exit('swimlane');
        if Starts(Cleaned, 'graph', false) or Starts(Cleaned, 'flowchart', false) then
            exit('flowchart');
        if Starts(Cleaned, 'timeline', false) then
            exit('timeline');
        if Starts(Cleaned, 'gitGraph', false) then
            exit('gitGraph');
        if Starts(Cleaned, 'stateDiagram', false) then
            exit('state');
        if Starts(Cleaned, 'journey', false) then
            exit('journey');
        if Starts(Cleaned, 'quadrantChart', false) then
            exit('quadrantChart');
        if Starts(Cleaned, 'sankey', false) then
            exit('sankey');
        if Starts(Cleaned, 'packet', false) then
            exit('packet');
        if Starts(Cleaned, 'xychart', false) then
            exit('xychart');
        if Starts(Cleaned, 'block', false) then
            exit('block');
        if Starts(Cleaned, 'eventmodeling', false) then
            exit('eventmodeling');
        if Starts(Cleaned, 'treeView-beta', false) then
            exit('treeView');
        if Starts(Cleaned, 'radar-beta', false) then
            exit('radar');
        if Starts(Cleaned, 'ishikawa', true) then
            exit('ishikawa');
        if Starts(Cleaned, 'treemap', false) then
            exit('treemap');
        if Starts(Cleaned, 'railroad-', true) then
            exit('railroad');
        if Starts(Cleaned, 'venn-beta', false) then
            exit('venn');
        if Starts(Cleaned, 'wardley-beta', true) then
            exit('wardley');
        if Starts(Cleaned, 'cynefin-beta', false) then
            exit('cynefin');
        if Starts(Cleaned, 'usecase-beta', false) then
            exit('usecase');
        exit('');
    end;

    local procedure Starts(Cleaned: Text; Keyword: Text; IgnoreCase: Boolean): Boolean
    var
        Rest: Text;
    begin
        Rest := MText.TrimStartWs(Cleaned);
        if IgnoreCase then
            exit(LowerCase(CopyStr(Rest, 1, StrLen(Keyword))) = LowerCase(Keyword));
        exit(Rest.StartsWith(Keyword));
    end;

    local procedure StartsWord(Cleaned: Text; Keyword: Text): Boolean
    var
        Rest: Text;
    begin
        Rest := MText.TrimStartWs(Cleaned);
        if not Rest.StartsWith(Keyword) then
            exit(false);
        exit(not MText.IsWord(MText.CharAt(Rest, StrLen(Keyword) + 1)));
    end;
}
