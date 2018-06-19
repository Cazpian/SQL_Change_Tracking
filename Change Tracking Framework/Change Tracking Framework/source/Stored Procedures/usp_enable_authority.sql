


CREATE procedure [source].[usp_enable_authority]

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
					declare @Statement nvarchar(max) =[system].[udf_string_format]('

						if not exists ( select top 1 1 
										from sys.change_tracking_databases as tracking

											inner join sys.databases as dbs
											on dbs.database_id = tracking.database_id

										where dbs.name = ''{0}'')

							-- turn on change tracking for the database
							-------------------------------------------
							alter database [{0}]
							set change_tracking		= on
							(	change_retention	= {1} hours,
								auto_cleanup = on);', concat(@DatabaseName, char(44), @Retention));


					-- execute the procedure and return the response.
					-------------------------------------------------
					execute sp_executesql @Execution,
							@ParmaterDefinition, 
							@Statement = @Statement;

					-- turn on change tracking for all associated entities
					------------------------------------------------------
					exec [source].[usp_enable_entities] @AuthorityID = @AuthorityID;


					print 'Authority Change Tracking - ENABLED';

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
