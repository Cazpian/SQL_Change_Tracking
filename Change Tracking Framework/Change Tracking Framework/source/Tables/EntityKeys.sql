CREATE TABLE [source].[EntityKeys] (
    [EntityKeyID] INT            IDENTITY (1, 1) NOT NULL,
    [EntityID]    INT            NOT NULL,
    [Name]        NVARCHAR (150) NOT NULL,
    CONSTRAINT [PK_EntityKeys] PRIMARY KEY CLUSTERED ([EntityKeyID] ASC),
    CONSTRAINT [FK_EntityKeys_Entities] FOREIGN KEY ([EntityID]) REFERENCES [source].[Entities] ([EntityID])
);

