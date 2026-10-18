/// <summary>
/// A measured label: port of pele's text/label.ts (layoutLabel) and labelSvg from svg/builder.ts.
/// Each instance holds one label. Lines are lists of styled spans; inline &lt;b&gt;, &lt;i&gt;, &lt;br&gt;
/// and, for markdown labels, *emphasis* and **strong** are understood. Lines wrap at word gaps.
/// </summary>
codeunit 68903 "Mermaid Label"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        SpanTexts: List of [Text];
        SpanStyles: List of [Integer];
        SpanWidths: List of [Decimal];
        SpanLines: List of [Integer];
        LineWidths: List of [Decimal];
        // The spans of the line being built, before it is committed.
        CurTexts: List of [Text];
        CurStyles: List of [Integer];
        CurWidths: List of [Decimal];
        CurWidth: Decimal;
        // The spans of one source line, before wrapping.
        InTexts: List of [Text];
        InStyles: List of [Integer];
        LabelWidth: Decimal;
        LabelHeight: Decimal;
        FontSize: Decimal;
        LineHeightValue: Decimal;

    procedure Reset()
    begin
        Clear(SpanTexts);
        Clear(SpanStyles);
        Clear(SpanWidths);
        Clear(SpanLines);
        Clear(LineWidths);
        Clear(CurTexts);
        Clear(CurStyles);
        Clear(CurWidths);
        Clear(InTexts);
        Clear(InStyles);
        CurWidth := 0;
        LabelWidth := 0;
        LabelHeight := 0;
        FontSize := 0;
        LineHeightValue := 0;
    end;

    procedure GetWidth(): Decimal
    begin
        exit(LabelWidth);
    end;

    procedure GetHeight(): Decimal
    begin
        exit(LabelHeight);
    end;

    procedure GetSize(): Decimal
    begin
        exit(FontSize);
    end;

    procedure GetLineHeight(): Decimal
    begin
        exit(LineHeightValue);
    end;

    procedure LineCount(): Integer
    begin
        exit(LineWidths.Count());
    end;

    procedure IsEmpty(): Boolean
    begin
        exit(LineWidths.Count() = 0);
    end;

    /// <summary>The label's text with its lines joined by spaces.</summary>
    procedure PlainText(): Text
    var
        Builder: TextBuilder;
        I: Integer;
        Line: Integer;
    begin
        Line := 1;
        for I := 1 to SpanTexts.Count() do begin
            if SpanLines.Get(I) <> Line then begin
                Builder.Append(' ');
                Line := SpanLines.Get(I);
            end;
            Builder.Append(SpanTexts.Get(I));
        end;
        exit(Builder.ToText());
    end;

    // ---------------------------------------------------------------- layout

    procedure Layout(Raw: Text; Markdown: Boolean; Size: Decimal; MaxWidth: Decimal; BaseStyle: Integer)
    var
        Txt: Text;
        Source: Text;
        Part: Text;
        W: Decimal;
        I: Integer;
    begin
        Reset();
        if Raw = '' then
            exit;
        FontSize := Size;
        LineHeightValue := Round(Size * 1.5, 1);

        if not HasMarkup(Raw) then begin
            Txt := MText.TrimWs(Raw);
            W := MText.Width(Txt, Size, BaseStyle);
            Clear(InTexts);
            Clear(InStyles);
            InTexts.Add(Txt);
            InStyles.Add(BaseStyle);
            if (W <= MaxWidth) or not Txt.Contains(' ') then
                CommitInput()
            else
                Wrap(MaxWidth);
            Finish();
            exit;
        end;

        if Markdown then
            Source := MText.TrimWs(Dedent(Raw))
        else
            Source := MText.TrimWs(Raw);
        foreach Part in SplitBreaks(Source) do begin
            Clear(InTexts);
            Clear(InStyles);
            Inline(MText.TrimWs(Part), Markdown, BaseStyle);
            W := 0;
            for I := 1 to InTexts.Count() do
                W += MText.Width(InTexts.Get(I), Size, InStyles.Get(I));
            if W > MaxWidth then
                Wrap(MaxWidth)
            else
                CommitInput();
        end;
        Finish();
    end;

    local procedure HasMarkup(Raw: Text): Boolean
    begin
        exit(Raw.Contains('<') or Raw.Contains('\') or Raw.Contains(MText.LF()) or Raw.Contains('*') or Raw.Contains('_') or
             Raw.Contains('&') or Raw.Contains(MText.FromCode(64258)));
    end;

    local procedure Finish()
    var
        W: Decimal;
    begin
        LabelWidth := 0;
        foreach W in LineWidths do
            if W > LabelWidth then
                LabelWidth := W;
        LabelHeight := LineWidths.Count() * LineHeightValue;
    end;

    /// <summary>Adds the source line's spans, measured, as one line of the label.</summary>
    local procedure CommitInput()
    var
        I: Integer;
        Total: Decimal;
        W: Decimal;
        LineNo: Integer;
    begin
        LineNo := LineWidths.Count() + 1;
        for I := 1 to InTexts.Count() do begin
            W := MText.Width(InTexts.Get(I), FontSize, InStyles.Get(I));
            SpanTexts.Add(InTexts.Get(I));
            SpanStyles.Add(InStyles.Get(I));
            SpanWidths.Add(W);
            SpanLines.Add(LineNo);
            Total += W;
        end;
        LineWidths.Add(Total);
    end;

    local procedure Dedent(Raw: Text): Text
    var
        Lines: List of [Text];
        Line: Text;
        Builder: TextBuilder;
        MinIndent: Integer;
        Indent: Integer;
        I: Integer;
        Cut: Integer;
    begin
        Raw := Raw.Replace(MText.CR() + MText.LF(), MText.LF()).Replace(MText.CR(), MText.LF());
        Lines := Raw.Split(MText.LF());
        MinIndent := -1;
        foreach Line in Lines do
            if not MText.IsBlankText(Line) then begin
                Indent := StrLen(Line) - StrLen(MText.TrimStartWs(Line));
                if (MinIndent < 0) or (Indent < MinIndent) then
                    MinIndent := Indent;
            end;
        if MinIndent <= 0 then
            exit(Raw);
        for I := 1 to Lines.Count() do begin
            Line := Lines.Get(I);
            Cut := StrLen(Line) - StrLen(MText.TrimStartWs(Line));
            if Cut > MinIndent then
                Cut := MinIndent;
            if I > 1 then
                Builder.Append(MText.LF());
            Builder.Append(CopyStr(Line, Cut + 1));
        end;
        exit(Builder.ToText());
    end;

    /// <summary>Splits at &lt;br&gt; tags, literal \n and line breaks.</summary>
    local procedure SplitBreaks(Source: Text): List of [Text]
    var
        Parts: List of [Text];
        Builder: TextBuilder;
        I: Integer;
        J: Integer;
        C: Integer;
        Consumed: Boolean;
    begin
        I := 1;
        while I <= StrLen(Source) do begin
            C := MText.CharAt(Source, I);
            Consumed := false;
            if C = 10 then begin
                Parts.Add(Builder.ToText());
                Clear(Builder);
                I += 1;
                Consumed := true;
            end else
                if (C = 92) and (MText.CharAt(Source, I + 1) = 110) then begin
                    Parts.Add(Builder.ToText());
                    Clear(Builder);
                    I += 2;
                    Consumed := true;
                end else
                    if (C = 60) and (LowerCase(CopyStr(Source, I + 1, 2)) = 'br') then begin
                        J := I + 3;
                        while MText.IsSpace(MText.CharAt(Source, J)) do
                            J += 1;
                        if MText.CharAt(Source, J) = 47 then
                            J += 1;
                        if MText.CharAt(Source, J) = 62 then begin
                            Parts.Add(Builder.ToText());
                            Clear(Builder);
                            I := J + 1;
                            Consumed := true;
                        end;
                    end;
            if not Consumed then begin
                Builder.Append(CopyStr(Source, I, 1));
                I += 1;
            end;
        end;
        Parts.Add(Builder.ToText());
        exit(Parts);
    end;

    local procedure PushText(Value: Text; StyleValue: Integer)
    var
        Decoded: Text;
        Last: Integer;
    begin
        if Value = '' then
            exit;
        Decoded := MText.DecodeEntities(Value);
        Last := InTexts.Count();
        if Last > 0 then
            if InStyles.Get(Last) = StyleValue then begin
                InTexts.Set(Last, InTexts.Get(Last) + Decoded);
                exit;
            end;
        InTexts.Add(Decoded);
        InStyles.Add(StyleValue);
    end;

    /// <summary>Splits inline HTML and, for markdown labels, emphasis markers into styled spans.</summary>
    local procedure Inline(Source: Text; Markdown: Boolean; Base: Integer)
    var
        Pending: TextBuilder;
        StyleValue: Integer;
        Marked: Integer;
        I: Integer;
        N: Integer;
        C: Integer;
        TagName: Text;
        TagLen: Integer;
        Closing: Boolean;
        Bit: Integer;
        DoubleMark: Boolean;
        MarkLen: Integer;
        IsOpen: Boolean;
        Prev: Integer;
        Next: Integer;
        CanOpen: Boolean;
        CanClose: Boolean;
        Wordy: Boolean;
        Handled: Boolean;
        Marker: Text;
    begin
        StyleValue := Base;
        N := StrLen(Source);
        I := 1;
        while I <= N do begin
            C := MText.CharAt(Source, I);
            Handled := false;
            if C = 60 then begin
                if MatchTag(Source, I, TagName, TagLen, Closing) then begin
                    Bit := 0;
                    if (TagName = 'b') or (TagName = 'strong') then
                        Bit := MText.StyleBold()
                    else
                        if (TagName = 'i') or (TagName = 'em') then
                            Bit := MText.StyleItalic();
                    if Bit <> 0 then begin
                        PushText(Pending.ToText(), StyleValue);
                        Clear(Pending);
                        if Closing then begin
                            StyleValue := MText.RemoveStyle(StyleValue, Bit);
                            if MText.HasStyle(Base, Bit) then
                                StyleValue := MText.AddStyle(StyleValue, Bit);
                        end else
                            StyleValue := MText.AddStyle(StyleValue, Bit);
                    end;
                    I += TagLen;
                    Handled := true;
                end;
            end else
                if Markdown and ((C = 42) or (C = 95)) then begin
                    DoubleMark := MText.CharAt(Source, I + 1) = C;
                    if DoubleMark then begin
                        Bit := MText.StyleBold();
                        MarkLen := 2;
                    end else begin
                        Bit := MText.StyleItalic();
                        MarkLen := 1;
                    end;
                    Marker := CopyStr(Source, I, MarkLen);
                    IsOpen := not MText.HasStyle(Marked, Bit);
                    Prev := 32;
                    if I > 1 then
                        Prev := MText.CharAt(Source, I - 1);
                    Next := 32;
                    if I + MarkLen <= N then
                        Next := MText.CharAt(Source, I + MarkLen);
                    CanOpen := IsOpen and not MText.IsSpace(Next) and (MText.IndexOfFrom(Source, Marker, I + MarkLen) > 0);
                    CanClose := (not IsOpen) and not MText.IsSpace(Prev);
                    Wordy := (C = 95) and MText.IsWord(Prev) and MText.IsWord(Next);
                    if (CanOpen or CanClose) and not Wordy then begin
                        PushText(Pending.ToText(), StyleValue);
                        Clear(Pending);
                        if CanOpen then begin
                            Marked := MText.AddStyle(Marked, Bit);
                            StyleValue := MText.AddStyle(StyleValue, Bit);
                        end else begin
                            Marked := MText.RemoveStyle(Marked, Bit);
                            StyleValue := MText.RemoveStyle(StyleValue, Bit);
                            if MText.HasStyle(Base, Bit) then
                                StyleValue := MText.AddStyle(StyleValue, Bit);
                        end;
                        I += MarkLen;
                        Handled := true;
                    end;
                end;
            if not Handled then begin
                Pending.Append(CopyStr(Source, I, 1));
                I += 1;
            end;
        end;
        PushText(Pending.ToText(), StyleValue);
    end;

    /// <summary>Matches &lt;/?name( attrs)?/?&gt; at position I.</summary>
    local procedure MatchTag(Source: Text; I: Integer; var TagName: Text; var TagLen: Integer; var Closing: Boolean): Boolean
    var
        J: Integer;
        NameStart: Integer;
        C: Integer;
    begin
        J := I + 1;
        Closing := MText.CharAt(Source, J) = 47;
        if Closing then
            J += 1;
        if not MText.IsLetter(MText.CharAt(Source, J)) then
            exit(false);
        NameStart := J;
        J += 1;
        while MText.IsWord(MText.CharAt(Source, J)) or (MText.CharAt(Source, J) = 45) do
            J += 1;
        TagName := LowerCase(MText.Substr(Source, NameStart, J));
        if MText.IsSpace(MText.CharAt(Source, J)) then begin
            J += 1;
            C := MText.CharAt(Source, J);
            while (C <> -1) and (C <> 60) and (C <> 62) do begin
                J += 1;
                C := MText.CharAt(Source, J);
            end;
        end;
        if MText.CharAt(Source, J) = 47 then
            J += 1;
        if MText.CharAt(Source, J) <> 62 then
            exit(false);
        TagLen := J - I + 1;
        exit(true);
    end;

    /// <summary>Pieces of text as /\s*\S+\s*|\s+/g finds them.</summary>
    local procedure Pieces(Value: Text): List of [Text]
    var
        Result: List of [Text];
        I: Integer;
        StartPos: Integer;
        N: Integer;
    begin
        N := StrLen(Value);
        I := 1;
        while I <= N do begin
            StartPos := I;
            while (I <= N) and MText.IsSpace(MText.CharAt(Value, I)) do
                I += 1;
            if I > N then
                Result.Add(MText.Substr(Value, StartPos, I))
            else begin
                while (I <= N) and not MText.IsSpace(MText.CharAt(Value, I)) do
                    I += 1;
                while (I <= N) and MText.IsSpace(MText.CharAt(Value, I)) do
                    I += 1;
                Result.Add(MText.Substr(Value, StartPos, I));
            end;
        end;
        exit(Result);
    end;

    local procedure CommitCurrent()
    var
        Last: Integer;
        Trimmed: Text;
        W: Decimal;
        I: Integer;
        LineNo: Integer;
    begin
        Last := CurTexts.Count();
        if Last > 0 then begin
            Trimmed := MText.TrimEndWs(CurTexts.Get(Last));
            if Trimmed <> CurTexts.Get(Last) then begin
                W := MText.Width(Trimmed, FontSize, CurStyles.Get(Last));
                CurWidth += W - CurWidths.Get(Last);
                CurTexts.Set(Last, Trimmed);
                CurWidths.Set(Last, W);
            end;
        end;
        LineNo := LineWidths.Count() + 1;
        for I := 1 to CurTexts.Count() do begin
            SpanTexts.Add(CurTexts.Get(I));
            SpanStyles.Add(CurStyles.Get(I));
            SpanWidths.Add(CurWidths.Get(I));
            SpanLines.Add(LineNo);
        end;
        LineWidths.Add(CurWidth);
        Clear(CurTexts);
        Clear(CurStyles);
        Clear(CurWidths);
        CurWidth := 0;
    end;

    /// <summary>Wraps the source line's spans at word gaps so that no line is wider than MaxWidth.</summary>
    local procedure Wrap(MaxWidth: Decimal)
    var
        S: Integer;
        Piece: Text;
        Part: Text;
        StyleValue: Integer;
        Last: Integer;
        W: Decimal;
        I: Integer;
        Merged: Boolean;
    begin
        Clear(CurTexts);
        Clear(CurStyles);
        Clear(CurWidths);
        CurWidth := 0;
        for S := 1 to InTexts.Count() do begin
            StyleValue := InStyles.Get(S);
            foreach Piece in Pieces(InTexts.Get(S)) do begin
                Part := Piece;
                if (CurWidth > 0) and (CurWidth + MText.Width(MText.TrimEndWs(Part), FontSize, StyleValue) > MaxWidth) then begin
                    CommitCurrent();
                    Part := MText.TrimStartWs(Part);
                end;
                Last := CurTexts.Count();
                Merged := false;
                if Last > 0 then
                    if CurStyles.Get(Last) = StyleValue then begin
                        CurTexts.Set(Last, CurTexts.Get(Last) + Part);
                        CurWidths.Set(Last, MText.Width(CurTexts.Get(Last), FontSize, StyleValue));
                        CurWidth := 0;
                        for I := 1 to CurWidths.Count() do
                            CurWidth += CurWidths.Get(I);
                        Merged := true;
                    end;
                if not Merged then begin
                    W := MText.Width(Part, FontSize, StyleValue);
                    CurTexts.Add(Part);
                    CurStyles.Add(StyleValue);
                    CurWidths.Add(W);
                    CurWidth += W;
                end;
            end;
        end;
        if (CurTexts.Count() > 0) or (LineWidths.Count() = 0) then
            CommitCurrent();
    end;

    // ---------------------------------------------------------------- SVG

    /// <summary>The emphasis every span of the label has, written once on the text element.</summary>
    local procedure SharedStyle(): Integer
    var
        Shared: Integer;
        Any: Boolean;
        I: Integer;
    begin
        Shared := MText.StyleBold() + MText.StyleItalic();
        for I := 1 to SpanTexts.Count() do
            if SpanTexts.Get(I) <> '' then begin
                Shared := MText.CommonStyle(Shared, SpanStyles.Get(I));
                Any := true;
            end;
        if not Any then
            exit(0);
        exit(Shared);
    end;

    procedure SpanStyleAttr(StyleValue: Integer): Text
    var
        Result: Text;
    begin
        if MText.HasStyle(StyleValue, MText.StyleBold()) then
            Result += ' font-weight="var(--_w)"';
        if MText.HasStyle(StyleValue, MText.StyleItalic()) then
            Result += ' font-style="italic"';
        exit(Result);
    end;

    local procedure TextStyleAttr(Attrs: Text; Shared: Integer): Text
    begin
        if MText.HasStyle(Shared, MText.StyleBold()) and not Attrs.Contains(' font-weight="') then
            Attrs += ' font-weight="var(--_w)"';
        if MText.HasStyle(Shared, MText.StyleItalic()) and not Attrs.Contains(' font-style="') then
            Attrs += ' font-style="italic"';
        exit(Attrs);
    end;

    local procedure SpanOnLine(S: Integer; LineNo: Integer): Boolean
    begin
        if S > SpanTexts.Count() then
            exit(false);
        exit(SpanLines.Get(S) = LineNo);
    end;

    /// <summary>Writes the label as SVG text centred on (Cx, Cy).</summary>
    procedure ToSvg(Cx: Decimal; Cy: Decimal; Attrs: Text): Text
    var
        Body: TextBuilder;
        Shift: Decimal;
        Y: Decimal;
        Shared: Integer;
        LineNo: Integer;
        S: Integer;
        First: Boolean;
        Pos: Text;
    begin
        if LineWidths.Count() = 0 then
            exit('');
        Shift := FontSize * 0.35;
        Y := Cy - LabelHeight / 2 + LineHeightValue / 2 + Shift;
        if (LineWidths.Count() = 1) and (SpanTexts.Count() = 1) then
            if SpanStyles.Get(1) = 0 then
                exit('<text' + Attrs + ' x="' + MText.Num(Cx) + '" y="' + MText.Num(Y) + '" text-anchor="middle">' + MText.Esc(SpanTexts.Get(1)) + '</text>');

        Shared := SharedStyle();
        Attrs := TextStyleAttr(Attrs, Shared);
        S := 1;
        for LineNo := 1 to LineWidths.Count() do begin
            First := true;
            while SpanOnLine(S, LineNo) do begin
                Pos := '';
                if First then
                    Pos := ' x="' + MText.Num(Cx) + '" y="' + MText.Num(Y) + '"';
                Body.Append('<tspan' + Pos + SpanStyleAttr(SpanStyles.Get(S) - MText.CommonStyle(SpanStyles.Get(S), Shared)) + '>' + MText.Esc(SpanTexts.Get(S)) + '</tspan>');
                First := false;
                S += 1;
            end;
            if First then
                Body.Append('<tspan x="' + MText.Num(Cx) + '" y="' + MText.Num(Y) + '"> </tspan>');
            Y += LineHeightValue;
        end;
        exit('<text' + Attrs + ' text-anchor="middle" xml:space="preserve">' + Body.ToText() + '</text>');
    end;
}
