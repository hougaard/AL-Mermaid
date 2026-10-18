/// <summary>
/// One entry of a sequence diagram: a message, note, block start or end, activation or autonumber
/// setting, as pele's SeqMessage holds it, plus what the renderer works out for it.
/// </summary>
table 68903 "Mermaid Seq Message"
{
    Caption = 'Mermaid Seq Message';
    TableType = Temporary;
    DataClassification = SystemMetadata;
    Access = Internal;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
        }
        field(2; "Line Type"; Integer)
        {
            Caption = 'Line Type';
        }
        field(3; "From Id"; Text[250])
        {
            Caption = 'From Id';
        }
        field(4; "To Id"; Text[250])
        {
            Caption = 'To Id';
        }
        field(5; Message; Text[2048])
        {
            Caption = 'Message';
        }
        field(6; Placement; Integer)
        {
            Caption = 'Placement';
        }
        field(7; Wrap; Boolean)
        {
            Caption = 'Wrap';
        }
        field(8; "Number Start"; Decimal)
        {
            Caption = 'Number Start';
        }
        field(9; "Number Step"; Decimal)
        {
            Caption = 'Number Step';
        }
        field(10; "Number Visible"; Boolean)
        {
            Caption = 'Number Visible';
        }
        field(20; "View Kind"; Integer)
        {
            Caption = 'View Kind';
        }
        field(21; "Col A"; Integer)
        {
            Caption = 'Col A';
        }
        field(22; "Col B"; Integer)
        {
            Caption = 'Col B';
        }
        field(23; "View X"; Decimal)
        {
            Caption = 'View X';
        }
        field(24; "View W"; Decimal)
        {
            Caption = 'View W';
        }
        field(25; "Wrap Width"; Decimal)
        {
            Caption = 'Wrap Width';
        }
        field(26; Number; Decimal)
        {
            Caption = 'Number';
        }
        field(27; "Number Shown"; Boolean)
        {
            Caption = 'Number Shown';
        }
        field(28; "Frame No."; Integer)
        {
            Caption = 'Frame No.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }
}
