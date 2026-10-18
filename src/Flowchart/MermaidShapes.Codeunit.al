/// <summary>
/// Port of pele's svg/shapes.ts and diagrams/flowchart/shapes.ts: the node shapes of a flowchart, how big
/// each is for its label, how it is drawn, how far its outline lies inside its box, and how much of a side
/// edges may spread along. Shapes are drawn centred on (0, 0).
/// </summary>
codeunit 68908 "Mermaid Shapes"
{
    Access = Internal;

    var
        MText: Codeunit "Mermaid Text";
        Math: Codeunit Math;
        Aliases: Dictionary of [Text, Text];
        PadX: Decimal;
        PadY: Decimal;
        Corner: Decimal;

    local procedure Init()
    begin
        PadX := 18;
        PadY := 12;
        Corner := 12;
        if Aliases.Count() > 0 then
            exit;
        AddAliases('rect,proc,process,rectangle,squareRect');
        AddAliases('rounded,event,roundedRect');
        AddAliases('stadium,terminal,pill');
        AddAliases('fr-rect,subprocess,subproc,framed-rectangle,subroutine');
        AddAliases('cyl,db,database,cylinder');
        AddAliases('datastore,data-store');
        AddAliases('folder,directory');
        AddAliases('bucket');
        AddAliases('console');
        AddAliases('browser');
        AddAliases('person');
        AddAliases('circle,circ');
        AddAliases('bang');
        AddAliases('cloud');
        AddAliases('diam,decision,diamond,question');
        AddAliases('hex,hexagon,prepare');
        AddAliases('lean-r,lean-right,in-out,lean_right');
        AddAliases('lean-l,lean-left,out-in,lean_left');
        AddAliases('trap-b,priority,trapezoid-bottom,trapezoid');
        AddAliases('trap-t,manual,trapezoid-top,inv-trapezoid,inv_trapezoid');
        AddAliases('dbl-circ,double-circle,doublecircle');
        AddAliases('text');
        AddAliases('notch-rect,card,notched-rectangle');
        AddAliases('lin-rect,lined-rectangle,lined-process,lin-proc,shaded-process');
        AddAliases('sm-circ,start,small-circle,stateStart');
        AddAliases('fr-circ,stop,framed-circle,stateEnd');
        AddAliases('fork,join,forkJoin');
        AddAliases('hourglass,collate');
        AddAliases('brace,comment,brace-l');
        AddAliases('brace-r');
        AddAliases('braces');
        AddAliases('bolt,com-link,lightning-bolt');
        AddAliases('doc,document');
        AddAliases('delay,half-rounded-rectangle');
        AddAliases('h-cyl,das,horizontal-cylinder');
        AddAliases('lin-cyl,disk,lined-cylinder');
        AddAliases('curv-trap,curved-trapezoid,display');
        AddAliases('div-rect,div-proc,divided-rectangle,divided-process');
        AddAliases('tri,extract,triangle');
        AddAliases('win-pane,internal-storage,window-pane');
        AddAliases('f-circ,junction,filled-circle');
        AddAliases('notch-pent,loop-limit,notched-pentagon');
        AddAliases('flip-tri,manual-file,flipped-triangle');
        AddAliases('sl-rect,manual-input,sloped-rectangle');
        AddAliases('docs,documents,st-doc,stacked-document');
        AddAliases('st-rect,procs,processes,stacked-rectangle');
        AddAliases('bow-rect,stored-data,bow-tie-rectangle');
        AddAliases('cross-circ,summary,crossed-circle');
        AddAliases('tag-doc,tagged-document');
        AddAliases('tag-rect,tagged-rectangle,tag-proc,tagged-process');
        AddAliases('flag,paper-tape');
        AddAliases('odd,rect_left_inv_arrow');
        AddAliases('lin-doc,lined-document');
        // Shapes Mermaid accepts by name without documenting them.
        AddInternal('state,choice,note,composite,rectWithTitle,labelRect,block_arrow,collapsedGroup,iconSquare,iconCircle,icon,iconRounded,imageSquare,anchor');
        AddInternal('kanbanItem,mindmapCircle,defaultMindmapNode,classBox,erBox,requirementBox,usecaseActor,usecaseActorHollow,usecaseActorAwesome');
        AddInternal('usecaseActorIcon,usecaseBusiness,usecaseEllipse,usecaseJsonTable');
    end;

    local procedure AddAliases(Names: Text)
    var
        List: List of [Text];
        Name: Text;
    begin
        List := Names.Split(',');
        foreach Name in List do
            if not Aliases.ContainsKey(Name) then
                Aliases.Add(Name, List.Get(1));
    end;

    local procedure AddInternal(Names: Text)
    var
        Name: Text;
    begin
        foreach Name in Names.Split(',') do
            if not Aliases.ContainsKey(Name) then
                Aliases.Add(Name, Name);
    end;

    procedure IsValidShape(Name: Text): Boolean
    begin
        Init();
        exit(Aliases.ContainsKey(Name));
    end;

    /// <summary>The documented short name for a shape name or alias; bracket syntax names included.</summary>
    procedure Canonical(Name: Text): Text
    var
        Result: Text;
    begin
        Init();
        case Name of
            '':
                exit('rect');
            'square':
                exit('rect');
            'round':
                exit('rounded');
            'ellipse':
                exit('ellipse');
            'hexagon':
                exit('hex');
            'diamond':
                exit('diam');
        end;
        if Aliases.Get(Name, Result) then
            exit(Result);
        exit('rect');
    end;

    procedure HasLabel(Shape: Text): Boolean
    begin
        exit(not (Shape in ['sm-circ', 'f-circ', 'fr-circ', 'fork', 'hourglass', 'cross-circ', 'bolt']));
    end;

    // ---------------------------------------------------------------- helpers

    local procedure N(Value: Decimal): Text
    begin
        exit(MText.Num(Value));
    end;

    local procedure RoundedAttr(): Text
    begin
        exit(' rx="var(--pele-radius,4px)"');
    end;

    local procedure RectSvg(W: Decimal; H: Decimal; A: Text; Rx: Text): Text
    begin
        exit('<rect x="' + N(-W / 2) + '" y="' + N(-H / 2) + '" width="' + N(W) + '" height="' + N(H) + '"' + Rx + A + '/>');
    end;

    local procedure PathSvg(D: Text; A: Text): Text
    begin
        exit('<path d="' + D + '"' + A + '/>');
    end;

    local procedure Poly(Points: List of [Decimal]; A: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
    begin
        I := 1;
        while I < Points.Count() do begin
            if I > 1 then
                Builder.Append(' ');
            Builder.Append(N(Points.Get(I)) + ',' + N(Points.Get(I + 1)));
            I += 2;
        end;
        exit('<polygon points="' + Builder.ToText() + '"' + A + '/>');
    end;

    local procedure Pts(var Points: List of [Decimal]; X: Decimal; Y: Decimal)
    begin
        Points.Add(X);
        Points.Add(Y);
    end;

    local procedure Bulge(T: Decimal; HalfLen: Decimal; Depth: Decimal): Decimal
    var
        K: Decimal;
    begin
        if HalfLen <= 0 then
            exit(0);
        K := MText.MinDec(1, Abs(T) / HalfLen);
        exit(Depth * (1 - MText.Sqrt(1 - K * K)));
    end;

    local procedure CylRy(W: Decimal): Decimal
    begin
        exit(MText.MinDec(12, MText.MaxDec(6, W / 14)));
    end;

    local procedure Wave(W: Decimal; H: Decimal; A: Text): Text
    var
        X: Decimal;
        Top: Decimal;
        Base: Decimal;
        Q: Decimal;
    begin
        X := W / 2;
        Top := -H / 2;
        Base := H / 2 - 10;
        Q := W / 4;
        exit('<path d="M' + N(-X) + ',' + N(Top) + 'H' + N(X) + 'V' + N(Base) + 'q' + N(-Q) + ',-12 ' + N(-2 * Q) + ',0t' + N(-2 * Q) + ',0Z"' + A + '/>');
    end;

    local procedure Brace(X: Decimal; H: Decimal; Dir: Decimal; LineAttr: Text): Text
    var
        Y: Decimal;
        K: Decimal;
    begin
        Y := H / 2;
        K := 6 * Dir;
        exit('<path d="M' + N(X) + ',' + N(-Y) + 'q' + N(K) + ',0 ' + N(K) + ',6V-6q0,6 ' + N(K) + ',6q' + N(-K) + ',0 ' + N(-K) + ',6V' + N(Y - 6) +
             'q0,6 ' + N(-K) + ',6" fill="none"' + LineAttr + '/>');
    end;

    local procedure TriSize(Tw: Decimal; Th: Decimal; Flip: Boolean; var W: Decimal; var H: Decimal; var Dy: Decimal)
    begin
        W := MText.MaxDec(1.6 * Tw + 40, 80);
        H := (Th + 10) / (1 - (Tw + 8) / W);
        Dy := H / 2 - 10 - Th / 2;
        if Flip then
            Dy := -Dy;
    end;

    // ---------------------------------------------------------------- size

    /// <summary>The size of a shape that holds a label Tw by Th, and how far the label sits below its centre.</summary>
    procedure GetSize(Shape: Text; Tw: Decimal; Th: Decimal; var W: Decimal; var H: Decimal; var Dy: Decimal)
    var
        Rx: Decimal;
        Ry: Decimal;
    begin
        Init();
        Dy := 0;
        case Shape of
            'stadium':
                begin
                    H := Th + 2 * PadY;
                    W := Tw + H * 0.5 + 2 * PadX - 8;
                end;
            'fr-rect':
                begin
                    W := Tw + 2 * PadX + 16;
                    H := Th + 2 * PadY;
                end;
            'cyl':
                begin
                    W := MText.MaxDec(Tw + 2 * PadX, 56);
                    Ry := CylRy(W);
                    H := Th + 2 * PadY + 2 * Ry;
                    Dy := Ry / 2;
                end;
            'lin-cyl':
                begin
                    W := MText.MaxDec(Tw + 2 * PadX, 56);
                    Ry := CylRy(W);
                    H := Th + 2 * PadY + 2 * Ry + 8;
                    Dy := Ry / 2 + 4;
                end;
            'circle':
                begin
                    W := MText.MaxDec(MText.Hypot(Tw, Th) + 16, 44);
                    H := W;
                end;
            'dbl-circ':
                begin
                    W := MText.MaxDec(MText.Hypot(Tw, Th) + 26, 54);
                    H := W;
                end;
            'ellipse':
                begin
                    W := Tw * 1.3 + 2 * PadX;
                    H := Th * 1.2 + 2 * PadY;
                end;
            'diam':
                begin
                    W := (Tw + 16) + 1.6 * (Th + 8);
                    H := (Tw + 16) / 1.6 + (Th + 8);
                end;
            'hex', 'lean-r', 'lean-l', 'trap-b', 'trap-t':
                begin
                    H := Th + 2 * PadY;
                    W := Tw + 2 * PadX + H / 2;
                end;
            'odd', 'delay':
                begin
                    H := Th + 2 * PadY;
                    W := Tw + 2 * PadX + H / 4;
                end;
            'text':
                begin
                    W := Tw + 8;
                    H := Th + 8;
                end;
            'sm-circ', 'f-circ':
                begin
                    W := 14;
                    H := 14;
                end;
            'fr-circ':
                begin
                    W := 18;
                    H := 18;
                end;
            'fork':
                begin
                    W := 72;
                    H := 8;
                end;
            'hourglass':
                begin
                    W := 32;
                    H := 40;
                end;
            'cross-circ':
                begin
                    W := 44;
                    H := 44;
                end;
            'bolt':
                begin
                    W := 36;
                    H := 56;
                end;
            'lin-rect':
                begin
                    W := Tw + 2 * PadX + 8;
                    H := Th + 2 * PadY;
                end;
            'div-rect':
                begin
                    W := Tw + 2 * PadX;
                    H := Th + 2 * PadY + 8;
                    Dy := 4;
                end;
            'win-pane', 'st-rect':
                begin
                    W := Tw + 2 * PadX + 8;
                    H := Th + 2 * PadY + 8;
                    Dy := 4;
                end;
            'tri':
                TriSize(Tw, Th, false, W, H, Dy);
            'flip-tri':
                TriSize(Tw, Th, true, W, H, Dy);
            'sl-rect':
                begin
                    W := Tw + 2 * PadX;
                    H := Th + 2 * PadY + 10;
                    Dy := 5;
                end;
            'notch-pent':
                begin
                    W := Tw + 2 * PadX;
                    H := Th + 2 * PadY;
                end;
            'h-cyl':
                begin
                    H := Th + 2 * PadY;
                    Rx := MText.MinDec(12, H / 4);
                    W := Tw + 2 * PadX + 2 * Rx;
                end;
            'doc', 'tag-doc':
                begin
                    W := Tw + 2 * PadX;
                    H := Th + 2 * PadY + 10;
                    Dy := -5;
                end;
            'lin-doc':
                begin
                    W := Tw + 2 * PadX + 8;
                    H := Th + 2 * PadY + 10;
                    Dy := -5;
                end;
            'docs':
                begin
                    W := Tw + 2 * PadX + 8;
                    H := Th + 2 * PadY + 18;
                    Dy := -1;
                end;
            'flag':
                begin
                    W := Tw + 2 * PadX;
                    H := Th + 2 * PadY + 16;
                end;
            'folder':
                begin
                    W := MText.MaxDec(Tw + 2 * PadX, 64);
                    H := Th + 2 * PadY + 8;
                    Dy := 4;
                end;
            'bucket':
                begin
                    W := Tw + 2 * PadX + 20;
                    H := Th + 2 * PadY + 10;
                    Dy := 3;
                end;
            'console', 'browser':
                begin
                    W := MText.MaxDec(Tw + 2 * PadX, 72);
                    H := Th + 2 * PadY + 12;
                    Dy := 6;
                end;
            'person':
                begin
                    W := MText.MaxDec(Tw + 2 * PadX, 56);
                    H := Th + 2 * PadY + 26;
                    Dy := 13;
                end;
            'bang':
                begin
                    W := Tw + 2 * PadX + 28;
                    H := Th + 2 * PadY + 24;
                end;
            'cloud':
                begin
                    W := Tw + 2 * PadX + 32;
                    H := Th + 2 * PadY + 24;
                end;
            'brace', 'brace-r':
                begin
                    W := Tw + 2 * PadX + 12;
                    H := Th + 2 * PadY;
                end;
            'braces':
                begin
                    W := Tw + 2 * PadX + 24;
                    H := Th + 2 * PadY;
                end;
            'curv-trap':
                begin
                    H := Th + 2 * PadY;
                    W := Tw + 2 * PadX + H * 0.6;
                end;
            'bow-rect':
                begin
                    H := Th + 2 * PadY;
                    W := Tw + 2 * PadX + H * 0.4;
                end;
            'collapsedGroup':
                begin
                    W := Tw + 2 * PadX + 8;
                    H := Th + 2 * PadY + 8;
                    Dy := -2;
                end;
            else begin
                // rect, rounded, notch-rect, datastore, tag-rect and anything unknown: a plain box.
                W := MText.MaxDec(Tw + 2 * PadX, 2 * PadX + 12);
                H := Th + 2 * PadY;
            end;
        end;
    end;

    // ---------------------------------------------------------------- drawing

    /// <summary>Draws a shape W by H centred on (0, 0). A is the fill and stroke, LineAttr the stroke of inner lines.</summary>
    procedure Draw(Shape: Text; W: Decimal; H: Decimal; A: Text; LineAttr: Text): Text
    var
        Points: List of [Decimal];
        X: Decimal;
        Y: Decimal;
        S: Decimal;
        M: Decimal;
        Rx: Decimal;
        Ry: Decimal;
        Top: Decimal;
        Bottom: Decimal;
        L: Decimal;
        R: Decimal;
        K: Decimal;
        Q: Decimal;
        Tab: Decimal;
        Taper: Decimal;
        Bw: Decimal;
        Bh: Decimal;
        Angle: Decimal;
        I: Integer;
        Result: Text;
    begin
        Init();
        case Shape of
            'rounded':
                exit(RectSvg(W, H, A, ' rx="' + N(MText.MinDec(12, H / 2)) + '"'));
            'stadium':
                exit(RectSvg(W, H, A, ' rx="' + N(H / 2) + '"'));
            'fr-rect':
                begin
                    X := W / 2 - 8;
                    exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-X) + ',' + N(-H / 2) + 'V' + N(H / 2) + 'M' + N(X) + ',' + N(-H / 2) + 'V' + N(H / 2) + '" fill="none"' + LineAttr + '/>');
                end;
            'cyl', 'lin-cyl':
                begin
                    Rx := W / 2;
                    Ry := CylRy(W);
                    Top := -H / 2 + Ry;
                    Bottom := H / 2 - Ry;
                    Result := '<path d="M' + N(-Rx) + ',' + N(Top) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 1 ' + N(Rx) + ',' + N(Top) + 'V' + N(Bottom) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 1 ' + N(-Rx) + ',' + N(Bottom) + 'Z"' + A + '/>';
                    if Shape = 'cyl' then
                        exit(Result + '<path d="M' + N(-Rx) + ',' + N(Top) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 0 ' + N(Rx) + ',' + N(Top) + '" fill="none"' + LineAttr + '/>');
                    exit(Result + '<path d="M' + N(-Rx) + ',' + N(Top) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 0 ' + N(Rx) + ',' + N(Top) +
                         'M' + N(-Rx) + ',' + N(Top + 8) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 0 ' + N(Rx) + ',' + N(Top + 8) + '" fill="none"' + LineAttr + '/>');
                end;
            'circle', 'sm-circ':
                exit('<circle r="' + N(W / 2) + '"' + A + '/>');
            'dbl-circ':
                exit('<circle r="' + N(W / 2) + '"' + A + '/><circle r="' + N(W / 2 - 5) + '" fill="none"' + LineAttr + '/>');
            'ellipse':
                exit('<ellipse rx="' + N(W / 2) + '" ry="' + N(H / 2) + '"' + A + '/>');
            'diam':
                begin
                    Pts(Points, 0, -H / 2);
                    Pts(Points, W / 2, 0);
                    Pts(Points, 0, H / 2);
                    Pts(Points, -W / 2, 0);
                    exit(Poly(Points, A));
                end;
            'hex':
                begin
                    M := H / 4;
                    Pts(Points, -W / 2 + M, -H / 2);
                    Pts(Points, W / 2 - M, -H / 2);
                    Pts(Points, W / 2, 0);
                    Pts(Points, W / 2 - M, H / 2);
                    Pts(Points, -W / 2 + M, H / 2);
                    Pts(Points, -W / 2, 0);
                    exit(Poly(Points, A));
                end;
            'odd':
                begin
                    Pts(Points, -W / 2, -H / 2);
                    Pts(Points, W / 2, -H / 2);
                    Pts(Points, W / 2, H / 2);
                    Pts(Points, -W / 2, H / 2);
                    Pts(Points, -W / 2 + H / 4, 0);
                    exit(Poly(Points, A));
                end;
            'lean-r', 'lean-l', 'trap-b', 'trap-t':
                begin
                    S := H / 4;
                    case Shape of
                        'lean-r':
                            begin
                                Pts(Points, -W / 2 + S, -H / 2);
                                Pts(Points, W / 2, -H / 2);
                                Pts(Points, W / 2 - S, H / 2);
                                Pts(Points, -W / 2, H / 2);
                            end;
                        'lean-l':
                            begin
                                Pts(Points, -W / 2, -H / 2);
                                Pts(Points, W / 2 - S, -H / 2);
                                Pts(Points, W / 2, H / 2);
                                Pts(Points, -W / 2 + S, H / 2);
                            end;
                        'trap-b':
                            begin
                                Pts(Points, -W / 2 + S, -H / 2);
                                Pts(Points, W / 2 - S, -H / 2);
                                Pts(Points, W / 2, H / 2);
                                Pts(Points, -W / 2, H / 2);
                            end;
                        else begin
                            Pts(Points, -W / 2, -H / 2);
                            Pts(Points, W / 2, -H / 2);
                            Pts(Points, W / 2 - S, H / 2);
                            Pts(Points, -W / 2 + S, H / 2);
                        end;
                    end;
                    exit(Poly(Points, A));
                end;
            'text':
                exit(RectSvg(W, H, ' fill="none" stroke="none"', ''));
            'f-circ':
                exit('<circle r="' + N(W / 2) + '" fill="var(--_l)"' + LineAttr + '/>');
            'fr-circ':
                exit('<circle r="' + N(W / 2) + '"' + A + '/><circle r="' + N(W / 2 - 4) + '" fill="var(--_l)"' + LineAttr + '/>');
            'fork':
                exit(RectSvg(W, H, ' fill="var(--_l)"' + LineAttr, ' rx="2"'));
            'notch-rect':
                begin
                    Pts(Points, -W / 2 + 10, -H / 2);
                    Pts(Points, W / 2, -H / 2);
                    Pts(Points, W / 2, H / 2);
                    Pts(Points, -W / 2, H / 2);
                    Pts(Points, -W / 2, -H / 2 + 10);
                    exit(Poly(Points, A));
                end;
            'lin-rect':
                exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-W / 2 + 8) + ',' + N(-H / 2) + 'V' + N(H / 2) + '" fill="none"' + LineAttr + '/>');
            'div-rect':
                exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-W / 2) + ',' + N(-H / 2 + 8) + 'H' + N(W / 2) + '" fill="none"' + LineAttr + '/>');
            'win-pane':
                exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-W / 2 + 8) + ',' + N(-H / 2) + 'V' + N(H / 2) + 'M' + N(-W / 2) + ',' + N(-H / 2 + 8) + 'H' + N(W / 2) + '" fill="none"' + LineAttr + '/>');
            'tri':
                begin
                    Pts(Points, 0, -H / 2);
                    Pts(Points, W / 2, H / 2);
                    Pts(Points, -W / 2, H / 2);
                    exit(Poly(Points, A));
                end;
            'flip-tri':
                begin
                    Pts(Points, -W / 2, -H / 2);
                    Pts(Points, W / 2, -H / 2);
                    Pts(Points, 0, H / 2);
                    exit(Poly(Points, A));
                end;
            'sl-rect':
                begin
                    Pts(Points, -W / 2, -H / 2 + 10);
                    Pts(Points, W / 2, -H / 2);
                    Pts(Points, W / 2, H / 2);
                    Pts(Points, -W / 2, H / 2);
                    exit(Poly(Points, A));
                end;
            'notch-pent':
                begin
                    Pts(Points, -W / 2 + 10, -H / 2);
                    Pts(Points, W / 2 - 10, -H / 2);
                    Pts(Points, W / 2, -H / 2 + 10);
                    Pts(Points, W / 2, H / 2);
                    Pts(Points, -W / 2, H / 2);
                    Pts(Points, -W / 2, -H / 2 + 10);
                    exit(Poly(Points, A));
                end;
            'hourglass':
                begin
                    Pts(Points, -W / 2, -H / 2);
                    Pts(Points, W / 2, -H / 2);
                    Pts(Points, -W / 2, H / 2);
                    Pts(Points, W / 2, H / 2);
                    exit(Poly(Points, A));
                end;
            'delay':
                begin
                    R := H / 2;
                    exit('<path d="M' + N(-W / 2) + ',' + N(-R) + 'H' + N(W / 2 - R) + 'A' + N(R) + ',' + N(R) + ' 0 0 1 ' + N(W / 2 - R) + ',' + N(R) + 'H' + N(-W / 2) + 'Z"' + A + '/>');
                end;
            'h-cyl':
                begin
                    Ry := H / 2;
                    Rx := MText.MinDec(12, H / 4);
                    L := -W / 2 + Rx;
                    R := W / 2 - Rx;
                    exit('<path d="M' + N(L) + ',' + N(-Ry) + 'H' + N(R) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 1 ' + N(R) + ',' + N(Ry) + 'H' + N(L) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 1 ' + N(L) + ',' + N(-Ry) + 'Z"' + A + '/>' +
                         '<path d="M' + N(R) + ',' + N(-Ry) + 'A' + N(Rx) + ',' + N(Ry) + ' 0 0 0 ' + N(R) + ',' + N(Ry) + '" fill="none"' + LineAttr + '/>');
                end;
            'cross-circ':
                begin
                    R := W / 2;
                    K := R * 0.70710678;
                    exit('<circle r="' + N(R) + '"' + A + '/><path d="M' + N(-K) + ',' + N(-K) + 'L' + N(K) + ',' + N(K) + 'M' + N(K) + ',' + N(-K) + 'L' + N(-K) + ',' + N(K) + '" fill="none"' + LineAttr + '/>');
                end;
            'st-rect':
                begin
                    Bw := W - 8;
                    Bh := H - 8;
                    for I := 0 to 2 do
                        Result += '<rect x="' + N(-W / 2 + (2 - I) * 4) + '" y="' + N(-H / 2 + I * 4) + '" width="' + N(Bw) + '" height="' + N(Bh) + '"' + RoundedAttr() + A + '/>';
                    exit(Result);
                end;
            'doc':
                exit(Wave(W, H, A));
            'tag-doc':
                exit(Wave(W, H, A) + '<path d="M' + N(W / 2 - 12) + ',' + N(H / 2 - 14) + 'L' + N(W / 2) + ',' + N(H / 2 - 26) + '" fill="none"' + LineAttr + '/>');
            'lin-doc':
                exit(Wave(W, H, A) + '<path d="M' + N(-W / 2 + 8) + ',' + N(-H / 2) + 'V' + N(H / 2 - 6) + '" fill="none"' + LineAttr + '/>');
            'docs':
                begin
                    for I := 0 to 2 do
                        Result += '<g transform="translate(' + MText.IntText((1 - I) * 4) + ',' + MText.IntText((I - 1) * 4) + ')">' + Wave(W - 8, H - 8, A) + '</g>';
                    exit(Result);
                end;
            'flag':
                begin
                    X := W / 2;
                    Y := H / 2 - 8;
                    Q := W / 4;
                    exit('<path d="M' + N(-X) + ',' + N(-Y) + 'q' + N(Q) + ',-10 ' + N(2 * Q) + ',0t' + N(2 * Q) + ',0V' + N(Y) + 'q' + N(-Q) + ',10 ' + N(-2 * Q) + ',0t' + N(-2 * Q) + ',0Z"' + A + '/>');
                end;
            'datastore':
                exit(RectSvg(W, H, A.Replace('stroke="var(--_b)"', 'stroke="none"'), '') + '<path d="M' + N(-W / 2) + ',' + N(-H / 2) + 'H' + N(W / 2) + 'M' + N(-W / 2) + ',' + N(H / 2) + 'H' + N(W / 2) + '" fill="none"' + LineAttr + '/>');
            'folder':
                begin
                    X := W / 2;
                    Y := H / 2;
                    Tab := MText.MinDec(W * 0.4, 48);
                    exit(PathSvg('M' + N(-X) + ',' + N(-Y) + 'H' + N(-X + Tab) + 'L' + N(-X + Tab + 8) + ',' + N(-Y + 8) + 'H' + N(X) + 'V' + N(Y) + 'H' + N(-X) + 'Z', A));
                end;
            'bucket':
                begin
                    X := W / 2;
                    Y := H / 2;
                    Ry := 5;
                    Taper := H / 6;
                    exit(PathSvg('M' + N(-X) + ',' + N(-Y + Ry) + 'A' + N(X) + ',' + N(Ry) + ' 0 0 1 ' + N(X) + ',' + N(-Y + Ry) + 'L' + N(X - Taper) + ',' + N(Y - Ry) + 'A' + N(X - Taper) + ',' + N(Ry) + ' 0 0 1 ' + N(-X + Taper) + ',' + N(Y - Ry) + 'Z', A) +
                         '<path d="M' + N(-X) + ',' + N(-Y + Ry) + 'A' + N(X) + ',' + N(Ry) + ' 0 0 0 ' + N(X) + ',' + N(-Y + Ry) + '" fill="none"' + LineAttr + '/>');
                end;
            'console':
                exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-W / 2) + ',' + N(-H / 2 + 12) + 'H' + N(W / 2) + 'M' + N(-W / 2 + 7) + ',' + N(-H / 2 + 4) + 'l3,2.5l-3,2.5M' + N(-W / 2 + 13) + ',' + N(-H / 2 + 9) + 'h4" fill="none"' + LineAttr + '/>');
            'browser':
                begin
                    Result := RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(-W / 2) + ',' + N(-H / 2 + 12) + 'H' + N(W / 2) + '" fill="none"' + LineAttr + '/>';
                    for I := 0 to 2 do
                        Result += '<circle cx="' + N(-W / 2 + 8 + I * 7) + '" cy="' + N(-H / 2 + 6) + '" r="1.5" fill="none"' + LineAttr + '/>';
                    exit(Result);
                end;
            'person':
                begin
                    Top := -H / 2;
                    exit('<rect x="' + N(-W / 2) + '" y="' + N(Top + 26) + '" width="' + N(W) + '" height="' + N(H - 26) + '" rx="12"' + A + '/><circle cy="' + N(Top + 14) + '" r="13"' + A + '/>');
                end;
            'bang':
                begin
                    for I := 0 to 27 do begin
                        Angle := (Math.Pi() * I) / 14 - Math.Pi() / 2;
                        K := 0.82;
                        if I mod 2 = 0 then
                            K := 1;
                        Pts(Points, Math.Cos(Angle) * (W / 2) * K, Math.Sin(Angle) * (H / 2) * K);
                    end;
                    exit(Poly(Points, A));
                end;
            'cloud':
                begin
                    X := W / 2;
                    Y := H / 2;
                    R := Y * 0.55;
                    exit(PathSvg('M' + N(-X + R) + ',' + N(Y) + 'A' + N(R) + ',' + N(R) + ' 0 0 1 ' + N(-X + R * 0.6) + ',' + N(-Y * 0.1) +
                                 'A' + N(X * 0.42) + ',' + N(Y * 0.7) + ' 0 0 1 ' + N(-X * 0.1) + ',' + N(-Y * 0.72) +
                                 'A' + N(X * 0.4) + ',' + N(Y * 0.62) + ' 0 0 1 ' + N(X * 0.62) + ',' + N(-Y * 0.42) +
                                 'A' + N(R * 1.05) + ',' + N(R * 1.05) + ' 0 0 1 ' + N(X - R) + ',' + N(Y) + 'Z', A));
                end;
            'brace':
                exit(RectSvg(W, H, ' fill="none" stroke="none"', '') + Brace(-W / 2 + 12, H, -1, LineAttr));
            'brace-r':
                exit(RectSvg(W, H, ' fill="none" stroke="none"', '') + Brace(W / 2 - 12, H, 1, LineAttr));
            'braces':
                exit(RectSvg(W, H, ' fill="none" stroke="none"', '') + Brace(-W / 2 + 12, H, -1, LineAttr) + Brace(W / 2 - 12, H, 1, LineAttr));
            'bolt':
                begin
                    Pts(Points, W * 0.15, -H / 2);
                    Pts(Points, -W / 2, H * 0.08);
                    Pts(Points, -W * 0.05, H * 0.08);
                    Pts(Points, -W * 0.15, H / 2);
                    Pts(Points, W / 2, -H * 0.08);
                    Pts(Points, W * 0.05, -H * 0.08);
                    exit(Poly(Points, A));
                end;
            'curv-trap':
                begin
                    X := W / 2;
                    Y := H / 2;
                    K := H * 0.3;
                    exit(PathSvg('M' + N(-X + K) + ',' + N(-Y) + 'H' + N(X - K) + 'A' + N(K) + ',' + N(Y) + ' 0 0 1 ' + N(X - K) + ',' + N(Y) + 'H' + N(-X + K) + 'L' + N(-X) + ',0Z', A));
                end;
            'bow-rect':
                begin
                    X := W / 2;
                    Y := H / 2;
                    K := H * 0.2;
                    exit(PathSvg('M' + N(-X + K) + ',' + N(-Y) + 'H' + N(X) + 'A' + N(K) + ',' + N(Y) + ' 0 0 0 ' + N(X) + ',' + N(Y) + 'H' + N(-X + K) + 'A' + N(K) + ',' + N(Y) + ' 0 0 1 ' + N(-X + K) + ',' + N(-Y) + 'Z', A));
                end;
            'tag-rect':
                exit(RectSvg(W, H, A, RoundedAttr()) + '<path d="M' + N(W / 2 - 12) + ',' + N(H / 2) + 'L' + N(W / 2) + ',' + N(H / 2 - 12) + '" fill="none"' + LineAttr + '/>');
            'collapsedGroup':
                exit('<rect x="' + N(-W / 2 + 6) + '" y="' + N(-H / 2 + 8) + '" width="' + N(W - 12) + '" height="' + N(H - 8) + '"' + RoundedAttr() + A + '/>' +
                     '<rect x="' + N(-W / 2) + '" y="' + N(-H / 2) + '" width="' + N(W) + '" height="' + N(H - 4) + '"' + RoundedAttr() + A + '/>');
        end;
        exit(RectSvg(W, H, A, RoundedAttr()));
    end;

    // ---------------------------------------------------------------- outline

    /// <summary>Distance from the bounding box to the outline on a side (0 top, 1 right, 2 bottom, 3 left), T from the middle of the side.</summary>
    procedure Inset(Shape: Text; W: Decimal; H: Decimal; Side: Integer; T: Decimal): Decimal
    var
        Odd: Boolean;
    begin
        Odd := Side mod 2 = 1;
        case Shape of
            'circle', 'dbl-circ', 'ellipse', 'sm-circ', 'f-circ', 'fr-circ', 'cross-circ':
                begin
                    if Odd then
                        exit(Bulge(T, H / 2, W / 2));
                    exit(Bulge(T, W / 2, H / 2));
                end;
            'cyl', 'lin-cyl':
                begin
                    if Odd then
                        exit(0);
                    exit(Bulge(T, W / 2, CylRy(W)));
                end;
            'stadium':
                begin
                    if Odd then
                        exit(Bulge(T, H / 2, H / 2));
                    exit(0);
                end;
            'diam':
                begin
                    if Odd then begin
                        if H = 0 then
                            exit(0);
                        exit((Abs(T) * W) / H);
                    end;
                    if W = 0 then
                        exit(0);
                    exit((Abs(T) * H) / W);
                end;
            'hex':
                begin
                    if Odd then
                        exit(Abs(T) / 2);
                    exit(0);
                end;
            'odd':
                begin
                    if Side = 3 then
                        exit(H / 4);
                    exit(0);
                end;
            'lean-r', 'lean-l', 'trap-b', 'trap-t':
                begin
                    if Odd then
                        exit(H / 8);
                    exit(0);
                end;
            'tri', 'flip-tri', 'bolt':
                begin
                    if Odd then
                        exit(W / 4);
                    exit(0);
                end;
            'sl-rect':
                begin
                    if Side = 0 then
                        exit(5);
                    exit(0);
                end;
            'hourglass':
                begin
                    if Odd then
                        exit(W / 2);
                    exit(0);
                end;
            'doc', 'docs', 'tag-doc', 'lin-doc':
                begin
                    if Side = 2 then
                        exit(10);
                    exit(0);
                end;
            'flag':
                begin
                    if Odd then
                        exit(0);
                    exit(8);
                end;
            'bucket':
                begin
                    if Odd then
                        exit(H / 12);
                    exit(0);
                end;
            'bang':
                exit(3);
            'cloud':
                begin
                    if Odd then
                        exit(2);
                    exit(1);
                end;
            'bow-rect':
                begin
                    if Side = 1 then
                        exit(H * 0.2);
                    exit(0);
                end;
        end;
        exit(0);
    end;

    /// <summary>How much of a side edges may spread along, when the flow runs down or, if Sideways, across.</summary>
    procedure Span(Shape: Text; W: Decimal; H: Decimal; Sideways: Boolean): Decimal
    var
        Along: Decimal;
        Result: Decimal;
    begin
        Init();
        Along := W;
        if Sideways then
            Along := H;
        case Shape of
            'rect', 'rounded', 'fr-rect', 'text', 'notch-rect', 'lin-rect', 'div-rect', 'win-pane', 'notch-pent', 'datastore', 'console', 'browser', 'tag-rect':
                Result := Along - 2 * Corner;
            'circle', 'dbl-circ', 'ellipse', 'sm-circ', 'f-circ', 'fr-circ', 'cross-circ', 'diam':
                Result := Along * 0.6;
            'stadium':
                if Sideways then
                    Result := H * 0.6
                else
                    Result := W - H;
            'cyl':
                if Sideways then
                    Result := H - 2 * Corner - 12
                else
                    Result := W * 0.6;
            'lin-cyl':
                if Sideways then
                    Result := H - 2 * Corner - 20
                else
                    Result := W * 0.6;
            'hex':
                if Sideways then
                    Result := H * 0.5
                else
                    Result := W - H / 2 - Corner;
            'odd':
                if Sideways then
                    Result := 0
                else
                    Result := W - 2 * Corner;
            'lean-r', 'lean-l', 'trap-b', 'trap-t':
                if Sideways then
                    Result := 0
                else
                    Result := W - 2 * (H / 4) - 2 * Corner;
            'fork':
                Result := Along - 8;
            'st-rect':
                Result := Along - 2 * Corner - 8;
            else
                Result := 0;
        end;
        exit(MText.MaxDec(0, Result));
    end;
}
