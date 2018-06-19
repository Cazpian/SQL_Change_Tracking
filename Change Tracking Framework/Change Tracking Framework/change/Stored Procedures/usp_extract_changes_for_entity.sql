


CREATE procedure [change].[usp_extract_changes_for_entity]

	@EntityID	int = 3
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

				declare @timestamp		datetime = getdate()
				declare @database_name	nvarchar(150)
				declare @server			nvarchar(150)
				declare @entity_id		int
				declare @entity_name	nvarchar(200)
				declare @entity_schema	nvarchar(200)
				declare @version		int = 1

				-- get the database and entity information
				------------------------------------------
				select	@database_name	= [Authorities].[Database]	,
						@server			= [Authorities].[Server]	,
						@entity_id		= [Entities].[EntityID]		,
						@entity_name	= [Entities].[Name]			,
						@entity_schema	= [Entities].[Schema]		,
						@version		= isnull(max([EntityVersionLog].[Version]), 0)
				from	[source].[Entities]

					inner join [source].[Authorities]
					on [Entities].[AuthorityID] = [Authorities].[AuthorityID]
					
					left join [change].[EntityVersionLog]
					on [EntityVersionLog].[EntityID] = [Entities].[EntityID]

				where [source].[Entities].[EntityID] = @EntityID
				group by	[Authorities].[Database]	,
							[Authorities].[Server]		,
							[Entities].[EntityID]		,
							[Entities].[Name]			,
							[Entities].[Schema]		

				-- defines the parameters that are passes into the execution statement.
				-----------------------------------------------------------------------
				declare @params nvarchar(500) = N'@statement nvarchar(max), @success bit output, @changes xml output'; 
				declare @success			bit = 0;
				declare @changes			xml;

				-- execution needs to take place on the remote server so we'll pass this into the execution statement
				-----------------------------------------------------------------------------------------------------
				declare @Execution	 nvarchar(500) =	case when @Server is not null and @Server != '.'
																then  [system].[udf_string_format](	N'declare @Params nvarchar(500) = N''@success bit output, @changes xml output'';
																										execute [{0}].[master].[dbo].sp_executesql @statement, @params, @success output, @changes output; ', @Server)
															
														else										N'declare @Params nvarchar(500) = N''@success bit output, @changes xml output'';
																										execute [master].[dbo].sp_executesql @statement, @params, @success output, @changes output;'
														end;


				-- contains the script to enable change tracking at the database level
				----------------------------------------------------------------------
				declare @Statement nvarchar(max) = [system].[udf_string_format]('

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
					
							-- return the change information in the xml 
							-------------------------------------------
							set @changes = (
									select	''{2}.{1}''					as [@entity]		,
											max(sys_change_version)		as [max_version]	, 
											getdate()					as [processed]		,
											count(sys_change_version)	as [change_count]	,
	
										(
												select	
													sys_change_version			as [@version]	,
													sys_change_operation		as [@operation]	,
													sys_change_context			as [context]	,
													{key_columns}	
		
												from	changetable (changes [{0}].[{2}].[{1}], {3})  as bob
												for xml path(''change''), type) as [all_changes]

									from	changetable (changes [{0}].[{2}].[{1}], {3}) as [changes]
									for xml path(''entity_changes''))

							-- return success
							-----------------
							set @success = 1;

						end;

					', concat(@database_name, char(44), @entity_name, char(44), @entity_schema, char(44), @version));

					-- replace the primary key column tag with the actual key values
					----------------------------------------------------------------
					set @Statement = replace(@Statement, '{key_columns}', [source].[get_primary_key_columns](@EntityID));

					-- execute the procedure and return the response.
					-------------------------------------------------
					execute sp_executesql @Execution,
							@params, 
							@statement	= @statement,
							@success	= @success		output,
							@changes	= @changes		output;

					-- insert the change tracking information into the version - log
					----------------------------------------------------------------
					insert into [change].[EntityVersionLog] ([EntityID], [Version], [Count], [Started], [Duration])
					select	@entity_id											as [EntityID]	,
							x.y.value('max_version[1]',		'int')				as [MaxVersion]	,
							x.y.value('change_count[1]',	'int')				as [Count]		,
							x.y.value('processed[1]',		'datetime')			as [Started]	,
							datediff(second, @timestamp, x.y.value('processed[1]', 'datetime')) as [Duration]
					from	@changes.nodes('/entity_changes') x(y)

					insert into [change].[ItemLog] ([EntityVersionLogID], [Version], [Operation], [Context], [ID])
					select	scope_identity(),
							x.y.value('@version',	'nvarchar(200)') as [version],
							x.y.value('@operation', 'nvarchar(200)') as [operation],
							x.y.value('context[1]',	'varbinary(128)') as [context],
							x.y.query('.')
					from	@changes.nodes('/entity_changes/all_changes/change') x(y)

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
