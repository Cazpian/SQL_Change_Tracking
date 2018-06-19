CREATE TABLE [change].[ItemLog] (
    [ItemLogID]          BIGINT          IDENTITY (1, 1) NOT NULL,
    [EntityVersionLogID] INT             NOT NULL,
    [Version]            BIGINT          NOT NULL,
    [Operation]          NCHAR (1)       NOT NULL,
    [Context]            VARBINARY (128) NULL,
    [ID]                 XML             NOT NULL,
    CONSTRAINT [PK_EntityChangeLog] PRIMARY KEY CLUSTERED ([ItemLogID] ASC),
    CONSTRAINT [FK_ItemLog_EntityVersionLog] FOREIGN KEY ([EntityVersionLogID]) REFERENCES [change].[EntityVersionLog] ([EntityVersionLogID])
);

