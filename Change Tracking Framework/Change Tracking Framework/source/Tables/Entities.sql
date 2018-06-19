CREATE TABLE [source].[Entities] (
    [EntityID]    INT            IDENTITY (1, 1) NOT NULL,
    [AuthorityID] INT            NOT NULL,
    [Name]        NVARCHAR (150) NOT NULL,
    [Schema]      NVARCHAR (150) NOT NULL,
    [Active]      BIT            CONSTRAINT [DF_Entities_Active] DEFAULT ((0)) NULL,
    CONSTRAINT [pk_source_entities] PRIMARY KEY CLUSTERED ([EntityID] ASC)
);

