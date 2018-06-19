


CREATE procedure [source].[usp_enable_entities]

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
				declare entities_cursor cursor for
				select	[Entities].[EntityID]		,
						[Entities].[Active]			,
						[Authorities].[Database]	,
						[Authorities].[Server]		,
						[Entities].[Name]			,
						[Entities].[Schema]
				from	[source].[Entities]

					inner join [source].[Authorities]
					on [Entities].[AuthorityID] = [Authorities].[AuthorityID]

				where [Authorities].[AuthorityID] = @AuthorityID

				open entities_cursor;

				while 1 = 1
				begin

					declare @DatabaseName	nvarchar(150)
					declare @Server			nvarchar(150)
					declare @entity_name	nvarchar(200)
					declare @entity_schema	nvarchar(200)
					declare @entity_id		int
					declare @entity_active	bit
					

					-- get the next item from the cursor
					------------------------------------
					fetch next from entities_cursor
					into @entity_id, @entity_active, @DatabaseName, @Server, @entity_name, @entity_schema;

					-- break on nothing retrieved
					-----------------------------
					if (@@fetch_status != 0) break;

					-- remove any previously known keys
					-----------------------------------
					delete	[EntityKeys]
					where	[EntityKeys].[EntityID] = @entity_id

					-- defines the parameters that are passes into the execution statement.
					-----------------------------------------------------------------------
					declare @ParmaterDefinition nvarchar(500) = N'@Statement nvarchar(max), @Success bit output, @Keys xml output'; 
					declare @Success			bit = 0;
					declare @Keys				xml;

					-- execution needs to take place on the remote server so we'll pass this into the execution statement
					-----------------------------------------------------------------------------------------------------
					declare @Execution	 nvarchar(500) =	case when @Server is not null and @Server != '.'
																	then  [system].[udf_string_format](	N'declare @Params nvarchar(500) = N''@Success bit output, @Keys xml output'';
																										  execute [{0}].[master].[dbo].sp_executesql @Statement, @Params, @Success output, @Keys output; ', @Server)
															
															else										N'declare @Params nvarchar(500) = N''@Success bit output, @Keys xml output'';
																										  execute [master].[dbo].sp_executesql @Statement, @Params, @Success output, @Keys output;'
															end;


					-- contains the script to enable change tracking at the database level
					----------------------------------------------------------------------
					declare @Statement nvarchar(max) = [system].[udf_string_format]('

						-- check to see if the change tracking is already on for this entity
						--------------------------------------------------------------------
						if not exists ( select top 1 1 
										from	{0}.sys.change_tracking_tables 

											inner join {0}.sys.tables
											on change_tracking_tables.object_id = tables.object_id

												inner join {0}.sys.schemas
												on schemas.schema_id = tables.schema_id

										where	tables.name		= ''{1}'' 
										and		schemas.name	= ''{2}'')
							begin

								-- check to see if table exists
								-------------------------------
								if exists ( select top 1 1 
											from {0}.sys.tables

												inner join {0}.sys.schemas
												on schemas.schema_id = tables.schema_id

											where	tables.name		= ''{1}'' 
											and		schemas.name	= ''{2}'') 
									begin 

										-- turn on change tracking for the database
										-------------------------------------------
										alter table [{0}].[{2}].[{1}]
										enable change_tracking
										with (track_columns_updated = off);
								
										print ''Entity Change tracking enabled for : [{0}].[{2}].[{1}]'';

										-- return success
										-----------------
										set @Success = 1;

									end 
								else 
									print ''** ERROR: Entity Not Found : [{0}].[{2}].[{1}]'';

							end;
						else
							-- return success
							-----------------
							set @Success = 1;
							
						-- extract the primary key information for the remote entity
						------------------------------------------------------------
						select @keys = ( 
							select	schemas.name		as [@schema],
									tables.name			as [@entity],
		
									indexes.name		as [primary_keys/@name],
									(
										select	columns.name	as [column_name]
										from	{0}.sys.index_columns 

											inner join {0}.sys.columns 
											on	index_columns.object_id = columns.object_id 
											and index_columns.column_id = columns.column_id

										where	indexes.object_id = index_columns.object_id 
										and		indexes.index_id  = index_columns.index_id

										for xml path(''''), type) as [primary_keys]

							from {0}.sys.tables

								inner join {0}.sys.schemas
								on schemas.schema_id = tables.schema_id

								inner join {0}.sys.change_tracking_tables
								on change_tracking_tables.object_id = tables.object_id

								inner join {0}.sys.indexes
								on	indexes.object_id = tables.object_id
								and indexes.is_primary_key = 1

							where	tables.name		= ''{1}'' 
							and		schemas.name	= ''{2}''	
							order by tables.object_id
							for xml path(''entity''), root(''entities''));
							
							', concat(@DatabaseName, char(44), @entity_name, char(44), @entity_schema));

					-- execute the procedure and return the response.
					-------------------------------------------------
					execute sp_executesql @Execution,
							@ParmaterDefinition, 
							@Statement	= @Statement,
							@Success	= @Success	output,
							@Keys		= @Keys		output;

					-- update the status of the entity
					---------------------------------
					if (@Success != isnull(@entity_active, 0))
						update	[source].[Entities]
						set		[Active]	= @Success
						where	[EntityID]	= @entity_id

					-- key for returning primary key information
					--------------------------------------------
					if (@Keys is not null)

						-- return the known entity with the primary-key information.
						------------------------------------------------------------
						insert into [source].[EntityKeys] ( [EntityID], [Name] )
						select	[Entities].[EntityID]			as [EntityID],
								col.value('.', 'nvarchar(200)')	as [Name]

						from   @Keys.nodes('//entity/primary_keys/column_name') x(col)

							inner join [source].[Entities] 
							on	[Entities].[AuthorityID] = @AuthorityID
							and [Entities].[Name]	= col.value('../../@entity[1]', 'nvarchar(150)')
							and [Entities].[Schema] = col.value('../../@schema[1]', 'nvarchar(150)')


				end

				close         entities_cursor;
				deallocate    entities_cursor;

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
