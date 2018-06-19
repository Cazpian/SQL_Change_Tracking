


create procedure [change].[usp_extract_changes_for_authority]

	@AuthorityID	int = 1

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

			-- is procedure nested in existing transaction
			---------------------------------------------
			if (@TRANS_COUNTER > 0)
			save transaction procedure_rollback_point;

				-- create cursor for cycling through 
				------------------------------------
				declare entity_sync_cursor cursor for
				select	[Entities].[EntityID]					as [EntityID]	,
						[Authorities].[Database]				as [Database]	,
						[Authorities].[Server]					as [Server]		,
						[Entities].[Name]						as [Name]		,
						[Entities].[Schema]						as [Schema]		,
						isnull([Versions].[ExtractVersion], 0)	as [Version]

				from	[source].[Entities]

					inner join [source].[Authorities]
					on [Entities].[AuthorityID] = [Authorities].[AuthorityID]

						outer apply (
										select	max([Version]) as [ExtractVersion]
										from	[sync].[EntityChangeLog] as [log]
										where	[log].[EntityID] = [Entities].[EntityID] 

									 ) as [Versions]



				where	[Authorities].[AuthorityID] = 1  -- @AuthorityID
				and		[Entities].[Active] = 1

				open entity_sync_cursor;

				while 1 = 1
				begin

					declare @DatabaseName	nvarchar(150)
					declare @Server			nvarchar(150)
					declare @entity_name	nvarchar(200)
					declare @entity_schema	nvarchar(200)
					declare @entity_id		int
					declare @version		int
					
					-- get the next item from the cursor
					------------------------------------
					fetch next from entity_sync_cursor
					into @entity_id, @DatabaseName, @Server, @entity_name, @entity_schema, @version;

					-- break on nothing retrieved
					-----------------------------
					if (@@fetch_status != 0) break;

					-- defines the parameters that are passes into the execution statement.
					-----------------------------------------------------------------------
					declare @ParmaterDefinition nvarchar(500) = N'@Statement nvarchar(max)'; 

					-- execution needs to take place on the remote server so we'll pass this into the execution statement
					-----------------------------------------------------------------------------------------------------
					declare @Execution	 nvarchar(500) =	case when @Server is not null and @Server != '.'
																	then  [system].[udf_string_format](	N'execute [{0}].[master].[dbo].sp_executesql @Statement; ', @Server)
															
															else										N'execute [master].[dbo].sp_executesql @Statement;'
															end;


					-- contains the script to enable change tracking at the database level
					----------------------------------------------------------------------
					declare @Statement nvarchar(max) = [system].[udf_string_format]('

						declare @last_sync_version		int = {3}

						-- check to see if the change tracking is already on for this entity
						--------------------------------------------------------------------
						if exists ( select top 1 1 
									from	{0}.sys.change_tracking_tables 

										inner join {0}.sys.tables
										on change_tracking_tables.object_id = tables.object_id

											inner join {0}.sys.schemas
											on schemas.schema_id = tables.schema_id

									where	tables.name		= ''{1}'' 
									and		schemas.name	= ''{2}'')
							begin
				
								select	*  
								from	CHANGETABLE (CHANGES [{0}].[{2}].[{1}], @last_sync_version) as [changes];

								print '' get change information for [{0}].[{2}].[{1}]'';

							end;
						', concat(@DatabaseName, char(44), @entity_name, char(44), @entity_schema, char(44), @version));

					-- execute the procedure and return the response.
					-------------------------------------------------
					execute sp_executesql @Execution,
							@ParmaterDefinition, 
							@Statement	= @Statement;


				end

				close entity_sync_cursor;
				deallocate entity_sync_cursor;

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
			else
			
			-- confirm the state of the current transaction and see if we can rollback 
			-- to our locally saved transaction save point. Note: if the transaction
			-- is uncommittable, a rollback to the save-point is not allowed
			-------------------------------------------------------------------------
			if (xact_state() > 0)
			rollback transaction procedure_rollback_point;

			-- log the error to core errors table
			------------------------------------
			if (xact_state() >= 0)
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
