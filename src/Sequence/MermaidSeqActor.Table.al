/// <summary>
/// A sequence diagram participant, as pele's SeqActor holds it, plus the column the renderer gives it.
/// </summary>
table 68902 "Mermaid Seq Actor"
{
    Caption = 'Mermaid Seq Actor';
    TableType = Temporary;
    DataClassification = SystemMetadata;
    Access = Internal;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
        }
        field(2; Id; Text[250])
        {
            Caption = 'Id';
        }
        field(3; Description; Text[2048])
        {
            Caption = 'Description';
        }
        field(4; Kind; Text[20])
        {
            Caption = 'Kind';
        }
        field(5; "Box No."; Integer)
        {
            Caption = 'Box No.';
        }
        field(6; Wrap; Boolean)
        {
            Caption = 'Wrap';
        }
        field(7; "Created At"; Integer)
        {
            Caption = 'Created At';
        }
        field(8; "Destroyed At"; Integer)
        {
            Caption = 'Destroyed At';
        }
        field(9; "Class Name"; Text[250])
        {
            Caption = 'Class Name';
        }
        field(20; X; Decimal)
        {
            Caption = 'X';
        }
        field(21; Width; Decimal)
        {
            Caption = 'Width';
        }
        field(22; Height; Decimal)
        {
            Caption = 'Height';
        }
        field(23; Top; Decimal)
        {
            Caption = 'Top';
        }
        field(24; "Life Start"; Decimal)
        {
            Caption = 'Life Start';
        }
        field(25; "Life End"; Decimal)
        {
            Caption = 'Life End';
        }
        field(26; "Create Line"; Integer)
        {
            Caption = 'Create Line';
        }
        field(27; "Destroy Line"; Integer)
        {
            Caption = 'Destroy Line';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(ById; Id)
        {
        }
    }
}
