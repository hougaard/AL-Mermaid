/// <summary>
/// A flowchart link, as pele's FlowEdge / GraphEdge hold it.
/// </summary>
table 68901 "Mermaid Flow Edge"
{
    Caption = 'Mermaid Flow Edge';
    TableType = Temporary;
    DataClassification = SystemMetadata;
    Access = Internal;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
        }
        field(2; "Start Id"; Text[250])
        {
            Caption = 'Start Id';
        }
        field(3; "End Id"; Text[250])
        {
            Caption = 'End Id';
        }
        field(4; "Arrow Type"; Text[30])
        {
            Caption = 'Arrow Type';
        }
        field(5; Stroke; Text[20])
        {
            Caption = 'Stroke';
        }
        field(6; Length; Integer)
        {
            Caption = 'Length';
        }
        field(7; "Label"; Text[2048])
        {
            Caption = 'Label';
        }
        field(8; "Label Type"; Text[20])
        {
            Caption = 'Label Type';
        }
        field(9; Styles; Text[2048])
        {
            Caption = 'Styles';
        }
        field(10; Classes; Text[250])
        {
            Caption = 'Classes';
        }
        field(11; "Edge Id"; Text[250])
        {
            Caption = 'Edge Id';
        }
        field(12; "User Defined Id"; Boolean)
        {
            Caption = 'User Defined Id';
        }
        field(13; Interpolate; Text[30])
        {
            Caption = 'Interpolate';
        }
        field(14; "Has Style"; Boolean)
        {
            Caption = 'Has Style';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(ById; "Edge Id")
        {
        }
    }
}
