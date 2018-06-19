


CREATE procedure [source].[usp_disable_authority]

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
		
			declare @DatabaseName	nvarchar(150)
			declare @Server			nvarchar(150)
			declare @Retention		int 

			-- get the information required to setup the change tracking
			------------------------------------------------------------
			select	@DatabaseName	= [Auth].[Database]				,
					@Server			= [Auth].[Server]				,
					@Retention		= [Auth].[RetentionInHours]

			from	[source].[Authorities] as [Auth]
			where	[Auth].[AuthorityID] = @AuthorityID

			declare @ValidateParameters			bit

			-- check to see if the servername and database exists
			-----------------------------------------------------
			exec @ValidateParameters = [source].[usp_validate_database_name]  @RemoteServerName = @Server, @RemoteDatabaseName = @DatabaseName

			-- check that the database can be found on this instance.
			---------------------------------------------------------
			if ( @ValidateParameters = 'true' )
				begin

					-- defines the parameters that are passes into the execution statement.
					-----------------------------------------------------------------------
					declare @ParmaterDefinition nvarchar(500) = N'@Statement nvarchar(max)'; 

					-- execution needs to take place on the remote server so we'll pass this into the execution statement
					-----------------------------------------------------------------------------------------------------
					declare @Execution	 nvarchar(500) =	case when @Server is not null and @Server != '.'
																	then  [system].[udf_string_format](N'execute [{0}].[master].[dbo].sp_executesql @Statement;', @Server)
															else	N'execute [master].[dbo].sp_executesql @Statement;'
															end;


					-- contains the script to enable change tracking at the database level
					----------------------------------------------------------------------
					declare @Statement nvarchar(max) = [system].[udf_string_format]('

						if exists ( select top 1 1 
									from master.sys.change_tracking_databases as tracking

										inner join master.sys.databases as dbs
										on dbs.database_id = tracking.database_id

									where dbs.name = ''{0}'')
							begin

								-- create cursor for cycling through 
								------------------------------------
								declare entity_tracking_cursor cursor for
								select	upper(tables.name)	,
										upper(schemas.name)
								from	{0}.sys.change_tracking_tables 

									inner join {0}.sys.tables
									on change_tracking_tables.object_id = tables.object_id

										inner join {0}.sys.schemas
										on schemas.schema_id = tables.schema_id


								open entity_tracking_cursor;

								while 1 = 1
								begin

									declare @entity_name	nvarchar(200)
									declare @entity_schema	nvarchar(200)

									-- get the next item from the cursor
									------------------------------------
									fetch next from entity_tracking_cursor
									into @entity_name, @entity_schema;

									-- break on nothing retrieved
									-----------------------------
									if (@@fetch_status != 0) break;

									-- contains the script to disable change tracking at the entity level
									----------------------------------------------------------------------
									declare @Statement nvarchar(max) = formatmessage(''

											-- turn on change tracking for the database
											-------------------------------------------
											alter table [{0}].[%s].[%s]
											disable change_tracking;'', @entity_schema, @entity_name);

									-- execute the procedure and return the response.
									-------------------------------------------------
									execute sp_executesql @Statement;

									print formatmessage(''Entity Change tracking disabled for : [{0}].[%s].[%s]'', @entity_schema, @entity_name);

								end

								close         entity_tracking_cursor;
								deallocate    entity_tracking_cursor;

								-- remove change tracking at the database level
								-----------------------------------------------
								alter database AX_DATA_API
								set change_tracking = off;

							end;', @DatabaseName);

					-- execute the procedure and return the response.
					-------------------------------------------------
					execute sp_executesql @Execution,
							@ParmaterDefinition, 
							@Statement = @Statement;

					print 'Authority Change Tracking - DISABLED';

				end  

		end try

		begin catch
		-----------

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
