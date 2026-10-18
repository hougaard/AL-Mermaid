/// <summary>
/// A flowchart vertex or subgraph, as pele's FlowNode / FlowSubgraph / GraphNode hold them,
/// plus the size and place the layout gives it.
/// </summary>
table 68900 "Mermaid Flow Node"
{
    Caption = 'Mermaid Flow Node';
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
        field(3; "Label"; Text[2048])
        {
            Caption = 'Label';
        }
        field(4; "Label Type"; Text[20])
        {
            Caption = 'Label Type';
        }
        field(5; "Shape"; Text[50])
        {
            Caption = 'Shape';
        }
        field(6; Styles; Text[2048])
        {
            Caption = 'Styles';
        }
        field(7; Classes; Text[2048])
        {
            Caption = 'Classes';
        }
        field(8; Link; Text[2048])
        {
            Caption = 'Link';
        }
        field(9; "Link Target"; Text[30])
        {
            Caption = 'Link Target';
        }
        field(10; Tooltip; Text[2048])
        {
            Caption = 'Tooltip';
        }
        field(11; "Is Group"; Boolean)
        {
            Caption = 'Is Group';
        }
        field(12; "Parent Id"; Text[250])
        {
            Caption = 'Parent Id';
        }
        field(13; Direction; Text[10])
        {
            Caption = 'Direction';
        }
        field(14; "Has Label"; Boolean)
        {
            Caption = 'Has Label';
        }
        field(15; Callback; Text[250])
        {
            Caption = 'Callback';
        }
        field(16; "Callback Args"; Text[2048])
        {
            Caption = 'Callback Args';
        }
        field(20; "Layout Index"; Integer)
        {
            Caption = 'Layout Index';
        }
        field(21; Width; Decimal)
        {
            Caption = 'Width';
        }
        field(22; Height; Decimal)
        {
            Caption = 'Height';
        }
        field(23; "Label Dy"; Decimal)
        {
            Caption = 'Label Dy';
        }
        field(24; "Drawn Width"; Decimal)
        {
            Caption = 'Drawn Width';
        }
        field(25; "Drawn Height"; Decimal)
        {
            Caption = 'Drawn Height';
        }
        field(26; X; Decimal)
        {
            Caption = 'X';
        }
        field(27; Y; Decimal)
        {
            Caption = 'Y';
        }
        field(28; Loops; Integer)
        {
            Caption = 'Loops';
        }
        field(29; "Canonical Shape"; Text[50])
        {
            Caption = 'Canonical Shape';
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
