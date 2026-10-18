/// <summary>
/// Port of pele's svg/root.ts, svg/theme.ts, svg/title.ts and svg/edges.ts: the SVG document with its
/// CSS variable theme, author styles, markers, edge routes with curves, edge labels and self-loops.
/// </summary>
codeunit 68904 "Mermaid SVG Builder"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        ArrowLen: Decimal;
        LeadLen: Decimal;
        CornerLen: Decimal;
        HandleRatio: Decimal;
        Initialized: Boolean;

    local procedure Init()
    begin
        if Initialized then
            exit;
        ArrowLen := 8;
        LeadLen := 6;
        CornerLen := 12;
        HandleRatio := 0.62;
        Initialized := true;
    end;

    // ---------------------------------------------------------------- theme

    procedure Radius(): Text
    begin
        exit('var(--pele-radius,4px)');
    end;

    procedure Critical(): Text
    begin
        exit('var(--pele-critical,#e45756)');
    end;

    /// <summary>Private aliases set once on the root element, so each use is short and the public --pele-* tokens keep their fallbacks.</summary>
    procedure RootStyle(): Text
    begin
        exit('--_bg:var(--pele-bg,#fff);--_fg:var(--pele-fg,#1f1f1f);--_m:var(--pele-muted,#6e6e6e);' +
             '--_l:var(--pele-line,#1f1f1f);--_s:var(--pele-surface,#f3f3f3);--_a:var(--pele-surface-alt,#e6e6e6);' +
             '--_b:var(--pele-border,#8a8a8a);--_c:var(--pele-accent,#5b7bd5);color:var(--_fg)');
    end;

    procedure FontStyle(Size: Decimal; Family: Text): Text
    begin
        if not IsFamilyList(Family) then
            Family := 'sans-serif';
        exit(';--_fm:var(--pele-font-mono,monospace);font:' + MText.Num(Size) + 'px sans-serif;' +
             'letter-spacing:normal;word-spacing:normal;text-transform:none;direction:ltr;' +
             'font-family:var(--pele-font,' + Family + ')');
    end;

    /// <summary>A list of font names, and nothing that could end the declaration it is put in.</summary>
    local procedure IsFamilyList(Family: Text): Boolean
    var
        I: Integer;
        C: Integer;
    begin
        if MText.TrimWs(Family) = '' then
            exit(false);
        for I := 1 to StrLen(Family) do begin
            C := Family[I];
            if (C = 92) or (C = 60) or (C = 62) or (C = 123) or (C = 125) or (C = 40) or (C = 41) or (C = 59) or (C = 58) or (C = 64) or (C = 10) then
                exit(false);
        end;
        exit(true);
    end;

    /// <summary>Colour for the nth data series in a chart, cycling through eight tokens.</summary>
    procedure SeriesColor(Index: Integer): Text
    var
        K: Integer;
        Colors: List of [Text];
    begin
        Colors.Add('#4c78a8');
        Colors.Add('#f58518');
        Colors.Add('#54a24b');
        Colors.Add('#e45756');
        Colors.Add('#72b7b2');
        Colors.Add('#eeca3b');
        Colors.Add('#b279a2');
        Colors.Add('#9d755d');
        K := ((Index mod 8) + 8) mod 8;
        exit('var(--pele-series-' + MText.IntText(K + 1) + ',' + Colors.Get(K + 1) + ')');
    end;

    procedure ClassNames(Raw: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        C: Integer;
        Gap: Boolean;
        Cleaned: Text;
    begin
        for I := 1 to StrLen(Raw) do begin
            C := Raw[I];
            if MText.IsWord(C) or (C = 45) then begin
                if Gap then
                    Builder.Append(' ');
                Gap := false;
                Builder.Append(CopyStr(Raw, I, 1));
            end else
                Gap := true;
        end;
        Cleaned := MText.TrimWs(Builder.ToText());
        if Cleaned = '' then
            exit('');
        exit(' ' + Cleaned);
    end;

    // ---------------------------------------------------------------- author styles

    local procedure IsShapeProp(Prop: Text): Boolean
    begin
        exit(Prop in ['fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-dasharray', 'stroke-dashoffset',
                      'stroke-linecap', 'stroke-linejoin', 'stroke-opacity', 'opacity', 'rx', 'ry']);
    end;

    local procedure IsTextProp(Prop: Text): Boolean
    begin
        exit(Prop in ['color', 'font-size', 'font-family', 'font-weight', 'font-style', 'text-decoration', 'letter-spacing',
                      'word-spacing', 'opacity']);
    end;

    local procedure IsUnsafe(Value: Text): Boolean
    var
        Lower: Text;
    begin
        Lower := LowerCase(Value);
        if Lower.Contains('javascript:') or Lower.Contains('@import') or Lower.Contains('image-set') or Lower.Contains('/*') then
            exit(true);
        if Lower.Contains('<') or Lower.Contains('>') or Lower.Contains('{') or Lower.Contains('}') or Lower.Contains(';') or Lower.Contains('\') then
            exit(true);
        if CallsFunction(Lower, 'url') or CallsFunction(Lower, 'expression') then
            exit(true);
        exit(false);
    end;

    local procedure CallsFunction(Lower: Text; Name: Text): Boolean
    var
        Pos: Integer;
        J: Integer;
    begin
        Pos := StrPos(Lower, Name);
        while Pos > 0 do begin
            J := Pos + StrLen(Name);
            while MText.IsSpace(MText.CharAt(Lower, J)) do
                J += 1;
            if MText.CharAt(Lower, J) = 40 then
                exit(true);
            Pos := MText.IndexOfFrom(Lower, Name, Pos + 1);
        end;
        exit(false);
    end;

    local procedure PutOrdered(var Keys: List of [Text]; var Values: Dictionary of [Text, Text]; KeyName: Text; Value: Text)
    begin
        if Values.ContainsKey(KeyName) then
            Values.Set(KeyName, Value)
        else begin
            Values.Add(KeyName, Value);
            Keys.Add(KeyName);
        end;
    end;

    /// <summary>
    /// Splits Mermaid style declarations into what applies to a shape, to a line, and to text (pele's resolveStyle).
    /// The attribute results are ready to append to an element, with a leading space, or empty.
    /// </summary>
    procedure ResolveStyle(Declarations: List of [Text]; var ShapeAttr: Text; var LineAttr: Text; var TextAttr: Text; var Stroke: Text; var IsBold: Boolean; var IsItalic: Boolean; var StyleFontSize: Decimal)
    var
        ShapeKeys: List of [Text];
        ShapeValues: Dictionary of [Text, Text];
        TextKeys: List of [Text];
        TextValues: Dictionary of [Text, Text];
        Decl: Text;
        Prop: Text;
        Value: Text;
        At: Integer;
        ShapeCss: Text;
        LineCss: Text;
        TextCss: Text;
        KeyName: Text;
        Weight: Text;
        Size: Text;
        WeightNo: Decimal;
        Px: Decimal;
    begin
        ShapeAttr := '';
        LineAttr := '';
        TextAttr := '';
        Stroke := '';
        IsBold := false;
        IsItalic := false;
        StyleFontSize := 0;
        foreach Decl in Declarations do begin
            At := StrPos(Decl, ':');
            if At > 1 then begin
                Prop := LowerCase(MText.TrimWs(CopyStr(Decl, 1, At - 1)));
                Value := MText.TrimWs(RemoveImportant(CopyStr(Decl, At + 1)));
                if (Value <> '') and not IsUnsafe(Value) then begin
                    if IsShapeProp(Prop) then
                        PutOrdered(ShapeKeys, ShapeValues, Prop, Value);
                    if IsTextProp(Prop) then
                        if Prop = 'color' then
                            PutOrdered(TextKeys, TextValues, 'fill', Value)
                        else
                            PutOrdered(TextKeys, TextValues, Prop, Value);
                end;
            end;
        end;
        foreach KeyName in ShapeKeys do begin
            ShapeCss += KeyName + ':' + ShapeValues.Get(KeyName) + ';';
            if (KeyName <> 'fill') and (KeyName <> 'fill-opacity') then
                LineCss += KeyName + ':' + ShapeValues.Get(KeyName) + ';';
        end;
        foreach KeyName in TextKeys do
            TextCss += KeyName + ':' + TextValues.Get(KeyName) + ';';
        if ShapeCss <> '' then
            ShapeAttr := ' style="' + MText.Esc(ShapeCss) + '"';
        if LineCss <> '' then
            LineAttr := ' style="' + MText.Esc(LineCss) + '"';
        if TextCss <> '' then
            TextAttr := ' style="' + MText.Esc(TextCss) + '"';
        if ShapeValues.ContainsKey('stroke') then
            Stroke := ShapeValues.Get('stroke');
        if TextValues.Get('font-weight', Weight) then begin
            IsBold := (Weight = 'bold') or (Weight = 'bolder');
            if Evaluate(WeightNo, Weight, 9) then
                if WeightNo >= 600 then
                    IsBold := true;
        end;
        if TextValues.Get('font-style', Value) then
            IsItalic := Value = 'italic';
        if TextValues.Get('font-size', Size) then begin
            if Size.EndsWith('px') then
                Size := CopyStr(Size, 1, StrLen(Size) - 2);
            if IsPlainNumber(Size) then
                if Evaluate(Px, Size, 9) then
                    if (Px > 0) and (Px <= 200) then
                        StyleFontSize := Px;
        end;
    end;

    local procedure IsPlainNumber(Value: Text): Boolean
    var
        I: Integer;
    begin
        if Value = '' then
            exit(false);
        for I := 1 to StrLen(Value) do
            if not (MText.IsDigit(MText.CharAt(Value, I)) or (Value[I] = '.')) then
                exit(false);
        exit(true);
    end;

    local procedure RemoveImportant(Value: Text): Text
    var
        Pos: Integer;
    begin
        Pos := StrPos(LowerCase(Value), '!important');
        while Pos > 0 do begin
            Value := CopyStr(Value, 1, Pos - 1) + CopyStr(Value, Pos + 10);
            Pos := StrPos(LowerCase(Value), '!important');
        end;
        exit(Value);
    end;

    // ---------------------------------------------------------------- document

    /// <summary>A rectangle's corner radius comes from a variable, which browsers take reliably only in a style.</summary>
    local procedure Rounded(Content: Text): Text
    var
        Builder: TextBuilder;
        RoundedAttr: Text;
        I: Integer;
        TagEnd: Integer;
        Tag: Text;
        At: Integer;
        StylePos: Integer;
        EndPos: Integer;
        LastPos: Integer;
    begin
        RoundedAttr := ' rx="' + Radius() + '"';
        if StrPos(Content, RoundedAttr) = 0 then
            exit(Content);
        LastPos := 1;
        I := StrPos(Content, '<rect');
        while I > 0 do begin
            TagEnd := MText.IndexOfFrom(Content, '>', I);
            if TagEnd > 0 then begin
                Tag := MText.Substr(Content, I, TagEnd + 1);
                At := StrPos(Tag, RoundedAttr);
                if At > 0 then begin
                    Tag := CopyStr(Tag, 1, At - 1) + CopyStr(Tag, At + StrLen(RoundedAttr));
                    StylePos := StrPos(Tag, ' style="');
                    if StylePos > 0 then
                        Tag := CopyStr(Tag, 1, StylePos + 7) + 'rx:var(--_r);' + CopyStr(Tag, StylePos + 8)
                    else begin
                        if Tag.EndsWith('/>') then
                            EndPos := StrLen(Tag) - 1
                        else
                            EndPos := StrLen(Tag);
                        Tag := CopyStr(Tag, 1, EndPos - 1) + ' style="rx:var(--_r)"' + CopyStr(Tag, EndPos);
                    end;
                    Builder.Append(MText.Substr(Content, LastPos, I));
                    Builder.Append(Tag);
                    LastPos := TagEnd + 1;
                end;
                I := MText.IndexOfFrom(Content, '<rect', TagEnd + 1);
            end else
                I := 0;
        end;
        Builder.Append(CopyStr(Content, LastPos));
        exit(Builder.ToText());
    end;

    procedure Document(DiagramType: Text; Width: Decimal; Height: Decimal; FontSize: Decimal; AccTitle: Text; AccDescr: Text; Content: Text): Text
    var
        Prefix: Text;
        Head: Text;
        Aria: Text;
        Fit: Text;
        Weights: Text;
        W: Text;
        H: Text;
    begin
        Prefix := MText.Esc(MText.IdPrefix());
        if AccTitle <> '' then begin
            Head += '<title id="' + Prefix + '-title">' + MText.EscText(AccTitle) + '</title>';
            Aria += ' aria-labelledby="' + Prefix + '-title"';
        end;
        if AccDescr <> '' then begin
            Head += '<desc id="' + Prefix + '-desc">' + MText.EscText(AccDescr) + '</desc>';
            Aria += ' aria-describedby="' + Prefix + '-desc"';
        end;
        if MText.Responsive() then
            Fit := 'max-width:100%;height:auto;';
        Content := Rounded(Content);
        if Content.Contains('var(--_r)') then
            Weights := ';--_r:' + Radius();
        if Content.Contains('var(--_tw)') then
            Weights += ';--_tw:var(--pele-title-weight,bold)';
        if Content.Contains('var(--_hw)') then
            Weights += ';--_hw:var(--pele-heading-weight,bold)';
        if Content.Contains('var(--_w)') then
            Weights += ';--_w:var(--pele-bold-weight,bold)';
        W := MText.Num(Width);
        H := MText.Num(Height);
        exit('<svg xmlns="http://www.w3.org/2000/svg" class="pele pele-' + DiagramType + '" viewBox="0 0 ' + W + ' ' + H +
             '" width="' + W + '" height="' + H + '" style="' + Fit + RootStyle() + Weights + MText.Esc(FontStyle(FontSize, MText.FontFamily())) +
             '" fill="var(--_fg)" role="graphics-document document" aria-roledescription="' + DiagramType + '"' + Aria + '>' +
             Head + Content + '</svg>');
    end;

    // ---------------------------------------------------------------- markers

    procedure Arrow(): Decimal
    begin
        Init();
        exit(ArrowLen);
    end;

    procedure MarkerTrim(MarkerType: Text): Decimal
    begin
        Init();
        case MarkerType of
            'arrow_point':
                exit(ArrowLen - 1);
            'arrow_circle':
                exit(ArrowLen);
            'arrow_cross':
                exit(4);
        end;
        exit(0);
    end;

    /// <summary>Draws a marker whose tip is at (X, Y), pointing along (Dx, Dy).</summary>
    procedure Marker(MarkerType: Text; X: Decimal; Y: Decimal; Dx: Decimal; Dy: Decimal; Color: Text): Text
    var
        Nx: Decimal;
        Ny: Decimal;
        Bx: Decimal;
        By: Decimal;
        HalfW: Decimal;
        Cx: Decimal;
        Cy: Decimal;
        A: Decimal;
        Ux: Decimal;
        Uy: Decimal;
        Vx: Decimal;
        Vy: Decimal;
    begin
        Init();
        Nx := -Dy;
        Ny := Dx;
        case MarkerType of
            'arrow_point':
                begin
                    Bx := X - Dx * ArrowLen;
                    By := Y - Dy * ArrowLen;
                    HalfW := ArrowLen * 0.42;
                    exit('<path class="pele-marker" d="M' + P(X, Y) + 'L' + P(Bx + Nx * HalfW, By + Ny * HalfW) + 'L' +
                         P(Bx - Nx * HalfW, By - Ny * HalfW) + 'Z" fill="' + Color + '" stroke="none"/>');
                end;
            'arrow_circle':
                exit('<circle class="pele-marker" cx="' + MText.Num(X - Dx * 4) + '" cy="' + MText.Num(Y - Dy * 4) + '" r="3.5" fill="' + Color + '" stroke="none"/>');
            'arrow_cross':
                begin
                    Cx := X - Dx * 4;
                    Cy := Y - Dy * 4;
                    A := 3.5;
                    Ux := (Dx + Nx) * A;
                    Uy := (Dy + Ny) * A;
                    Vx := (Dx - Nx) * A;
                    Vy := (Dy - Ny) * A;
                    exit('<path class="pele-marker" d="M' + P(Cx - Ux, Cy - Uy) + 'L' + P(Cx + Ux, Cy + Uy) + 'M' + P(Cx - Vx, Cy - Vy) + 'L' + P(Cx + Vx, Cy + Vy) + '"/>');
                end;
        end;
        exit('');
    end;

    /// <summary>"x,y" with two decimals.</summary>
    procedure P(X: Decimal; Y: Decimal): Text
    begin
        exit(MText.Num(X) + ',' + MText.Num(Y));
    end;

    // ---------------------------------------------------------------- routes

    /// <summary>
    /// How far along the flow the handles of a plain S reach, as a share of the way it travels along it.
    /// Half gives an even S; one that runs far across turns sooner, down to a quarter.
    /// </summary>
    procedure Ease(Across: Decimal; Along: Decimal): Decimal
    var
        Den: Decimal;
    begin
        Den := Abs(Across);
        if Den = 0 then
            Den := 1;
        exit(MText.MaxDec(0.25, MText.MinDec(0.5, (4 * Abs(Along)) / Den)));
    end;

    local procedure Near(Ax: Decimal; Ay: Decimal; Bx: Decimal; By: Decimal): Boolean
    begin
        exit((Abs(Ax - Bx) < 0.01) and (Abs(Ay - By) < 0.01));
    end;

    local procedure Aligned(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer): Boolean
    begin
        exit((Abs(Xs.Get(I) - Xs.Get(I - 1)) < 0.01) or (Abs(Ys.Get(I) - Ys.Get(I - 1)) < 0.01));
    end;

    local procedure IsStraight(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer; Linear: Boolean): Boolean
    begin
        if Linear then
            exit(true);
        exit(Aligned(Xs, Ys, I));
    end;

    local procedure UnitVector(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer; J: Integer; Axis: Decimal; Linear: Boolean; var Ux: Decimal; var Uy: Decimal)
    var
        Dx: Decimal;
        Dy: Decimal;
        Len: Decimal;
        MaxIJ: Integer;
    begin
        MaxIJ := I;
        if J > MaxIJ then
            MaxIJ := J;
        if not IsStraight(Xs, Ys, MaxIJ, Linear) then begin
            if Axis = 0 then begin
                Ux := 0;
                Uy := MText.Sign(Ys.Get(J) - Ys.Get(I));
                if Uy = 0 then
                    Uy := 1;
            end else begin
                Uy := 0;
                Ux := MText.Sign(Xs.Get(J) - Xs.Get(I));
                if Ux = 0 then
                    Ux := 1;
            end;
            exit;
        end;
        Dx := Xs.Get(J) - Xs.Get(I);
        Dy := Ys.Get(J) - Ys.Get(I);
        Len := MText.Hypot(Dx, Dy);
        if Len = 0 then
            Len := 1;
        Ux := Dx / Len;
        Uy := Dy / Len;
    end;

    local procedure SegLength(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer): Decimal
    begin
        exit(Abs(Xs.Get(I) - Xs.Get(I - 1)) + Abs(Ys.Get(I) - Ys.Get(I - 1)));
    end;

    /// <summary>Whether the route turns a corner at point I, from running one way to running the other.</summary>
    local procedure Turns(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer; LastIdx: Integer; Linear: Boolean): Boolean
    var
        Vertical1: Boolean;
        Vertical2: Boolean;
    begin
        if Linear or (I <= 1) or (I >= LastIdx) then
            exit(false);
        if not (Aligned(Xs, Ys, I) and Aligned(Xs, Ys, I + 1)) then
            exit(false);
        if (SegLength(Xs, Ys, I) < 0.01) or (SegLength(Xs, Ys, I + 1) < 0.01) then
            exit(false);
        Vertical1 := Abs(Xs.Get(I) - Xs.Get(I - 1)) < 0.01;
        Vertical2 := Abs(Xs.Get(I + 1) - Xs.Get(I)) < 0.01;
        exit(Vertical1 <> Vertical2);
    end;

    local procedure AlongRun(var Xs: List of [Decimal]; var Ys: List of [Decimal]; I: Integer; Ux: Decimal; Uy: Decimal): Decimal
    begin
        exit(Abs(Xs.Get(I) - Xs.Get(I - 1)) * Abs(Ux) + Abs(Ys.Get(I) - Ys.Get(I - 1)) * Abs(Uy));
    end;

    local procedure Lead(Reach: Decimal; Trim: Decimal; RunLength: Decimal): Decimal
    var
        Room: Decimal;
    begin
        Room := MText.MinDec(MText.MaxDec(0, Reach - LeadLen - Trim), RunLength / 4);
        exit(Room + MText.MinDec(Reach - Trim - Room, (RunLength - Room) / 4));
    end;

    /// <summary>
    /// Builds the path for a route of x, y, axis triples, trimming both ends to leave room for markers
    /// (pele's routePath). Between two points that are not in line the route is one S along the flow;
    /// where the route turns a corner it turns widely, or with a small rounding for stepped curves.
    /// </summary>
    procedure RoutePath(Route: List of [Decimal]; Curve: Text; StartTrim: Decimal; EndTrim: Decimal; var D: Text; var Sx: Decimal; var Sy: Decimal; var Sdx: Decimal; var Sdy: Decimal; var Ex: Decimal; var Ey: Decimal; var Edx: Decimal; var Edy: Decimal)
    var
        Xs: List of [Decimal];
        Ys: List of [Decimal];
        Axes: List of [Decimal];
        TurnPts: List of [Decimal];
        Builder: TextBuilder;
        Linear: Boolean;
        Stepped: Boolean;
        I: Integer;
        K: Integer;
        LastIdx: Integer;
        X: Decimal;
        Y: Decimal;
        Axis: Decimal;
        Px: Decimal;
        Py: Decimal;
        Mx: Decimal;
        My: Decimal;
        StartReach: Decimal;
        EndReach: Decimal;
        Arrives: Decimal;
        Leaves: Decimal;
        AtX: Decimal;
        AtY: Decimal;
        Down: Boolean;
        AlongV: Decimal;
        KHandle: Decimal;
        Ux: Decimal;
        Uy: Decimal;
        Vx: Decimal;
        Vy: Decimal;
        Before: Decimal;
        After: Decimal;
        Skip: Boolean;
    begin
        Init();
        D := '';
        Linear := Curve = 'linear';
        Stepped := (Curve = 'step') or (Curve = 'stepBefore') or (Curve = 'stepAfter');
        I := 1;
        while I + 2 <= Route.Count() do begin
            X := Route.Get(I);
            Y := Route.Get(I + 1);
            Axis := Route.Get(I + 2);
            LastIdx := Xs.Count();
            // A stepped route turns at right angles where a smooth one would curve.
            if Stepped and (LastIdx >= 1) then
                if (Abs(X - Xs.Get(LastIdx)) >= 0.01) and (Abs(Y - Ys.Get(LastIdx)) >= 0.01) then begin
                    Px := Xs.Get(LastIdx);
                    Py := Ys.Get(LastIdx);
                    case Curve of
                        'stepBefore':
                            begin
                                My := Py;
                                Mx := Px;
                            end;
                        'stepAfter':
                            begin
                                My := Y;
                                Mx := X;
                            end;
                        else begin
                            My := (Py + Y) / 2;
                            Mx := (Px + X) / 2;
                        end;
                    end;
                    Clear(TurnPts);
                    if Axis = 0 then begin
                        TurnPts.Add(Px);
                        TurnPts.Add(My);
                        TurnPts.Add(X);
                        TurnPts.Add(My);
                    end else begin
                        TurnPts.Add(Mx);
                        TurnPts.Add(Py);
                        TurnPts.Add(Mx);
                        TurnPts.Add(Y);
                    end;
                    for K := 0 to 1 do
                        if not (Near(TurnPts.Get(K * 2 + 1), TurnPts.Get(K * 2 + 2), Px, Py) or Near(TurnPts.Get(K * 2 + 1), TurnPts.Get(K * 2 + 2), X, Y)) then begin
                            Xs.Add(TurnPts.Get(K * 2 + 1));
                            Ys.Add(TurnPts.Get(K * 2 + 2));
                            Axes.Add(Axis);
                        end;
                end;
            Xs.Add(X);
            Ys.Add(Y);
            Axes.Add(Axis);
            I += 3;
        end;
        LastIdx := Xs.Count();
        if LastIdx < 2 then
            exit;

        UnitVector(Xs, Ys, 1, 2, Axes.Get(2), Linear, Sdx, Sdy);
        UnitVector(Xs, Ys, LastIdx - 1, LastIdx, Axes.Get(LastIdx), Linear, Edx, Edy);
        Sx := Xs.Get(1);
        Sy := Ys.Get(1);
        Ex := Xs.Get(LastIdx);
        Ey := Ys.Get(LastIdx);
        Xs.Set(1, Xs.Get(1) + Sdx * StartTrim);
        Ys.Set(1, Ys.Get(1) + Sdy * StartTrim);
        Xs.Set(LastIdx, Xs.Get(LastIdx) - Edx * EndTrim);
        Ys.Set(LastIdx, Ys.Get(LastIdx) - Edy * EndTrim);

        // An edge that curves into a marker runs straight for a little way first, where it has the room.
        StartReach := 0;
        if StartTrim > 0 then
            StartReach := StartTrim + LeadLen;
        EndReach := 0;
        if EndTrim > 0 then
            EndReach := EndTrim + LeadLen;
        Arrives := 0;
        if EndReach > EndTrim then
            if (not IsStraight(Xs, Ys, LastIdx, Linear)) or Turns(Xs, Ys, LastIdx - 1, LastIdx, Linear) then
                Arrives := Lead(EndReach, EndTrim, AlongRun(Xs, Ys, LastIdx, Edx, Edy));
        Leaves := 0;
        if StartReach > StartTrim then
            if (not IsStraight(Xs, Ys, 2, Linear)) or Turns(Xs, Ys, 2, LastIdx, Linear) then
                Leaves := Lead(StartReach, StartTrim, AlongRun(Xs, Ys, 2, Sdx, Sdy));
        if Arrives >= 1 then begin
            Xs.Insert(LastIdx, Xs.Get(LastIdx) - Edx * Arrives);
            Ys.Insert(LastIdx, Ys.Get(LastIdx) - Edy * Arrives);
            Axes.Insert(LastIdx, Axes.Get(LastIdx));
            LastIdx += 1;
        end;
        if Leaves >= 1 then begin
            Xs.Insert(2, Xs.Get(1) + Sdx * Leaves);
            Ys.Insert(2, Ys.Get(1) + Sdy * Leaves);
            Axes.Insert(2, Axes.Get(2));
            LastIdx += 1;
        end;

        Builder.Append('M' + P(Xs.Get(1), Ys.Get(1)));
        AtX := Xs.Get(1);
        AtY := Ys.Get(1);
        for I := 2 to LastIdx do begin
            X := Xs.Get(I);
            Y := Ys.Get(I);
            if not IsStraight(Xs, Ys, I, Linear) then begin
                Down := Axes.Get(I) = 0;
                if Down then begin
                    AlongV := Y - AtY;
                    KHandle := Abs(AlongV) * Ease(X - AtX, AlongV);
                    Ux := 0;
                    Uy := MText.Sign(AlongV) * KHandle;
                end else begin
                    AlongV := X - AtX;
                    KHandle := Abs(AlongV) * Ease(Y - AtY, AlongV);
                    Ux := MText.Sign(AlongV) * KHandle;
                    Uy := 0;
                end;
                Builder.Append('C' + P(AtX + Ux, AtY + Uy) + ' ' + P(X - Ux, Y - Uy) + ' ' + P(X, Y));
                AtX := X;
                AtY := Y;
            end else
                if not Turns(Xs, Ys, I, LastIdx, Linear) then begin
                    // A point part of the way along one straight run adds nothing to the path.
                    Skip := false;
                    if I < LastIdx then
                        if Aligned(Xs, Ys, I) and Aligned(Xs, Ys, I + 1) then
                            if (X - Xs.Get(I - 1)) * (Xs.Get(I + 1) - X) + (Y - Ys.Get(I - 1)) * (Ys.Get(I + 1) - Y) > 0 then
                                Skip := true;
                    if not Skip then
                        if not Near(X, Y, AtX, AtY) then begin
                            Builder.Append('L' + P(X, Y));
                            AtX := X;
                            AtY := Y;
                        end;
                end else begin
                    if Turns(Xs, Ys, I - 1, LastIdx, Linear) then
                        Before := SegLength(Xs, Ys, I) / 2
                    else
                        Before := SegLength(Xs, Ys, I);
                    if Turns(Xs, Ys, I + 1, LastIdx, Linear) then
                        After := SegLength(Xs, Ys, I + 1) / 2
                    else
                        After := SegLength(Xs, Ys, I + 1);
                    if Stepped then begin
                        Before := MText.MinDec(CornerLen, MText.MinDec(Before, After));
                        After := Before;
                    end;
                    UnitVector(Xs, Ys, I - 1, I, Axes.Get(I), Linear, Ux, Uy);
                    UnitVector(Xs, Ys, I, I + 1, Axes.Get(I + 1), Linear, Vx, Vy);
                    if not Near(X - Ux * Before, Y - Uy * Before, AtX, AtY) then
                        Builder.Append('L' + P(X - Ux * Before, Y - Uy * Before));
                    AtX := X + Vx * After;
                    AtY := Y + Vy * After;
                    if Stepped then
                        Builder.Append('Q' + P(X, Y) + ' ' + P(AtX, AtY))
                    else
                        Builder.Append('C' + P(X - Ux * Before * (1 - HandleRatio), Y - Uy * Before * (1 - HandleRatio)) + ' ' +
                                       P(X + Vx * After * (1 - HandleRatio), Y + Vy * After * (1 - HandleRatio)) + ' ' + P(AtX, AtY));
                end;
        end;
        D := Builder.ToText();
        Sdx := -Sdx;
        Sdy := -Sdy;
    end;

    /// <summary>
    /// A self-loop beside a node of drawn size W by H: out of the side that lies across the flow and back in.
    /// K counts the loops already on the node, so each reaches a little further. Also places the label beyond the loop.
    /// </summary>
    procedure LoopPath(Cx: Decimal; Cy: Decimal; W: Decimal; H: Decimal; K: Integer; Sideways: Boolean; Base: Decimal; Trim: Decimal; LabelW: Decimal; LabelH: Decimal; var LabelX: Decimal; var LabelY: Decimal; var D: Text; var Ex: Decimal; var Ey: Decimal; var Edx: Decimal; var Edy: Decimal)
    var
        HalfSide: Decimal;
        Spread: Decimal;
        Reach: Decimal;
        Len: Decimal;
        Tx: Decimal;
        Ty: Decimal;
    begin
        if Sideways then
            HalfSide := W / 2
        else
            HalfSide := H / 2;
        Spread := MText.MinDec(HalfSide - 4, 8 + K * 6);
        Reach := Base + K * 8;
        Len := MText.Hypot(Reach, Spread);
        if Len = 0 then
            Len := 1;
        Tx := (Reach / Len) * Trim;
        Ty := (Spread / Len) * Trim;
        if Sideways then begin
            LabelX := Cx;
            LabelY := Cy + H / 2 + Reach + 4 + LabelH / 2;
        end else begin
            LabelX := Cx + W / 2 + Reach + 4 + LabelW / 2;
            LabelY := Cy;
        end;
        D := 'M' + LoopAt(Cx, Cy, W, H, Sideways, 0, -Spread) + 'C' + LoopAt(Cx, Cy, W, H, Sideways, Reach, -Spread * 2) + ' ' +
             LoopAt(Cx, Cy, W, H, Sideways, Reach, Spread * 2) + ' ' + LoopAt(Cx, Cy, W, H, Sideways, Tx, Spread + Ty);
        if Sideways then begin
            Ex := Cx + Spread;
            Ey := Cy + H / 2;
            Edx := -Spread / Len;
            Edy := -Reach / Len;
        end else begin
            Ex := Cx + W / 2;
            Ey := Cy + Spread;
            Edx := -Reach / Len;
            Edy := -Spread / Len;
        end;
    end;

    local procedure LoopAt(Cx: Decimal; Cy: Decimal; W: Decimal; H: Decimal; Sideways: Boolean; OutV: Decimal; AlongV: Decimal): Text
    begin
        if Sideways then
            exit(P(Cx + AlongV, Cy + H / 2 + OutV));
        exit(P(Cx + W / 2 + OutV, Cy + AlongV));
    end;

    /// <summary>An edge label on a patch of the background, so the line does not run through the text.</summary>
    procedure EdgeLabelSvg(Id: Text; var Lbl: Codeunit "Mermaid Label"; X: Decimal; Y: Decimal; Attrs: Text): Text
    var
        W: Decimal;
        H: Decimal;
    begin
        W := Lbl.GetWidth() + 8;
        H := Lbl.GetHeight();
        exit('<g class="pele-edge-label" data-id="' + MText.EscText(Id) + '">' +
             '<rect x="' + MText.Num(X - W / 2) + '" y="' + MText.Num(Y - H / 2) + '" width="' + MText.Num(W) + '" height="' + MText.Num(H) + '" rx="3" fill="var(--_bg)"/>' +
             Lbl.ToSvg(X, Y, Attrs) + '</g>');
    end;

    /// <summary>
    /// The attributes that carry a Mermaid click callback (click X call name(args)) to the viewer, which passes
    /// them to AL in its ElementClicked event. Callbacks are never run as script. Empty when there is no callback.
    /// </summary>
    procedure CallbackAttrs(CallbackName: Text; CallbackArgs: Text): Text
    var
        Result: Text;
    begin
        if CallbackName = '' then
            exit('');
        Result := ' data-callback="' + MText.EscText(CallbackName) + '"';
        if CallbackArgs <> '' then
            Result += ' data-args="' + MText.EscText(CallbackArgs) + '"';
        exit(Result);
    end;

    /// <summary>The diagram title, bold and centred.</summary>
    procedure TitleSvg(var Lbl: Codeunit "Mermaid Label"; Cx: Decimal; Cy: Decimal): Text
    begin
        exit(Lbl.ToSvg(Cx, Cy, ' class="pele-title" font-weight="var(--_tw)"'));
    end;
}
