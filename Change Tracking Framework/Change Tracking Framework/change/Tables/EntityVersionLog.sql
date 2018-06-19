CREATE TABLE [change].[EntityVersionLog] (
    [EntityVersionLogID] INT      IDENTITY (1, 1) NOT NULL,
    [EntityID]           INT      NOT NULL,
    [Version]            INT      NULL,
    [Count]              INT      NOT NULL,
    [Started]            DATETIME NOT NULL,
    [Duration]           INT      NOT NULL,
    CONSTRAINT [PK_ChangeLog] PRIMARY KEY CLUSTERED ([EntityVersionLogID] ASC),
    CONSTRAINT [FK_EntityVersionLog_Entities] FOREIGN KEY ([EntityID]) REFERENCES [source].[Entities] ([EntityID])
);

