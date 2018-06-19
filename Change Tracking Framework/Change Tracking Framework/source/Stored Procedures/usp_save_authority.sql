


CREATE procedure [source].[usp_save_authority]

	@Name					[nvarchar](150)		= 'API DEVELOPMENT'	,
	@RemoteServerName		[nvarchar](130)		= '.'				,
	@RemoteDatabaseName		[nvarchar](60)		= 'AX_DATA_API'		,
	@RententionInHours		[int]				= 48

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

				declare @ValidateParameters			bit

				-- check to see if the servername and database exists
				-----------------------------------------------------
				exec @ValidateParameters = [source].[usp_validate_database_name]  @RemoteServerName = @RemoteServerName, @RemoteDatabaseName = @RemoteDatabaseName

				-- check that these details are not already resident
				----------------------------------------------------
				if exists ( select	top 1 1 
							from	[source].[Authorities] as [Auth]
							where	[Auth].[Server]		 = @RemoteServerName
							and		[Auth].[Database]	 = @RemoteDatabaseName
							and		[Auth].[Name]		!= @Name )
					throw 51003, 'Authority already exists under different name.', 1;   

				-- check that the database can be found on this instance.
				---------------------------------------------------------
				if ( @ValidateParameters = 'true' )
					begin

						-- get the local broker instance
						--------------------------------
						declare @BrokerInstance varchar(36) 

						-- get the local TCP endpoint settings 
						--------------------------------------
						declare @EndPoint varchar(56) 

						-- used to hold the statement.
						------------------------------
						declare @Statement nvarchar(max) = [system].[udf_string_format]('

								use [{0}];

								select	@RemoteBrokerInstance = [service_broker_guid]
								from	[sys].[databases] 
								where   [database_id] = DB_ID(''{0}''); 
							
								select	@RemoteEndPoint = N''TCP://'' + convert(nvarchar(120), serverproperty(''MachineName'')) + '':'' + convert(nvarchar(6), [port])
								from  [sys].[tcp_endpoints]
								where [name] = ''ServiceBrokerEndpoint''

						', @RemoteDatabaseName);	

						-- defines the parameters used to create the dynamic pass-through query
						-----------------------------------------------------------------------
						declare @ParameterDefinition			nvarchar(500) = N'@Statement nvarchar(max), @BrokerInstance nvarchar(36) output, @EndPoint nvarchar(56) output'; 
						declare @Execution nvarchar(500) = 
						
								case when @RemoteServerName != null or @RemoteServerName != '.' 
										then [system].[udf_string_format](
										N'  declare @Parameters	 nvarchar(500) = N''@RemoteBrokerInstance nvarchar(36) output, @RemoteEndPoint nvarchar(56) output''; 

											execute [{0}].[master].[dbo].sp_executesql @Statement, @Parameters, 
													@RemoteBrokerInstance	= @BrokerInstance	output,
													@RemoteEndPoint			= @EndPoint			output;', @RemoteServerName)
								else 
										N'  declare @Parameters	 nvarchar(500) = N''@RemoteBrokerInstance nvarchar(36) output, @RemoteEndPoint nvarchar(56) output''; 

											execute [master].[dbo].sp_executesql @Statement, @Parameters, 
													@RemoteBrokerInstance	= @BrokerInstance	output,
													@RemoteEndPoint			= @EndPoint			output;'
								end;
						
	
						-- we need to execute this procedure on the remote server so that it picks up the correct server and endpoint information
						-- we thus have to do a double dynamic pass-through query as the servname on which this is to run needs to be passed into the query.
						-------------------------------------------------
						execute sp_executesql @Execution, @ParameterDefinition,
								@Statement		= @Statement,
								@BrokerInstance = @BrokerInstance	output,
								@EndPoint		= @EndPoint			output;

						-- check for existing record with the same name
						-----------------------------------------------
						if not exists ( select	top 1 1
										from	[source].[Authorities] as [auth]
										where	[auth].[Name] = @Name )

							-- create the authority record with the mined information
							---------------------------------------------------------
							insert into [source].[Authorities]
							(
								[Name]				, 
								[Database]			, 
								[Server]			, 
								[EndPoint]			,
								[Broker]			,
								[RetentionInHours]	,
								[Active]
							)
							select	@Name				as [Name]		,
									@RemoteDatabaseName	as [Database]	,
									@RemoteServerName	as [Server]		,
									@EndPoint			as [EndPoint]	,
									@BrokerInstance		as [Broker]		,
									@RententionInHours	as [Retention]	,
									case when ((@EndPoint is not null) 
										   and (@BrokerInstance is not null)) then 1
									else 0 end			as [Active]
							
						else

							-- update the authority record
							------------------------------ 
							update	[source].[Authorities]
							set		[Database]	= @RemoteDatabaseName	,
									[Server]	= @RemoteServerName		,
									[EndPoint]	= @EndPoint				,
									[Broker]	= @BrokerInstance		
							where	[Name]		= @Name

					end
				else
					throw 51000, 'Invalid server name or database name passed into the stored procedure.', 1;  

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
