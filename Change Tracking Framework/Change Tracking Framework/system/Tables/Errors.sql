CREATE TABLE [system].[Errors] (
    [ErrorID]         INT            IDENTITY (1, 1) NOT NULL,
    [Number]          INT            NULL,
    [Description]     NVARCHAR (800) NULL,
    [DateTime]        DATETIME       NULL,
    [StoredProcedure] NVARCHAR (255) NULL,
    [LineNumber]      INT            NULL,
    [UserName]        NVARCHAR (255) NULL,
    [MachineName]     NVARCHAR (255) NULL,
    [xml]             XML            NULL,
    CONSTRAINT [PK_Errors_ErrorsID] PRIMARY KEY CLUSTERED ([ErrorID] ASC)
);

