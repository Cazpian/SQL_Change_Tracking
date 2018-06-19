CREATE TABLE [source].[Authorities] (
    [AuthorityID]      INT              IDENTITY (1, 1) NOT NULL,
    [Name]             NVARCHAR (150)   NOT NULL,
    [Database]         NVARCHAR (60)    NOT NULL,
    [Server]           NVARCHAR (130)   NOT NULL,
    [EndPoint]         NVARCHAR (130)   NULL,
    [Broker]           UNIQUEIDENTIFIER NULL,
    [RetentionInHours] INT              NULL,
    [Active]           BIT              NOT NULL,
    CONSTRAINT [pk_source_authorities] PRIMARY KEY CLUSTERED ([AuthorityID] ASC)
);

