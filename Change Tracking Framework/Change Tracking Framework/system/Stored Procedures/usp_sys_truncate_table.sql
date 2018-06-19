
create procedure [system].[usp_sys_truncate_table]

	@pInSchema		[varchar](20)		,
	@pInTableName	[varchar](200)

as
	begin

		-- manage transactions and feedback
		-----------------------------------
		set xact_abort, nocount on;

		-- variables for transaction management
		---------------------------------------
		declare @DATA_RESPONSE_SUCCESS		int			= +1
		declare @TRANS_COUNTER				int			= @@TRANCOUNT
		declare @PROCEDURE_NAME				varchar(25) = OBJECT_NAME(@@PROCID) 
		
		begin try

			-- is this procedure outside of a transaction
			--------------------------------------------
			if (@TRANS_COUNTER = 0)
				begin transaction;

			-- holds the logic required to drop and CREATE the references
			-------------------------------------------------------------
			declare @drop_references table
			(
				[index]				[int]			identity(1,1)	not null primary key,
				[statement]			[nvarchar](max)					not null
			)
			declare @create_references table
			(
				[index]				[int]			identity(1,1)	not null primary key,
				[statement]			[nvarchar](max)					not null
			)
			declare @index_max		int
			declare @index			int
				
			-- populate drop statements
			---------------------------
			insert into @drop_references([statement])
			select 'alter table '					+
					quotename([con_schemas].[name]) + 
					'.'								+
					quotename([con_tables].[name])	+ 
					' drop constraint '				+
					quotename([keys].[name])		+
					';'

			from [sys].[foreign_keys] as [keys]

				inner join [sys].[tables] as [ref_tables] 
				on [ref_tables].[object_id] = [keys].[referenced_object_id]

					inner join [sys].[schemas] as [ref_schemas] 
					on [ref_schemas].[schema_id] = [ref_tables].[schema_id]

				inner join [sys].[tables] as [con_tables]
				on [con_tables].[object_id] = [keys].[parent_object_id]

					inner join [sys].[schemas] as [con_schemas] 
					on [con_schemas].[schema_id] = [con_tables].[schema_id]

			where  (([con_tables].[name]	= @pInTableName and	[con_schemas].[name] = @pInSchema)
				or  ([ref_tables].[name]	= @pInTableName and [ref_schemas].[name] = @pInSchema))

			-- populate the CREATE statements
			---------------------------------
			insert into @create_references([statement])
			select  'alter table '					+ 
					quotename([con_schemas].[name]) + 
					'.'								+
					quotename([con_tables].[name])	+ 
					' add constraint '				+ 
					quotename([keys].[name])		+
					' foreign key ('				+
					stuff(	(	select ',' + quotename([columns].[name])
								from sys.foreign_key_columns as [foreign_cols]

									inner join sys.columns as [columns]
									on	[columns].[column_id] = [foreign_cols].[parent_column_id]
									and [columns].[object_id] = [foreign_cols].[parent_object_id] 

								where [foreign_cols].[constraint_object_id]= [keys].[object_id]
								order by [foreign_cols].[constraint_column_id]
								for xml path(N''), type).value(N'.[1]', N'nvarchar(max)'), 1, 1, N'') +
					') references '				+
					quotename([ref_schemas].[name]) + 
					'.'								+
					quotename([ref_tables].[name])	+ 
					'(' +
					stuff(	(	select ',' + quotename([columns].[name])
								from sys.foreign_key_columns as [foreign_cols]

									inner join sys.columns as [columns]
									on	[columns].[column_id] = [foreign_cols].[referenced_column_id]
									and [columns].[object_id] = [foreign_cols].[referenced_object_id] 

								where [foreign_cols].[constraint_object_id]= [keys].[object_id]
								order by [foreign_cols].[constraint_column_id]
								for xml path(N''), type).value(N'.[1]', N'nvarchar(max)'), 1, 1, N'') + 
					');'

			from [sys].[foreign_keys] as [keys]

				inner join [sys].[tables] as [ref_tables] 
				on [ref_tables].[object_id] = [keys].[referenced_object_id]

					inner join [sys].[schemas] as [ref_schemas] 
					on [ref_schemas].[schema_id] = [ref_tables].[schema_id]

				inner join [sys].[tables] as [con_tables]
				on [con_tables].[object_id] = [keys].[parent_object_id]

					inner join [sys].[schemas] as [con_schemas] 
					on [con_schemas].[schema_id] = [con_tables].[schema_id]

			where [ref_tables].[is_ms_shipped] = 0 
			and	  [con_tables].[is_ms_shipped] = 0
			and   (([con_tables].[name]	= @pInTableName and	[con_schemas].[name] = @pInSchema)
				or ([ref_tables].[name]	= @pInTableName and [ref_schemas].[name] = @pInSchema))

			-- debug out the contents of the data-tables
			--------------------------------------------
			--select * from @drop_references
			--select * from @create_references

			-- set boundaries for iteration
			-------------------------------
			select	@index_max	= max([index]),
					@index		= 1
			from	@drop_references

			-- drop all references to the table of interest
			-----------------------------------------------
			while (@index <= @index_max) 
				begin
						
					declare @drop	nvarchar(max)

					-- set the drop statement 
					-------------------------
					select	@drop  = [drop].[statement]
					from	@drop_references as [drop]
					where	[drop].[index] = @index

					print @drop

					-- drop the reference
					---------------------
					exec sp_executesql @drop

					-- iterate the counter
					----------------------
					set @index = @index + 1

				end

			-- CREATE a statement to truncate the table
			---------------------------------------
			declare @truncate nvarchar(max) = 'truncate table '+ quotename(@pInSchema) + '.' + quotename(@pInTableName) 
			print @truncate

			-- truncate the table
			---------------------
			exec sp_executesql @truncate
					

			-- set boundaries for iteration
			-------------------------------
			select	@index_max	= max([index]),
					@index		= 1
			from	@create_references

			-- drop all references to the table of interest
			-----------------------------------------------
			while (@index <= @index_max) 
				begin
						
					declare @create	nvarchar(max)

					-- set the drop statement 
					-------------------------
					select	@CREATE  = [create].[statement]
					from	@create_references as [create]
					where	[create].[index] = @index

					print @create

					-- drop the reference
					---------------------
					exec sp_executesql @create

					-- iterate the counter
					----------------------
					set @index = @index + 1

				end
			 
			-- commit local transaction
			--------------------------
			if (@TRANS_COUNTER = 0)
				commit;

		end try

		begin catch
		-----------

			-- if the transaction has been created 
			-- locally rollback the entire transaction
			-----------------------------------------
			if (@TRANS_COUNTER = 0)
				rollback transaction;
			
			if (xact_state() >= 0)

				-- log the error to core errors table
				------------------------------------
				insert into [system].[Errors]
				(
					[Number]			, 
					[Description]		, 
					[DateTime]			, 
					[StoredProcedure]	, 
					[LineNumber]		,
					[UserName]			,
					[MachineName]
				) 
				select	error_number()		as [Number]				,
						error_message()		as [Description]		,	
						getdate()			as [DateTime]			,
						error_procedure()	as [StoredProcedure]	,
						error_line()		as [LineNumber]			,
						current_user		as [UserName]			,
						@@servername		as [ServerName];

			-- throw the error up to the next layer
			---------------------------------------
			throw;

		--------
		end catch

		-- return positive response to calling party
		--------------------------------------------
		return @DATA_RESPONSE_SUCCESS

	end
