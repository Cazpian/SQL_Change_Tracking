create function [system].[udf_string_format]
(  
    @pInString		nvarchar(max),
    @pInParameters  nvarchar(max)

)
returns nvarchar(max)
as
begin

	declare replacement_string_cursor cursor fast_forward for  
	select	[params].[index],  
			[params].[part]
	from	[system].[udf_split](@pInParameters, ',') as [params];

	declare @index	int
	declare @part	nvarchar(200)

	open replacement_string_cursor;

	fetch next from replacement_string_cursor into @index, @part;


	while (@@fetch_status = 0)
		begin

			set @pInString = replace(@pInString, formatmessage('{%i}', (@index - 1)), @part)
			fetch next from replacement_string_cursor into @index, @part;

		end

	close  replacement_string_cursor;
	deallocate	replacement_string_cursor;

	return @pInString

end