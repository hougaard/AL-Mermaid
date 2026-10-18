/// <summary>
/// Port of pele's diagrams/pie: parser.ts, model.ts and render.ts.
/// </summary>
codeunit 68910 "Mermaid Pie Chart"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Builder: Codeunit "Mermaid SVG Builder";
        Math: Codeunit Math;
        Labels: List of [Text];
        Values: List of [Decimal];
        PieTitle: Text;
        AccTitle: Text;
        AccDescr: Text;
        ShowData: Boolean;
        Src: Text;
        Pos: Integer;
        PieRadius: Decimal;
        Swatch: Decimal;
        RowH: Decimal;
        Gap: Decimal;
        Outside: Decimal;

    // ---------------------------------------------------------------- parsing

    procedure Parse(Source: Text; FrontTitle: Text)
    begin
        Clear(Labels);
        Clear(Values);
        PieTitle := '';
        AccTitle := '';
        AccDescr := '';
        ShowData := false;
        Src := Source;
        Pos := 1;
        SkipSpaceAndLines();
        if not Keyword('pie') then
            MText.SyntaxError('pie', Src, Pos, 'Expecting ''pie''', false);
        SkipBlanks();
        if Keyword('showData') then
            ShowData := true;
        while Pos <= StrLen(Src) do begin
            SkipBlanks();
            if Pos > StrLen(Src) then
                break;
            if MText.CharAt(Src, Pos) = 10 then
                Pos += 1
            else
                Statement();
        end;
        if PieTitle = '' then
            PieTitle := FrontTitle;
    end;

    local procedure Statement()
    var
        StartPos: Integer;
        LabelText: Text;
        Value: Decimal;
        Quote: Integer;
        Close: Integer;
        NumText: Text;
    begin
        StartPos := Pos;
        if Word('accTitle') then begin
            SkipBlanks();
            if MText.CharAt(Src, Pos) <> 58 then
                MText.SyntaxError('pie', Src, Pos, 'Expecting '':''', false);
            Pos += 1;
            AccTitle := MText.TrimStartWs(RestOfLine());
            EndOfLine();
            exit;
        end;
        if Word('accDescr') then begin
            SkipBlanks();
            if MText.CharAt(Src, Pos) = 123 then begin
                Close := MText.IndexOfFrom(Src, '}', Pos);
                if Close = 0 then
                    MText.SyntaxError('pie', Src, Pos, 'Expecting ''}''', false);
                AccDescr := MultiLineDescr(MText.Substr(Src, Pos + 1, Close));
                Pos := Close + 1;
            end else begin
                if MText.CharAt(Src, Pos) <> 58 then
                    MText.SyntaxError('pie', Src, Pos, 'Expecting '':''', false);
                Pos += 1;
                AccDescr := MText.TrimWs(RestOfLine());
            end;
            EndOfLine();
            exit;
        end;
        if Word('title') then begin
            PieTitle := MText.TrimWs(RestOfLine());
            EndOfLine();
            exit;
        end;
        Quote := MText.CharAt(Src, Pos);
        if (Quote = 34) or (Quote = 39) then begin
            Close := MText.IndexOfFrom(Src, MText.FromCode(Quote), Pos + 1);
            if Close = 0 then
                MText.SyntaxError('pie', Src, Pos, 'Expecting a closing quote', false);
            LabelText := MText.Substr(Src, Pos + 1, Close);
            Pos := Close + 1;
            SkipBlanks();
            if MText.CharAt(Src, Pos) <> 58 then
                MText.SyntaxError('pie', Src, Pos, 'Expecting '':''', false);
            Pos += 1;
            SkipBlanks();
            NumText := ReadNumber();
            if not Evaluate(Value, NumText, 9) then
                MText.SyntaxError('pie', Src, Pos, 'Expecting a number', false);
            if Value < 0 then
                MText.Fail('"' + LabelText + '" has invalid value: ' + NumText + '. Negative values are not allowed in pie charts. All slice values must be >= 0.');
            if not Labels.Contains(LabelText) then begin
                Labels.Add(LabelText);
                Values.Add(Value);
            end;
            EndOfLine();
            exit;
        end;
        Pos := StartPos;
        MText.SyntaxError('pie', Src, Pos, 'Expecting a section, a title, or a line break', false);
    end;

    local procedure MultiLineDescr(Value: Text): Text
    var
        Lines: List of [Text];
        Line: Text;
        Result: Text;
        First: Boolean;
    begin
        Lines := MText.TrimWs(Value).Split(MText.LF());
        First := true;
        foreach Line in Lines do begin
            if not First then
                Result += MText.LF();
            if First then
                Result += Line
            else
                Result += MText.TrimStartWs(Line);
            First := false;
        end;
        exit(Result);
    end;

    local procedure ReadNumber(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        if MText.CharAt(Src, Pos) = 45 then
            Pos += 1;
        while MText.IsDigit(MText.CharAt(Src, Pos)) do
            Pos += 1;
        if (MText.CharAt(Src, Pos) = 46) and MText.IsDigit(MText.CharAt(Src, Pos + 1)) then begin
            Pos += 1;
            while MText.IsDigit(MText.CharAt(Src, Pos)) do
                Pos += 1;
        end;
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    local procedure RestOfLine(): Text
    var
        StartPos: Integer;
    begin
        StartPos := Pos;
        while (Pos <= StrLen(Src)) and (MText.CharAt(Src, Pos) <> 10) do
            Pos += 1;
        exit(MText.Substr(Src, StartPos, Pos));
    end;

    local procedure EndOfLine()
    begin
        SkipBlanks();
        if Pos > StrLen(Src) then
            exit;
        if MText.CharAt(Src, Pos) <> 10 then
            MText.SyntaxError('pie', Src, Pos, 'Expecting a line break or the end of input', false);
        while MText.CharAt(Src, Pos) = 10 do
            Pos += 1;
    end;

    local procedure SkipBlanks()
    begin
        while MText.IsSpace(MText.CharAt(Src, Pos)) and (MText.CharAt(Src, Pos) <> 10) do
            Pos += 1;
    end;

    local procedure SkipSpaceAndLines()
    begin
        while MText.IsSpace(MText.CharAt(Src, Pos)) do
            Pos += 1;
    end;

    local procedure Keyword(Name: Text): Boolean
    begin
        if not MText.StartsWithAt(Src, Name, Pos) then
            exit(false);
        if MText.IsWord(MText.CharAt(Src, Pos + StrLen(Name))) then
            exit(false);
        Pos += StrLen(Name);
        exit(true);
    end;

    local procedure Word(Name: Text): Boolean
    begin
        exit(Keyword(Name));
    end;

    // ---------------------------------------------------------------- rendering

    local procedure Init()
    begin
        PieRadius := 120;
        Swatch := 12;
        RowH := 26;
        Gap := 32;
        Outside := 28;
    end;

    local procedure Point(Angle: Decimal; R: Decimal): Text
    begin
        exit(MText.Num(Math.Sin(Angle) * R) + ',' + MText.Num(-Math.Cos(Angle) * R));
    end;

    local procedure Ring(R: Decimal; Sweep: Integer): Text
    begin
        exit('M0,' + MText.Num(-R) + 'A' + MText.Num(R) + ',' + MText.Num(R) + ' 0 1 ' + MText.IntText(Sweep) + ' 0,' + MText.Num(R) +
             'A' + MText.Num(R) + ',' + MText.Num(R) + ' 0 1 ' + MText.IntText(Sweep) + ' 0,' + MText.Num(-R) + 'Z');
    end;

    local procedure Slice(StartAngle: Decimal; EndAngle: Decimal; OuterR: Decimal; InnerR: Decimal): Text
    var
        Large: Text;
    begin
        if EndAngle - StartAngle >= Math.Pi() * 2 - 0.000000001 then begin
            if InnerR > 0 then
                exit(Ring(OuterR, 1) + Ring(InnerR, 0));
            exit(Ring(OuterR, 1));
        end;
        Large := '0';
        if EndAngle - StartAngle > Math.Pi() then
            Large := '1';
        if InnerR <= 0 then
            exit('M0,0L' + Point(StartAngle, OuterR) + 'A' + MText.Num(OuterR) + ',' + MText.Num(OuterR) + ' 0 ' + Large + ' 1 ' + Point(EndAngle, OuterR) + 'Z');
        exit('M' + Point(StartAngle, OuterR) + 'A' + MText.Num(OuterR) + ',' + MText.Num(OuterR) + ' 0 ' + Large + ' 1 ' + Point(EndAngle, OuterR) +
             'L' + Point(EndAngle, InnerR) + 'A' + MText.Num(InnerR) + ',' + MText.Num(InnerR) + ' 0 ' + Large + ' 0 ' + Point(StartAngle, InnerR) + 'Z');
    end;

    local procedure Percent(Share: Decimal): Text
    begin
        exit(MText.IntText(Round(Share * 100, 1)) + '%');
    end;

    procedure Render(var Config: Dictionary of [Text, Text]): Text
    var
        TitleLbl: Codeunit "Mermaid Label";
        Lbl: Codeunit "Mermaid Label";
        Shares: List of [Decimal];
        Narrow: List of [Boolean];
        LegendWidths: List of [Decimal];
        PlacedX: List of [Decimal];
        PlacedY: List of [Decimal];
        PlacedW: List of [Decimal];
        SlicesOut: TextBuilder;
        LabelsOut: TextBuilder;
        OutsideOut: TextBuilder;
        LegendOut: TextBuilder;
        Size: Decimal;
        Small: Decimal;
        Pad: Decimal;
        TextPosition: Decimal;
        Hole: Decimal;
        InnerR: Decimal;
        Placed: Text;
        LegendPosition: Text;
        Side: Text;
        Stacked: Boolean;
        Sum: Decimal;
        Share: Decimal;
        Chord: Decimal;
        LegendWidth: Decimal;
        LegendHeight: Decimal;
        TitleHeight: Decimal;
        Margin: Decimal;
        Diameter: Decimal;
        Width: Decimal;
        Height: Decimal;
        Cx: Decimal;
        Cy: Decimal;
        BodyTop: Decimal;
        Angle: Decimal;
        EndAngle: Decimal;
        Mid: Decimal;
        Rim: Decimal;
        At: Decimal;
        X: Decimal;
        Y: Decimal;
        Lx: Decimal;
        Ly: Decimal;
        W: Decimal;
        R: Decimal;
        TotalWidth: Integer;
        TotalHeight: Integer;
        I: Integer;
        StepNo: Integer;
        Pct: Text;
        Content: Text;
        LegendText: Text;
        AnyNarrow: Boolean;
    begin
        LegendWidth := 0;
        Init();
        Size := MText.FontSize();
        Small := Round(Size * 0.875, 1);
        Pad := 8;
        if not MText.ConfigNumber(Config, 'pie.textPosition', TextPosition) then
            TextPosition := 0.75;
        if (TextPosition < 0) or (TextPosition > 1) then
            TextPosition := 0.75;
        InnerR := 0;
        if MText.ConfigNumber(Config, 'pie.donutHole', Hole) then
            if (Hole > 0) and (Hole <= 0.9) then
                InnerR := Hole * PieRadius;
        Placed := MText.ConfigText(Config, 'pie.legendPosition', 'right');
        LegendPosition := Placed;

        for I := 1 to Values.Count() do
            Sum += Values.Get(I);

        for I := 1 to Labels.Count() do begin
            LegendText := Labels.Get(I);
            if ShowData then
                LegendText := LegendText + ' [' + MText.DecText(Values.Get(I)) + ']';
            Lbl.Layout(LegendText, false, Small, 4000, 0);
            LegendWidths.Add(Lbl.GetWidth());
            if Lbl.GetWidth() > LegendWidth then
                LegendWidth := Lbl.GetWidth();
        end;
        if Labels.Count() > 0 then
            LegendWidth += Swatch + 8;
        LegendHeight := Labels.Count() * RowH;

        TitleLbl.Layout(PieTitle, false, Size, 4000, MText.StyleBold());
        if TitleLbl.GetHeight() > 0 then
            TitleHeight := TitleLbl.GetHeight() + 16;

        // A slice too thin for its percentage gets the label outside the rim, which needs a margin.
        for I := 1 to Values.Count() do begin
            Share := 0;
            if Sum > 0 then
                Share := Values.Get(I) / Sum;
            if (Share * 100 < 1) or (Round(Share * 100, 1) = 0) then
                Share := 0;
            Shares.Add(Share);
            if (Share = 0) or (Share >= 0.5) then
                Narrow.Add(false)
            else begin
                Chord := 2 * PieRadius * TextPosition * Math.Sin(Share * Math.Pi());
                Narrow.Add(Chord < MText.Width(Percent(Share), Small, 0) + 6);
                if Narrow.Get(I) then
                    AnyNarrow := true;
            end;
        end;
        if AnyNarrow then
            Margin := Outside;

        Side := '';
        if LegendPosition in ['left', 'right', 'center'] then
            Side := LegendPosition;
        Stacked := LegendPosition in ['top', 'bottom'];
        Diameter := (PieRadius + Margin) * 2;
        Width := Diameter;
        Height := Diameter;
        if (Side = 'left') or (Side = 'right') then begin
            if LegendWidth > 0 then
                Width += Gap + LegendWidth;
            Height := MText.MaxDec(Height, LegendHeight);
        end else
            if Stacked then begin
                Width := MText.MaxDec(Width, LegendWidth);
                if LegendHeight > 0 then
                    Height += 20 + LegendHeight;
            end;
        Width := MText.MaxDec(Width, TitleLbl.GetWidth());

        case Side of
            'left':
                Cx := Pad + LegendWidth + Gap + Diameter / 2;
            'right':
                Cx := Pad + Diameter / 2;
            else
                Cx := Pad + Width / 2;
        end;
        BodyTop := Pad + TitleHeight;
        if LegendPosition = 'top' then
            Cy := BodyTop + LegendHeight + 20 + Diameter / 2
        else
            if Stacked then
                Cy := BodyTop + Diameter / 2
            else
                Cy := BodyTop + Height / 2;

        Angle := 0;
        Rim := PieRadius + Outside / 2;
        for I := 1 to Labels.Count() do begin
            Share := Shares.Get(I);
            if Share > 0 then begin
                EndAngle := Angle + Share * Math.Pi() * 2;
                SlicesOut.Append('<path class="pele-slice" data-id="' + MText.EscText(Labels.Get(I)) + '" d="' + Slice(Angle, EndAngle, PieRadius, InnerR) + '" fill="' + Builder.SeriesColor(I - 1) + '"/>');
                Mid := (Angle + EndAngle) / 2;
                Pct := Percent(Share);
                if Narrow.Get(I) then begin
                    W := MText.Width(Pct, Small, 0);
                    At := Mid;
                    StepNo := 0;
                    while (StepNo < 360) and not IsClear(PlacedX, PlacedY, PlacedW, Math.Sin(At) * Rim, -Math.Cos(At) * Rim, W, Small) do begin
                        At += 2 / Rim;
                        StepNo += 1;
                    end;
                    X := Math.Sin(At) * Rim;
                    Y := -Math.Cos(At) * Rim;
                    PlacedX.Add(X);
                    PlacedY.Add(Y);
                    PlacedW.Add(W);
                    OutsideOut.Append('<text x="' + MText.Num(X) + '" y="' + MText.Num(Y + Small * 0.35) + '">' + Pct + '</text>');
                end else begin
                    R := PieRadius * TextPosition;
                    LabelsOut.Append('<text x="' + MText.Num(Math.Sin(Mid) * R) + '" y="' + MText.Num(-Math.Cos(Mid) * R + Small * 0.35) + '">' + Pct + '</text>');
                end;
                Angle := EndAngle;
            end;
        end;
        if SlicesOut.Length() = 0 then
            SlicesOut.Append('<circle class="pele-slice" r="' + MText.Num(PieRadius) + '" fill="none" stroke="var(--_b)"/>');

        case Side of
            'right':
                begin
                    Lx := Cx + Diameter / 2 + Gap;
                    Ly := BodyTop + (Height - LegendHeight) / 2;
                end;
            'left':
                begin
                    Lx := Pad;
                    Ly := BodyTop + (Height - LegendHeight) / 2;
                end;
            'center':
                begin
                    Lx := Cx - LegendWidth / 2;
                    Ly := Cy - LegendHeight / 2;
                end;
            else begin
                Lx := Pad + (Width - LegendWidth) / 2;
                if LegendPosition = 'top' then
                    Ly := BodyTop
                else
                    Ly := BodyTop + Diameter + 20;
            end;
        end;
        for I := 1 to Labels.Count() do begin
            LegendText := Labels.Get(I);
            if ShowData then
                LegendText := LegendText + ' [' + MText.DecText(Values.Get(I)) + ']';
            Lbl.Layout(LegendText, false, Small, 4000, 0);
            Y := Ly + (I - 1) * RowH + RowH / 2;
            LegendOut.Append('<g class="pele-legend-item" data-id="' + MText.EscText(Labels.Get(I)) + '">' +
                             '<rect x="' + MText.Num(Lx) + '" y="' + MText.Num(Y - Swatch / 2) + '" width="' + MText.Num(Swatch) + '" height="' + MText.Num(Swatch) + '" rx="2" fill="' + Builder.SeriesColor(I - 1) + '"/>' +
                             Lbl.ToSvg(Lx + Swatch + 8 + Lbl.GetWidth() / 2, Y, '') + '</g>');
        end;

        TotalWidth := MText.Ceil(Width + 2 * Pad);
        TotalHeight := MText.Ceil(Height + TitleHeight + 2 * Pad);
        Content := Builder.TitleSvg(TitleLbl, TotalWidth / 2, Pad + TitleLbl.GetHeight() / 2) +
                   '<g class="pele-slices" transform="translate(' + Builder.P(Cx, Cy) + ')" stroke="var(--_bg)" stroke-width="1" stroke-linejoin="round">' + SlicesOut.ToText() + '</g>';
        if LabelsOut.Length() > 0 then
            Content += '<g class="pele-slice-labels" transform="translate(' + Builder.P(Cx, Cy) + ')" font-size="' + MText.Num(Small) + '" text-anchor="middle" fill="var(--_bg)">' + LabelsOut.ToText() + '</g>';
        if OutsideOut.Length() > 0 then
            Content += '<g class="pele-slice-labels" transform="translate(' + Builder.P(Cx, Cy) + ')" font-size="' + MText.Num(Small) + '" text-anchor="middle">' + OutsideOut.ToText() + '</g>';
        if LegendOut.Length() > 0 then
            Content += '<g class="pele-legend" font-size="' + MText.Num(Small) + '">' + LegendOut.ToText() + '</g>';
        exit(Builder.Document('pie', TotalWidth, TotalHeight, Size, AccTitle, AccDescr, Content));
    end;

    local procedure IsClear(var PlacedX: List of [Decimal]; var PlacedY: List of [Decimal]; var PlacedW: List of [Decimal]; X: Decimal; Y: Decimal; W: Decimal; Small: Decimal): Boolean
    var
        I: Integer;
    begin
        for I := 1 to PlacedX.Count() do
            if (Abs(X - PlacedX.Get(I)) < (W + PlacedW.Get(I)) / 2 + 2) and (Abs(Y - PlacedY.Get(I)) < Small + 2) then
                exit(false);
        exit(true);
    end;
}
