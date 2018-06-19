


CREATE procedure [setup].[usp_intialise]
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
				
				--exec [system].[usp_sys_truncate_table] 'source',	'EntityKeys'
				--exec [system].[usp_sys_truncate_table] 'source',	'Entities'
				--exec [system].[usp_sys_truncate_table] 'source',	'Authorities'
				

				delete [source].[EntityKeys]
				delete [source].[Entities]
				delete [source].[Authorities]
				
				-- add authority for change tracking
				------------------------------------
				exec [source].[usp_save_authority] @Name = 'AX UAT ENVIRONMENT', @RemoteServerName = '.', @RemoteDatabaseName = 'AX_DATA_API' , @RententionInHours = 48;

				-- get a reference to the newly created authority
				-------------------------------------------------
				declare @AuthorityID	int = (select MAX([Authorities].[AuthorityID]) from [source].[Authorities]);

				-- add change tracking at the entity level
				------------------------------------------
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'PRODUCTS';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'STOCK';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'STOCKQUANTITIES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'ATTRIBUTES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'ATTRIBUTEVALUES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'ATTRIBUTEENUMVALUES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'STOCKREGIONALSIZES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'STOCKSIZESGEOGROUPS';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'INVT', @EntityName = 'STOCKWAREHOUSES';

				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'CUST', @EntityName = 'ADDRESSES';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'CUST', @EntityName = 'ADDRESSCONTACTS';
				exec [source].[usp_add_entity_tracking] @AuthorityID = @AuthorityID,  @EntitySchema = 'CUST', @EntityName = 'CUSTOMERS';

				-- implement change tracking on the remote database
				---------------------------------------------------
				exec [source].[usp_enable_authority] @AuthorityID;


				select * from  [source].[EntityKeys]
				select * from  [source].[Entities]
				select * from  [source].[Authorities]

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
