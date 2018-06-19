


CREATE procedure [source].[usp_add_entity_tracking]

	@AuthorityID	int				= 1	,
	@EntityName		nvarchar(150)	= 'products',
	@EntitySchema	nvarchar(150)	= 'invt'
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

				-- check for existing record with the same name
				-----------------------------------------------
				if not exists ( select	top 1 1
								from	[source].[Entities] as [entity]
								where	[entity].[Name]		= @EntityName
								and		[entity].[Schema]	= @EntitySchema )

					-- create the authority record with the mined information
					---------------------------------------------------------
					insert into [source].[Entities]
					(
						[AuthorityID]	, 
						[Name]			, 
						[Schema]
					)
					select	@AuthorityID				as [Name]		,
							upper(@EntityName)			as [Database]	,
							upper(@EntitySchema)		as [Server]		;
						

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
