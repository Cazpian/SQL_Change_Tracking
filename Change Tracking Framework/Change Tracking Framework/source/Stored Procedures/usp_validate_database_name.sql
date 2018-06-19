


-- exec [setup].[usp_validate_database_name] @RemoteServerName = '.', @RemoteDatabaseName = 'AX_DATA_API'
create procedure [source].[usp_validate_database_name] 
(

	@RemoteServerName		[nvarchar](60)  = '.',
	@RemoteDatabaseName		[nvarchar](130) = 'AX_DATA_API'

)
as
	begin
		-- manage transactions and feedback
		-----------------------------------
		set xact_abort, nocount on;

		-- holds the default return type
		--------------------------------
		declare @Exists		bit = 0;

		begin try
		
				-- check that the database can be found on this instance.
				---------------------------------------------------------
				if (@RemoteDatabaseName	is not null)
					begin

						-- check that the server is known to the current instance.
						----------------------------------------------------------
						if	( @RemoteServerName is null )	or 
							( @RemoteServerName = '.' )		or 
							exists (	select	* 
										from	sys.servers
										where	name = @RemoteServerName ) 
							begin

								-- used to hold the statement.
								------------------------------
								declare @ParmaterDefinition nvarchar(500) = N'@RemoteDatabaseName varchar(200), @Exists bit output';  
								declare @Statement			nvarchar(max) =
								
								case when @RemoteServerName != null or @RemoteServerName != '.' 
										then [system].[udf_string_format]('

										-- check for existing message types
										-----------------------------------
										if exists (	select	top 1 1
													from	[{0}].[master].[sys].[databases] as [databases]
													where	[databases].[name] = @RemoteDatabaseName )
											select @Exists = 1;
										else
											select @Exists = 0;', @RemoteServerName )
								else 
										'-- check for existing message types
										 -----------------------------------
										 if exists (	select	top 1 1
													from	[master].[sys].[databases] as [databases]
													where	[databases].[name] = @RemoteDatabaseName )
											select @Exists = 1;
										 else
											select @Exists = 0;'
								end;

								-- execute the procedure and return the response.
								-------------------------------------------------
								execute sp_executesql @Statement,	@ParmaterDefinition,  
																	@RemoteDatabaseName = @RemoteDatabaseName,
																	@Exists				= @Exists output;


						end
					else
						throw 51001, 'Server or linked server can''t be found.', 1;   		
					end 

		end try

		begin catch
		-----------
			
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
		return @Exists

	end