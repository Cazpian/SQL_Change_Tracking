create function [system].[udf_split]
( 
    @pInString		varchar(500),
    @pInDeliminator char(1)
)
    returns @results table
    (
        [index]		[int]					not null primary key,
        [part]		[varchar](550)			not null unique		,
		[alpha]		[varchar](2)			not null unique
    )
as
    begin

		-- holds the current identity for insert.
		-----------------------------------------
		declare @index	int
		declare @bit	varchar(100)
		
		set @index = 0

        -- check to see if the delimiter is contained within the string
        -----------------------------------------------------------
        while charindex(@pInDeliminator, @pInString) > 0
            begin
              
                -- get the component part
                --------------------------
                select	@bit = left(@pInString, charindex(@pInDeliminator, @pInString) - 1)

                -- check to see if item already in list
                ---------------------------------------
                if not exists ( select top 1 1 
								from	@results as [results]
								where	[results].[part] = @bit )
					begin
						
						-- increment index
						------------------
						set @index	= @index + 1
						
						-- add item to list
						-------------------
						insert into @results ([index],[part],[alpha])
						select	@index, rtrim(ltrim(@bit)), char(65+(@index/26)) + char(64+(@index%26))
					end
								               
                -- reset the string to exclude the component
                --------------------------------------------
                set @pInString = rtrim(ltrim(substring(@pInString, charindex(@pInDeliminator, @pInString) + 1, (len(@pInString) - charindex(@pInDeliminator, @pInString)))))
                
            end
            
        -- increment index for last component
        -------------------------------------
        set @index = @index + 1
            
        -- check for remainder
        ----------------------
        if (len(@pInString) > 0) 
             insert into @results ([index],[part],[alpha])
                select	@index, @pInString, char(65+(@index/26)) + char(64+(@index%26))
                where	not exists ( select top 1 1
									 from	@results as [results]
									 where	[results].[part] = @pInString
									)
            
    return  
end
