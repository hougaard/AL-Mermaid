/// <summary>
/// Shared text helpers ported from pele: character classes (util/chars.ts), entity decoding
/// (text/entities.ts), XML escaping and number formatting (svg/builder.ts), the Arial width
/// table (text/measurer.ts, text/metrics.ts) and the render options of one render call.
/// </summary>
codeunit 68902 "Mermaid Text"
{
    Access = Internal;
    SingleInstance = true;

    var
        RegularWidths: List of [Integer];
        BoldWidths: List of [Integer];
        NamedEntities: Dictionary of [Text, Integer];
        OptIdPrefix: Text;
        OptFontFamily: Text;
        OptFontSize: Decimal;
        OptResponsive: Boolean;
        OptionsSet: Boolean;
        // Advance widths of printable ASCII in thousandths of an em, two base-36 digits each (Arial).
        RegularMetricsTok: Label '7q7q9vfgfgopij5b9999atg87q997q7qfgfgfgfgfgfgfgfgfgfg7q7qg8g8g8fgs7ijijk2k2ijgzlmk27qdwijfgn5k2lmijlmk2ijgzk2ijq8ijijgz7q7q7qd1fg99fgfgdwfgfg7qfgfg6666dw66n5fgfgfgfg99dw7qfgdwk2dwdwdw9a789ag8', Locked = true;
        BoldMetricsTok: Label '7q99d6fgfgopk26m9999atg87q997q7qfgfgfgfgfgfgfgfgfgfg9999g8g8g8gzr3k2k2k2k2ijgzlmk27qfgk2gzn5k2lmijlmk2ijgzk2ijq8ijijgz997q99g8fg99fggzfggzfg99gzgz7q7qfg7qopgzgzgzgzatfg99gzfglmfgfgdwat7satg8', Locked = true;

    // ---------------------------------------------------------------- render options

    procedure SetOptions(IdPrefix: Text; FontFamily: Text; FontSize: Decimal; Responsive: Boolean)
    begin
        OptIdPrefix := IdPrefix;
        OptFontFamily := FontFamily;
        OptFontSize := FontSize;
        OptResponsive := Responsive;
        OptionsSet := true;
    end;

    procedure IdPrefix(): Text
    begin
        if not OptionsSet or (OptIdPrefix = '') then
            exit('pele');
        exit(OptIdPrefix);
    end;

    procedure FontFamily(): Text
    begin
        exit(OptFontFamily);
    end;

    procedure FontSize(): Decimal
    begin
        if not OptionsSet or (OptFontSize <= 0) then
            exit(16);
        exit(OptFontSize);
    end;

    procedure Responsive(): Boolean
    begin
        if not OptionsSet then
            exit(true);
        exit(OptResponsive);
    end;

    // ---------------------------------------------------------------- styles (bit flags)

    procedure StyleBold(): Integer
    begin
        exit(1);
    end;

    procedure StyleItalic(): Integer
    begin
        exit(2);
    end;

    procedure StyleMono(): Integer
    begin
        exit(4);
    end;

    procedure HasStyle(StyleValue: Integer; Bit: Integer): Boolean
    begin
        exit((StyleValue div Bit) mod 2 = 1);
    end;

    procedure AddStyle(StyleValue: Integer; Bit: Integer): Integer
    begin
        if HasStyle(StyleValue, Bit) then
            exit(StyleValue);
        exit(StyleValue + Bit);
    end;

    procedure RemoveStyle(StyleValue: Integer; Bit: Integer): Integer
    begin
        if HasStyle(StyleValue, Bit) then
            exit(StyleValue - Bit);
        exit(StyleValue);
    end;

    /// <summary>The bits of A that are also set in B.</summary>
    procedure CommonStyle(A: Integer; B: Integer): Integer
    var
        Result: Integer;
    begin
        if HasStyle(A, 1) and HasStyle(B, 1) then
            Result += 1;
        if HasStyle(A, 2) and HasStyle(B, 2) then
            Result += 2;
        if HasStyle(A, 4) and HasStyle(B, 4) then
            Result += 4;
        exit(Result);
    end;

    // ---------------------------------------------------------------- characters

    /// <summary>The UTF-16 code unit at a 1-based position, or -1 past either end.</summary>
    procedure CharAt(Value: Text; Pos: Integer): Integer
    begin
        if (Pos < 1) or (Pos > StrLen(Value)) then
            exit(-1);
        exit(Value[Pos]);
    end;

    procedure FromCode(CodePoint: Integer): Text
    var
        Result: Text;
    begin
        if CodePoint < 65536 then begin
            Result := ' ';
            Result[1] := CodePoint;
            exit(Result);
        end;
        CodePoint -= 65536;
        Result := '  ';
        Result[1] := 55296 + (CodePoint div 1024);
        Result[2] := 56320 + (CodePoint mod 1024);
        exit(Result);
    end;

    procedure LF(): Text
    begin
        exit(FromCode(10));
    end;

    procedure CR(): Text
    begin
        exit(FromCode(13));
    end;

    /// <summary>Whitespace as JavaScript's \s sees it.</summary>
    procedure IsSpace(C: Integer): Boolean
    begin
        if C < 0 then
            exit(false);
        if C < 128 then
            exit((C = 32) or ((C >= 9) and (C <= 13)));
        exit((C = 160) or (C = 5760) or ((C >= 8192) and (C <= 8202)) or (C = 8232) or (C = 8233) or
             (C = 8239) or (C = 8287) or (C = 12288) or (C = 65279));
    end;

    procedure IsBlank(C: Integer): Boolean
    begin
        exit((C = 32) or (C = 9));
    end;

    procedure IsLineEnd(C: Integer): Boolean
    begin
        exit((C = 10) or (C = 13) or (C = 8232) or (C = 8233));
    end;

    procedure IsDigit(C: Integer): Boolean
    begin
        exit((C >= 48) and (C <= 57));
    end;

    procedure IsLetter(C: Integer): Boolean
    begin
        exit(((C >= 65) and (C <= 90)) or ((C >= 97) and (C <= 122)));
    end;

    procedure IsHex(C: Integer): Boolean
    begin
        exit(IsDigit(C) or ((C >= 65) and (C <= 70)) or ((C >= 97) and (C <= 102)));
    end;

    /// <summary>A character of JavaScript's \w.</summary>
    procedure IsWord(C: Integer): Boolean
    begin
        exit(IsDigit(C) or IsLetter(C) or (C = 95));
    end;

    /// <summary>An approximation of a Unicode letter outside ASCII (pele uses generated tables).</summary>
    procedure IsUnicodeLetter(C: Integer): Boolean
    begin
        if C < 170 then
            exit(false);
        if (C = 215) or (C = 247) then
            exit(false);
        if IsSpace(C) then
            exit(false);
        // General punctuation, symbols, arrows, box drawing, CJK punctuation, private use, specials.
        if ((C >= 8192) and (C <= 11263)) or ((C >= 12288) and (C <= 12351)) or ((C >= 57344) and (C <= 63743)) or (C >= 65520) then
            exit(false);
        exit(true);
    end;

    // ---------------------------------------------------------------- strings

    /// <summary>1-based position of Sub in Value at or after From, or 0.</summary>
    procedure IndexOfFrom(Value: Text; Sub: Text; From: Integer): Integer
    var
        Pos: Integer;
    begin
        if From < 1 then
            From := 1;
        if From > StrLen(Value) then
            exit(0);
        if From = 1 then
            exit(StrPos(Value, Sub));
        Pos := StrPos(CopyStr(Value, From), Sub);
        if Pos = 0 then
            exit(0);
        exit(Pos + From - 1);
    end;

    procedure LastIndexOf(Value: Text; Sub: Text): Integer
    var
        Pos: Integer;
        Next: Integer;
    begin
        Pos := 0;
        Next := IndexOfFrom(Value, Sub, 1);
        while Next > 0 do begin
            Pos := Next;
            Next := IndexOfFrom(Value, Sub, Next + 1);
        end;
        exit(Pos);
    end;

    procedure StartsWithAt(Value: Text; Sub: Text; Pos: Integer): Boolean
    begin
        if (Pos < 1) or (Pos + StrLen(Sub) - 1 > StrLen(Value)) then
            exit(false);
        exit(CopyStr(Value, Pos, StrLen(Sub)) = Sub);
    end;

    /// <summary>The characters from FromPos up to, not including, ToPosExclusive (1-based).</summary>
    procedure Substr(Value: Text; FromPos: Integer; ToPosExclusive: Integer): Text
    begin
        if FromPos < 1 then
            FromPos := 1;
        if ToPosExclusive <= FromPos then
            exit('');
        exit(CopyStr(Value, FromPos, ToPosExclusive - FromPos));
    end;

    procedure RepeatText(Value: Text; Times: Integer): Text
    var
        Builder: TextBuilder;
        I: Integer;
    begin
        for I := 1 to Times do
            Builder.Append(Value);
        exit(Builder.ToText());
    end;

    procedure TrimWs(Value: Text): Text
    begin
        exit(TrimEndWs(TrimStartWs(Value)));
    end;

    procedure TrimStartWs(Value: Text): Text
    var
        I: Integer;
    begin
        I := 1;
        while IsSpace(CharAt(Value, I)) do
            I += 1;
        if I = 1 then
            exit(Value);
        exit(CopyStr(Value, I));
    end;

    procedure TrimEndWs(Value: Text): Text
    var
        I: Integer;
    begin
        I := StrLen(Value);
        while IsSpace(CharAt(Value, I)) do
            I -= 1;
        if I = StrLen(Value) then
            exit(Value);
        if I <= 0 then
            exit('');
        exit(CopyStr(Value, 1, I));
    end;

    procedure IsBlankText(Value: Text): Boolean
    begin
        exit(TrimWs(Value) = '');
    end;

    procedure ContainsWs(Value: Text): Boolean
    var
        I: Integer;
    begin
        for I := 1 to StrLen(Value) do
            if IsSpace(Value[I]) then
                exit(true);
        exit(false);
    end;

    procedure IntText(Value: Integer): Text
    begin
        exit(Format(Value, 0, 9));
    end;

    procedure DecText(Value: Decimal): Text
    var
        Result: Text;
    begin
        Result := Format(Value, 0, 9);
        if StrPos(Result, '.') > 0 then begin
            Result := Result.TrimEnd('0');
            Result := Result.TrimEnd('.');
        end;
        if (Result = '') or (Result = '-0') then
            Result := '0';
        exit(Result);
    end;

    /// <summary>A coordinate with at most two decimals, as pele's num().</summary>
    procedure Num(Value: Decimal): Text
    begin
        exit(DecText(Round(Value, 0.01)));
    end;

    procedure Ceil(Value: Decimal): Integer
    begin
        exit(Round(Value, 1, '>'));
    end;

    procedure Floor(Value: Decimal): Integer
    begin
        exit(Round(Value, 1, '<'));
    end;

    procedure MaxDec(A: Decimal; B: Decimal): Decimal
    begin
        if A > B then
            exit(A);
        exit(B);
    end;

    procedure MinDec(A: Decimal; B: Decimal): Decimal
    begin
        if A < B then
            exit(A);
        exit(B);
    end;

    procedure Sign(Value: Decimal): Decimal
    begin
        if Value > 0 then
            exit(1);
        if Value < 0 then
            exit(-1);
        exit(0);
    end;

    procedure Hypot(A: Decimal; B: Decimal): Decimal
    begin
        exit(Sqrt(A * A + B * B));
    end;

    procedure Sqrt(Value: Decimal): Decimal
    begin
        if Value <= 0 then
            exit(0);
        exit(Power(Value, 0.5));
    end;

    // ---------------------------------------------------------------- XML

    local procedure NeedsEscape(C: Integer): Boolean
    begin
        exit((C = 38) or (C = 60) or (C = 62) or (C = 34) or IsXmlControl(C));
    end;

    local procedure IsXmlControl(C: Integer): Boolean
    begin
        exit(((C >= 0) and (C <= 8)) or (C = 11) or (C = 12) or ((C >= 14) and (C <= 31)) or (C = 127));
    end;

    /// <summary>Escapes text for XML and drops the control characters XML does not allow.</summary>
    procedure Esc(Value: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        C: Integer;
        Needed: Boolean;
    begin
        for I := 1 to StrLen(Value) do
            if not Needed then
                if NeedsEscape(Value[I]) then
                    Needed := true;
        if not Needed then
            exit(Value);
        for I := 1 to StrLen(Value) do begin
            C := Value[I];
            case C of
                38:
                    Builder.Append('&amp;');
                60:
                    Builder.Append('&lt;');
                62:
                    Builder.Append('&gt;');
                34:
                    Builder.Append('&quot;');
                else
                    if not IsXmlControl(C) then
                        Builder.Append(CopyStr(Value, I, 1));
            end;
        end;
        exit(Builder.ToText());
    end;

    /// <summary>Escapes text that is only ever read as text, after turning entity codes into characters.</summary>
    procedure EscText(Value: Text): Text
    begin
        exit(Esc(DecodeEntities(Value)));
    end;

    // ---------------------------------------------------------------- measuring

    local procedure LoadMetrics()
    begin
        if RegularWidths.Count() > 0 then
            exit;
        Unpack(RegularMetricsTok, RegularWidths);
        Unpack(BoldMetricsTok, BoldWidths);
    end;

    local procedure Unpack(Packed: Text; var Widths: List of [Integer])
    var
        I: Integer;
    begin
        for I := 0 to 94 do
            Widths.Add(Base36(CharAt(Packed, I * 2 + 1)) * 36 + Base36(CharAt(Packed, I * 2 + 2)));
    end;

    local procedure Base36(C: Integer): Integer
    begin
        if IsDigit(C) then
            exit(C - 48);
        if (C >= 97) and (C <= 122) then
            exit(C - 87);
        if (C >= 65) and (C <= 90) then
            exit(C - 55);
        exit(0);
    end;

    local procedure IsWide(C: Integer): Boolean
    begin
        exit(((C >= 4352) and (C <= 4447)) or ((C >= 11904) and (C <= 42191)) or ((C >= 44032) and (C <= 55203)) or
             ((C >= 63744) and (C <= 64255)) or ((C >= 65072) and (C <= 65103)) or ((C >= 65280) and (C <= 65376)) or
             ((C >= 65504) and (C <= 65510)) or ((C >= 55296) and (C <= 56319)));
    end;

    local procedure IsZeroWidth(C: Integer): Boolean
    begin
        exit(((C >= 768) and (C <= 879)) or ((C >= 8203) and (C <= 8207)) or ((C >= 56320) and (C <= 57343)) or
             ((C >= 65024) and (C <= 65039)) or (C = 65279));
    end;

    /// <summary>Estimates the width of text from a table of Arial advances (pele's metricsMeasurer).</summary>
    procedure Width(Value: Text; Size: Decimal; StyleValue: Integer): Decimal
    var
        I: Integer;
        C: Integer;
        Units: Integer;
        Mono: Boolean;
        Bold: Boolean;
    begin
        LoadMetrics();
        Mono := HasStyle(StyleValue, StyleMono());
        Bold := HasStyle(StyleValue, StyleBold());
        for I := 1 to StrLen(Value) do begin
            C := Value[I];
            if C >= 32 then
                if C < 127 then begin
                    if Mono then
                        Units += 600
                    else
                        if Bold then
                            Units += BoldWidths.Get(C - 31)
                        else
                            Units += RegularWidths.Get(C - 31);
                end else
                    if not IsZeroWidth(C) then
                        if IsWide(C) then begin
                            if Mono then
                                Units += 1200
                            else
                                Units += 1000;
                        end else
                            if Mono then
                                Units += 600
                            else
                                Units += 580;
        end;
        exit(Units * Size / 1000);
    end;

    // ---------------------------------------------------------------- entities

    procedure PlaceholderOpen(): Text
    begin
        exit(FromCode(64258) + FromCode(176));
    end;

    procedure PlaceholderNumeric(): Text
    begin
        exit(FromCode(176));
    end;

    procedure PlaceholderClose(): Text
    begin
        exit(FromCode(182) + FromCode(223));
    end;

    local procedure LoadEntities()
    begin
        if NamedEntities.Count() > 0 then
            exit;
        AddNamed('amp:38,lt:60,gt:62,quot:34,apos:39,nbsp:160,iexcl:161,cent:162,pound:163,curren:164,yen:165,sect:167,');
        AddNamed('copy:169,laquo:171,not:172,reg:174,deg:176,plusmn:177,sup2:178,sup3:179,micro:181,para:182,middot:183,');
        AddNamed('sup1:185,raquo:187,frac14:188,frac12:189,frac34:190,iquest:191,times:215,divide:247,ndash:8211,mdash:8212,');
        AddNamed('lsquo:8216,rsquo:8217,sbquo:8218,ldquo:8220,rdquo:8221,bdquo:8222,dagger:8224,Dagger:8225,bull:8226,');
        AddNamed('hellip:8230,permil:8240,prime:8242,Prime:8243,lsaquo:8249,rsaquo:8250,euro:8364,trade:8482,larr:8592,');
        AddNamed('uarr:8593,rarr:8594,darr:8595,harr:8596,lArr:8656,uArr:8657,rArr:8658,dArr:8659,hArr:8660,forall:8704,');
        AddNamed('part:8706,exist:8707,empty:8709,nabla:8711,isin:8712,notin:8713,ni:8715,prod:8719,sum:8721,minus:8722,');
        AddNamed('radic:8730,infin:8734,and:8743,or:8744,cap:8745,cup:8746,int:8747,there4:8756,sim:8764,cong:8773,');
        AddNamed('asymp:8776,ne:8800,equiv:8801,le:8804,ge:8805,sub:8834,sup:8835,sube:8838,supe:8839,oplus:8853,otimes:8855,');
        AddNamed('perp:8869,sdot:8901,loz:9674,spades:9824,clubs:9827,hearts:9829,diams:9830,check:10003,cross:10007,');
        AddNamed('equals:61,colon:58,semi:59,num:35,percnt:37,lpar:40,rpar:41,lbrack:91,rbrack:93,lbrace:123,rbrace:125,');
        AddNamed('vert:124,sol:47,bsol:92,quest:63,excl:33,ast:42,plus:43,comma:44,period:46,dollar:36,commat:64,grave:96,');
        AddNamed('hat:94,lowbar:95,tilde:126,Alpha:913,Beta:914,Gamma:915,Delta:916,Epsilon:917,Zeta:918,Eta:919,Theta:920,');
        AddNamed('Iota:921,Kappa:922,Lambda:923,Mu:924,Nu:925,Xi:926,Omicron:927,Pi:928,Rho:929,Sigma:931,Tau:932,');
        AddNamed('Upsilon:933,Phi:934,Chi:935,Psi:936,Omega:937,alpha:945,beta:946,gamma:947,delta:948,epsilon:949,zeta:950,');
        AddNamed('eta:951,theta:952,iota:953,kappa:954,lambda:955,mu:956,nu:957,xi:958,omicron:959,pi:960,rho:961,sigmaf:962,');
        AddNamed('sigma:963,tau:964,upsilon:965,phi:966,chi:967,psi:968,omega:969');
    end;

    local procedure AddNamed(Pairs: Text)
    var
        Pair: Text;
        At: Integer;
        Code: Integer;
    begin
        foreach Pair in Pairs.Split(',') do begin
            At := StrPos(Pair, ':');
            if At > 0 then
                if Evaluate(Code, CopyStr(Pair, At + 1)) then
                    if not NamedEntities.ContainsKey(CopyStr(Pair, 1, At - 1)) then
                        NamedEntities.Add(CopyStr(Pair, 1, At - 1), Code);
        end;
    end;

    procedure LookupEntity(Name: Text; var Result: Text): Boolean
    var
        Code: Integer;
    begin
        LoadEntities();
        if not NamedEntities.Get(Name, Code) then
            exit(false);
        Result := FromCode(Code);
        exit(true);
    end;

    local procedure CodePointText(N: BigInteger; Fallback: Text): Text
    begin
        if (N > 0) and (N <= 1114111) and ((N < 55296) or (N > 57343)) then
            exit(FromCode(N));
        exit(Fallback);
    end;

    /// <summary>Mermaid's placeholders run from the open marker to the close marker, a second degree sign marking a numeric code.</summary>
    local procedure DecodePlaceholders(Value: Text): Text
    var
        Builder: TextBuilder;
        OpenMark: Text;
        LastPos: Integer;
        FromPos: Integer;
        StopPos: Integer;
        Numeric: Boolean;
        Body: Text;
        Raw: Text;
        Decoded: Text;
        N: BigInteger;
        Changed: Boolean;
    begin
        OpenMark := PlaceholderOpen();
        LastPos := 1;
        FromPos := StrPos(Value, OpenMark);
        while FromPos > 0 do begin
            StopPos := IndexOfFrom(Value, FromCode(182), FromPos + 2);
            if StopPos = 0 then
                FromPos := 0
            else begin
                if CharAt(Value, StopPos + 1) = 223 then begin
                    Numeric := CharAt(Value, FromPos + 2) = 176;
                    if Numeric then
                        Body := Substr(Value, FromPos + 3, StopPos)
                    else
                        Body := Substr(Value, FromPos + 2, StopPos);
                    Raw := Substr(Value, FromPos, StopPos + 2);
                    if Numeric then begin
                        if (StrLen(Body) <= 9) and Evaluate(N, Body) then
                            Decoded := CodePointText(N, Raw)
                        else
                            Decoded := Raw;
                    end else
                        if not LookupEntity(Body, Decoded) then
                            Decoded := '&' + Body + ';';
                    Builder.Append(Substr(Value, LastPos, FromPos));
                    Builder.Append(Decoded);
                    LastPos := StopPos + 2;
                    Changed := true;
                end;
                FromPos := IndexOfFrom(Value, OpenMark, StopPos + 1);
            end;
        end;
        if not Changed then
            exit(Value);
        Builder.Append(CopyStr(Value, LastPos));
        exit(Builder.ToText());
    end;

    /// <summary>Turns Mermaid's #35; / #quot; codes (as hidden by EncodeEntities) and HTML entities into characters.</summary>
    procedure DecodeEntities(Value: Text): Text
    var
        Builder: TextBuilder;
        I: Integer;
        J: Integer;
        N: BigInteger;
        Name: Text;
        Decoded: Text;
        Matched: Boolean;
    begin
        if StrPos(Value, PlaceholderClose()) > 0 then
            Value := DecodePlaceholders(Value);
        if StrPos(Value, '&') = 0 then
            exit(Value);
        I := 1;
        while I <= StrLen(Value) do begin
            Matched := false;
            if CharAt(Value, I) = 38 then
                if CharAt(Value, I + 1) = 35 then begin
                    if (CharAt(Value, I + 2) = 120) or (CharAt(Value, I + 2) = 88) then begin
                        J := I + 3;
                        while IsHex(CharAt(Value, J)) do
                            J += 1;
                        if (J > I + 3) and (CharAt(Value, J) = 59) then begin
                            N := HexValue(Substr(Value, I + 3, J));
                            Builder.Append(CodePointText(N, Substr(Value, I, J + 1)));
                            I := J + 1;
                            Matched := true;
                        end;
                    end else begin
                        J := I + 2;
                        while IsDigit(CharAt(Value, J)) do
                            J += 1;
                        if (J > I + 2) and (CharAt(Value, J) = 59) then begin
                            N := -1;
                            if J - I - 2 <= 9 then
                                if not Evaluate(N, Substr(Value, I + 2, J)) then
                                    N := -1;
                            Builder.Append(CodePointText(N, Substr(Value, I, J + 1)));
                            I := J + 1;
                            Matched := true;
                        end;
                    end;
                end else begin
                    J := I + 1;
                    while IsWord(CharAt(Value, J)) do
                        J += 1;
                    if (J > I + 1) and (CharAt(Value, J) = 59) then begin
                        Name := Substr(Value, I + 1, J);
                        if LookupEntity(Name, Decoded) then
                            Builder.Append(Decoded)
                        else
                            Builder.Append(Substr(Value, I, J + 1));
                        I := J + 1;
                        Matched := true;
                    end;
                end;
            if not Matched then begin
                Builder.Append(CopyStr(Value, I, 1));
                I += 1;
            end;
        end;
        exit(Builder.ToText());
    end;

    local procedure HexValue(Digits: Text): BigInteger
    var
        I: Integer;
        C: Integer;
        Result: BigInteger;
    begin
        if StrLen(Digits) > 8 then
            exit(-1);
        for I := 1 to StrLen(Digits) do begin
            C := Digits[I];
            if IsDigit(C) then
                Result := Result * 16 + C - 48
            else
                if C >= 97 then
                    Result := Result * 16 + C - 87
                else
                    Result := Result * 16 + C - 55;
        end;
        exit(Result);
    end;

    // ---------------------------------------------------------------- configuration

    procedure ConfigText(var Config: Dictionary of [Text, Text]; Path: Text; Default: Text): Text
    var
        Value: Text;
    begin
        if Config.Get(Path, Value) then
            exit(Value);
        exit(Default);
    end;

    procedure ConfigNumber(var Config: Dictionary of [Text, Text]; Path: Text; var Value: Decimal): Boolean
    var
        Raw: Text;
    begin
        if not Config.Get(Path, Raw) then
            exit(false);
        exit(Evaluate(Value, Raw, 9));
    end;

    procedure ConfigBool(var Config: Dictionary of [Text, Text]; Path: Text; Default: Boolean): Boolean
    var
        Raw: Text;
    begin
        if not Config.Get(Path, Raw) then
            exit(Default);
        if LowerCase(Raw) = 'true' then
            exit(true);
        if LowerCase(Raw) = 'false' then
            exit(false);
        exit(Default);
    end;

    procedure ConfigHas(var Config: Dictionary of [Text, Text]; Path: Text): Boolean
    begin
        exit(Config.ContainsKey(Path));
    end;

    // ---------------------------------------------------------------- errors

    /// <summary>A syntax error in the shape Mermaid reports it: the line, the source line and a caret under the column.</summary>
    procedure SyntaxError(DiagramType: Text; Src: Text; Offset: Integer; Detail: Text; Lexical: Boolean)
    var
        LineNo: Integer;
        LineStart: Integer;
        LineEnd: Integer;
        Column: Integer;
        I: Integer;
        Snippet: Text;
        Message: Text;
    begin
        LineNo := 1;
        LineStart := 1;
        if Offset < 1 then
            Offset := 1;
        for I := 1 to Offset - 1 do
            if I <= StrLen(Src) then
                if Src[I] = 10 then begin
                    LineNo += 1;
                    LineStart := I + 1;
                end;
        LineEnd := IndexOfFrom(Src, LF(), Offset);
        if LineEnd = 0 then
            LineEnd := StrLen(Src) + 1;
        if LineEnd < LineStart then
            LineEnd := LineStart;
        Column := Offset - LineStart + 1;
        Snippet := Substr(Src, LineStart, LineEnd) + LF() + RepeatText('-', Column - 1) + '^';
        if Lexical then
            Message := 'Lexical error on line ' + IntText(LineNo) + '. Unrecognized text.' + LF() + Snippet
        else
            Message := 'Parse error on line ' + IntText(LineNo) + ':' + LF() + Snippet + LF() + Detail;
        Error(ErrorInfo.Create(Message));
    end;

    procedure Fail(Message: Text)
    begin
        Error(ErrorInfo.Create(Message));
    end;
}
