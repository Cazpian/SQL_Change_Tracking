
create function [source].[get_primary_key_columns]
(	
	@entity_id	int
)
returns nvarchar(200) 
as
begin

	return (
		select stuff((
			select ', ' + [keys].[Name]
			from  [source].[EntityKeys] as [keys]
			where [keys].[EntityID] = @entity_id
			for xml path('')
		), 1, 2, '')); 

end 
